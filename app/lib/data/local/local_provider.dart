import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/models.dart';
import '../../domain/music_provider.dart';
import '../../src/rust/api/library.dart' as lib;
import '../lastfm.dart';
import '../online_meta.dart';

String _id(String prefix, String key) => '$prefix${sha1.convert(utf8.encode(key)).toString().substring(0, 16)}';

class _Stats {
  int plays = 0;
  DateTime? lastPlayed;
  DateTime? starred;
  int rating = 0;

  Map<String, dynamic> toJson() => {
        if (plays > 0) 'p': plays,
        if (lastPlayed != null) 'l': lastPlayed!.millisecondsSinceEpoch,
        if (starred != null) 's': starred!.millisecondsSinceEpoch,
        if (rating > 0) 'r': rating,
      };

  static _Stats fromJson(Map<String, dynamic> j) => _Stats()
    ..plays = j['p'] as int? ?? 0
    ..lastPlayed = j['l'] is int ? DateTime.fromMillisecondsSinceEpoch(j['l'] as int) : null
    ..starred = j['s'] is int ? DateTime.fromMillisecondsSinceEpoch(j['s'] as int) : null
    ..rating = j['r'] as int? ?? 0;

  bool get isEmpty => plays == 0 && starred == null && rating == 0;
}

class _LocalPlaylist {
  _LocalPlaylist(this.id, this.name, this.songIds, this.changed);
  final String id;
  String name;
  final List<String> songIds;
  DateTime changed;
}

/// Músicas do aparelho, sem servidor. O motor lê as tags e as capas (índice
/// incremental); aqui viram álbuns, artistas e gêneros. Favoritos, execuções,
/// "tocadas recentemente" e playlists ficam em arquivos locais. "Parecidas"
/// vêm do Last.fm quando há chave, senão do mesmo artista e gênero.
class LocalProvider implements MusicProvider {
  LocalProvider({required this.supportDir, required List<String> folders, this.lastFm}) : folders = List.of(folders);

  final String supportDir;
  List<String> folders;
  LastFm? lastFm;

  /// Chamado quando capas novas chegam da internet (recarregar telas).
  void Function()? onChanged;
  final _onlineCover = <String, String>{};
  List<lib.LocalTrack> _tracks = const [];

  static const accountIdValue = 'local';

  String get _indexPath => p.join(supportDir, 'local_library.json');
  String get _coversDir => p.join(supportDir, 'local_covers');
  File get _statsFile => File(p.join(supportDir, 'local_stats.json'));
  File get _playlistsFile => File(p.join(supportDir, 'local_playlists.json'));

  List<Song> _songs = const [];
  final _byId = <String, Song>{};
  final _albums = <String, Album>{};
  final _albumOf = <String, String>{}; // song id → album id
  final _artists = <String, Artist>{};
  final _stats = <String, _Stats>{};
  final _playlists = <String, _LocalPlaylist>{};
  final _rnd = Random();

  int get songCount => _songs.length;

  @override
  String get accountId => accountIdValue;

  @override
  ServerInfo? get serverInfo => const ServerInfo(type: 'local', version: '', apiVersion: '', openSubsonic: false);

  @override
  Future<ServerInfo> connect() async {
    await _loadOnlineCovers();
    _build(await lib.libraryLoad(indexPath: _indexPath));
    await _loadStats();
    await _loadPlaylists();
    return serverInfo!;
  }

  /// Varre as pastas de novo (só relê o que mudou). Devolve o total de músicas.
  Future<int> rescan() async {
    final tracks = await lib.libraryScan(folders: folders, indexPath: _indexPath, coversDir: _coversDir);
    _build(tracks);
    return tracks.length;
  }

  static int scanProgress() => lib.libraryScanProgress();

  // ---- Índice → modelos ----

  Future<void> _loadOnlineCovers() async {
    try {
      final dir = Directory(_coversDir);
      if (!await dir.exists()) return;
      await for (final f in dir.list()) {
        final name = p.basename(f.path);
        if (name.startsWith('online_')) _onlineCover[p.basenameWithoutExtension(name).substring(7)] = f.path;
      }
    } catch (_) {}
  }

  /// Busca na internet as capas dos álbuns que não têm (iTunes, Deezer), em
  /// segundo plano. Álbuns sem resultado só são tentados de novo em 7 dias.
  Future<void> fillMissingCovers() async {
    final missesFile = File(p.join(_coversDir, 'online_misses.json'));
    final misses = <String, int>{};
    try {
      if (await missesFile.exists()) {
        (jsonDecode(await missesFile.readAsString()) as Map).forEach((k, v) => misses['$k'] = v as int);
      }
    } catch (_) {}
    final now = DateTime.now().millisecondsSinceEpoch;
    final todo = _albums.values
        .where((a) => a.coverArt == null && now - (misses[a.id] ?? 0) > const Duration(days: 7).inMilliseconds)
        .toList();
    var found = 0;
    for (final a in todo) {
      final path = await fetchAlbumCover(artist: a.artist ?? '', album: a.name, dir: _coversDir, id: a.id);
      if (path != null) {
        _onlineCover[a.id] = path;
        found++;
        // Aplica aos poucos (a lista pode ser grande).
        if (found % 10 == 0) {
          _build(_tracks);
          onChanged?.call();
        }
      } else {
        misses[a.id] = now;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    try {
      await missesFile.writeAsString(jsonEncode(misses));
    } catch (_) {}
    if (found > 0) {
      _build(_tracks);
      onChanged?.call();
    }
  }

  void _build(List<lib.LocalTrack> tracks) {
    _tracks = tracks;
    _byId.clear();
    _albums.clear();
    _albumOf.clear();
    _artists.clear();
    final albumSongs = <String, List<Song>>{};
    final albumInfo = <String, (String name, String? artist, String? cover, int? year, int mtime)>{};
    for (final t in tracks) {
      final dir = p.dirname(t.path);
      final albumName = t.album ?? p.basename(dir);
      final albumArtist = t.albumArtist ?? t.artist;
      // Álbum = nome + artista do álbum; sem artista do álbum, a pasta separa.
      final albumId = _id('a', '${albumName.toLowerCase()}|${t.albumArtist?.toLowerCase() ?? dir}');
      final genres = (t.genre ?? '').split(RegExp(r'[;/]')).map((g) => g.trim()).where((g) => g.isNotEmpty).toList();
      final cover = t.cover ?? _onlineCover[albumId];
      final song = Song(
        id: _id('s', t.path),
        title: t.title,
        album: albumName,
        albumId: albumId,
        artist: t.artist,
        artistId: t.artist == null ? null : _id('r', t.artist!.toLowerCase()),
        albumArtist: t.albumArtist,
        track: t.track,
        disc: t.disc,
        year: t.year,
        genre: genres.firstOrNull,
        genres: genres,
        coverArt: cover,
        duration: t.durationMs == null ? null : Duration(milliseconds: t.durationMs!),
        bitRate: t.bitrateKbps,
        sampleRate: t.sampleRate,
        bitDepth: t.bitDepth,
        channels: t.channels,
        suffix: p.extension(t.path).replaceFirst('.', '').toLowerCase(),
        size: t.size,
        bpm: t.bpm,
        replayGain: (t.rgTrackGain == null && t.rgAlbumGain == null)
            ? null
            : ReplayGain(
                trackGain: t.rgTrackGain,
                albumGain: t.rgAlbumGain,
                trackPeak: t.rgTrackPeak,
                albumPeak: t.rgAlbumPeak,
              ),
        path: t.path,
      );
      _byId[song.id] = song;
      _albumOf[song.id] = albumId;
      (albumSongs[albumId] ??= []).add(song);
      final prev = albumInfo[albumId];
      albumInfo[albumId] = (
        albumName,
        prev?.$2 ?? albumArtist,
        prev?.$3 ?? cover,
        prev?.$4 ?? t.year,
        max(prev?.$5 ?? 0, t.mtime),
      );
    }
    for (final e in albumSongs.entries) {
      final songs = e.value
        ..sort((a, b) {
          final d = (a.disc ?? 1).compareTo(b.disc ?? 1);
          if (d != 0) return d;
          final t = (a.track ?? 9999).compareTo(b.track ?? 9999);
          return t != 0 ? t : a.title.compareTo(b.title);
        });
      final info = albumInfo[e.key]!;
      final artist = info.$2;
      _albums[e.key] = Album(
        id: e.key,
        name: info.$1,
        artist: artist,
        artistId: artist == null ? null : _id('r', artist.toLowerCase()),
        coverArt: info.$3,
        songCount: songs.length,
        duration: songs.fold<Duration>(Duration.zero, (d, s) => d + (s.duration ?? Duration.zero)),
        year: info.$4,
        genre: songs.map((s) => s.genre).whereType<String>().firstOrNull,
        created: DateTime.fromMillisecondsSinceEpoch(info.$5 * 1000),
        songs: songs,
      );
    }
    // Artistas: do álbum e das faixas.
    final artistAlbums = <String, (String name, Set<String> albums, String? cover)>{};
    void addArtist(String? name, String albumId, String? cover) {
      if (name == null || name.trim().isEmpty) return;
      final id = _id('r', name.toLowerCase());
      final cur = artistAlbums[id];
      artistAlbums[id] = (cur?.$1 ?? name, (cur?.$2 ?? <String>{})..add(albumId), cur?.$3 ?? cover);
    }

    for (final a in _albums.values) {
      addArtist(a.artist, a.id, a.coverArt);
      for (final s in a.songs) {
        addArtist(s.artist, a.id, a.coverArt);
      }
    }
    for (final e in artistAlbums.entries) {
      _artists[e.key] = Artist(id: e.key, name: e.value.$1, coverArt: e.value.$3, albumCount: e.value.$2.length);
    }
    _songs = _byId.values.toList()
      ..sort((a, b) {
        final c = (a.albumArtist ?? a.displayArtist).toLowerCase().compareTo((b.albumArtist ?? b.displayArtist).toLowerCase());
        if (c != 0) return c;
        final al = (a.album ?? '').toLowerCase().compareTo((b.album ?? '').toLowerCase());
        if (al != 0) return al;
        final d = (a.disc ?? 1).compareTo(b.disc ?? 1);
        return d != 0 ? d : (a.track ?? 0).compareTo(b.track ?? 0);
      });
  }

  Song _withStats(Song s) {
    final st = _stats[s.id];
    if (st == null) return s;
    return Song(
      id: s.id,
      title: s.title,
      album: s.album,
      albumId: s.albumId,
      artist: s.artist,
      artistId: s.artistId,
      artists: s.artists,
      albumArtist: s.albumArtist,
      track: s.track,
      disc: s.disc,
      year: s.year,
      genre: s.genre,
      genres: s.genres,
      coverArt: s.coverArt,
      duration: s.duration,
      bitRate: s.bitRate,
      sampleRate: s.sampleRate,
      bitDepth: s.bitDepth,
      channels: s.channels,
      suffix: s.suffix,
      size: s.size,
      starred: st.starred,
      userRating: st.rating == 0 ? null : st.rating,
      playCount: st.plays,
      bpm: s.bpm,
      replayGain: s.replayGain,
      path: s.path,
    );
  }

  Album _albumWithStats(Album a, {bool songs = false}) {
    final st = _stats[a.id];
    return Album(
      id: a.id,
      name: a.name,
      artist: a.artist,
      artistId: a.artistId,
      coverArt: a.coverArt,
      songCount: a.songCount,
      duration: a.duration,
      year: a.year,
      genre: a.genre,
      starred: st?.starred,
      playCount: a.songs.fold<int>(0, (n, s) => n + (_stats[s.id]?.plays ?? 0)),
      created: a.created,
      songs: songs ? a.songs.map(_withStats).toList() : const [],
    );
  }

  // ---- Estatísticas e playlists (arquivos locais) ----

  Future<void> _loadStats() async {
    _stats.clear();
    try {
      if (await _statsFile.exists()) {
        final j = jsonDecode(await _statsFile.readAsString()) as Map;
        j.forEach((k, v) => _stats['$k'] = _Stats.fromJson(Map<String, dynamic>.from(v as Map)));
      }
    } catch (_) {}
  }

  Timer? _saveStatsTimer;
  void _saveStatsSoon() {
    _saveStatsTimer?.cancel();
    _saveStatsTimer = Timer(const Duration(seconds: 2), () async {
      final data = {for (final e in _stats.entries) if (!e.value.isEmpty) e.key: e.value.toJson()};
      final tmp = File('${_statsFile.path}.tmp');
      await tmp.writeAsString(jsonEncode(data));
      await tmp.rename(_statsFile.path);
    });
  }

  _Stats _st(String id) => _stats[id] ??= _Stats();

  Future<void> _loadPlaylists() async {
    _playlists.clear();
    try {
      if (await _playlistsFile.exists()) {
        for (final e in jsonDecode(await _playlistsFile.readAsString()) as List) {
          final m = Map<String, dynamic>.from(e as Map);
          _playlists[m['id'] as String] = _LocalPlaylist(
            m['id'] as String,
            m['name'] as String,
            List<String>.from(m['songs'] as List),
            DateTime.fromMillisecondsSinceEpoch(m['changed'] as int? ?? 0),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _savePlaylists() async {
    final data = [
      for (final pl in _playlists.values)
        {'id': pl.id, 'name': pl.name, 'songs': pl.songIds, 'changed': pl.changed.millisecondsSinceEpoch},
    ];
    final tmp = File('${_playlistsFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(_playlistsFile.path);
  }

  Playlist _playlistModel(_LocalPlaylist pl, {bool songs = false}) {
    final list = pl.songIds.map((id) => _byId[id]).whereType<Song>().toList();
    return Playlist(
      id: pl.id,
      name: pl.name,
      songCount: list.length,
      duration: list.fold<Duration>(Duration.zero, (d, s) => d + (s.duration ?? Duration.zero)),
      coverArt: list.map((s) => s.coverArt).whereType<String>().firstOrNull,
      changed: pl.changed,
      songs: songs ? list.map(_withStats).toList() : const [],
    );
  }

  // ---- MusicProvider ----

  @override
  bool get hasLocalAddress => false;
  @override
  bool get onLocalAddress => false;
  @override
  String get activeAddress => 'local';
  @override
  set localAddress(String? url) {}
  @override
  Future<bool> checkLocalAddress() async => false;
  @override
  Stream<bool> get endpointChanges => const Stream.empty();
  @override
  Map<String, String> get authParams => const {};
  @override
  Future<bool> validateAuth(Map<String, String> params) async => false;

  List<T> _page<T>(List<T> list, int offset, int size) =>
      offset >= list.length ? const [] : list.sublist(offset, min(list.length, offset + size));

  @override
  Future<List<Album>> albumList(AlbumListType type,
      {int size = 50, int offset = 0, String? genre, int? fromYear, int? toYear}) async {
    var list = _albums.values.toList();
    int plays(Album a) => a.songs.fold<int>(0, (n, s) => n + (_stats[s.id]?.plays ?? 0));
    DateTime last(Album a) => a.songs
        .map((s) => _stats[s.id]?.lastPlayed)
        .whereType<DateTime>()
        .fold(DateTime.fromMillisecondsSinceEpoch(0), (x, y) => y.isAfter(x) ? y : x);
    switch (type) {
      case AlbumListType.newest:
        list.sort((a, b) => (b.created ?? DateTime(0)).compareTo(a.created ?? DateTime(0)));
      case AlbumListType.recent:
        list = list.where((a) => last(a).millisecondsSinceEpoch > 0).toList()..sort((a, b) => last(b).compareTo(last(a)));
      case AlbumListType.frequent:
        list = list.where((a) => plays(a) > 0).toList()..sort((a, b) => plays(b).compareTo(plays(a)));
      case AlbumListType.random:
        list.shuffle(_rnd);
      case AlbumListType.alphabeticalByName:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case AlbumListType.alphabeticalByArtist:
        list.sort((a, b) {
          final c = a.displayArtist.toLowerCase().compareTo(b.displayArtist.toLowerCase());
          return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      case AlbumListType.starred:
        list = list.where((a) => _stats[a.id]?.starred != null).toList();
      case AlbumListType.highest:
        list = list.where((a) => plays(a) > 0 || _stats[a.id]?.starred != null).toList()
          ..sort((a, b) => plays(b).compareTo(plays(a)));
      case AlbumListType.byYear:
        final from = fromYear ?? 0, to = toYear ?? 9999;
        list = list.where((a) => a.year != null && a.year! >= min(from, to) && a.year! <= max(from, to)).toList()
          ..sort((a, b) => from <= to ? a.year!.compareTo(b.year!) : b.year!.compareTo(a.year!));
      case AlbumListType.byGenre:
        list = list.where((a) => a.songs.any((s) => s.genres.contains(genre))).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return _page(list, offset, size).map(_albumWithStats).toList();
  }

  @override
  Future<Album> album(String id) async {
    final a = _albums[id];
    if (a == null) throw StateError('álbum não encontrado');
    return _albumWithStats(a, songs: true);
  }

  @override
  Future<List<Artist>> artists() async =>
      _artists.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Future<Artist> artist(String id) async {
    final a = _artists[id];
    if (a == null) throw StateError('artista não encontrado');
    final name = a.name.toLowerCase();
    final albums = _albums.values
        .where((al) => al.artist?.toLowerCase() == name || al.songs.any((s) => s.artist?.toLowerCase() == name))
        .map(_albumWithStats)
        .toList()
      ..sort((x, y) => (x.year ?? 0).compareTo(y.year ?? 0));
    return Artist(id: a.id, name: a.name, coverArt: a.coverArt, albumCount: albums.length, albums: albums);
  }

  @override
  Future<ArtistInfo?> artistInfo(String id) async {
    final a = _artists[id];
    final fm = lastFm;
    if (a == null || fm == null) return null;
    try {
      final info = await fm.artistInfo(a.name);
      final similar = await fm.similarArtists(a.name, limit: 30);
      final local = <Artist>[];
      for (final s in similar) {
        final hit = _artists[_id('r', s.name.toLowerCase())];
        if (hit != null) local.add(hit);
      }
      return ArtistInfo(biography: info?.biography, lastFmUrl: info?.lastFmUrl, similarArtists: local);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Song>> topSongs(String artistName, {int count = 10}) async {
    final name = artistName.toLowerCase();
    final songs = _songs.where((s) => s.artist?.toLowerCase() == name || s.albumArtist?.toLowerCase() == name).toList();
    final fm = lastFm;
    if (fm != null) {
      try {
        final order = {for (final (i, t) in (await fm.topTracks(artistName, limit: 50)).indexed) matchKey(t): i};
        songs.sort((a, b) => (order[matchKey(a.title)] ?? 999).compareTo(order[matchKey(b.title)] ?? 999));
        return songs.take(count).map(_withStats).toList();
      } catch (_) {}
    }
    songs.sort((a, b) => (_stats[b.id]?.plays ?? 0).compareTo(_stats[a.id]?.plays ?? 0));
    return songs.take(count).map(_withStats).toList();
  }

  @override
  Future<List<Song>> randomSongs({int size = 50, String? genre}) async {
    final pool = genre == null ? List.of(_songs) : _songs.where((s) => s.genres.contains(genre)).toList();
    pool.shuffle(_rnd);
    return pool.take(size).map(_withStats).toList();
  }

  @override
  Future<List<Genre>> genres() async {
    final songs = <String, int>{};
    final albums = <String, Set<String>>{};
    for (final s in _songs) {
      for (final g in s.genres) {
        songs[g] = (songs[g] ?? 0) + 1;
        (albums[g] ??= {}).add(s.albumId ?? '');
      }
    }
    return [
      for (final g in songs.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())))
        Genre(name: g, songCount: songs[g]!, albumCount: albums[g]!.length),
    ];
  }

  @override
  Future<List<Song>> songsByGenre(String genre, {int count = 100, int offset = 0}) async =>
      _page(_songs.where((s) => s.genres.contains(genre)).toList(), offset, count).map(_withStats).toList();

  @override
  Future<SearchResult> search(String query, {int artistCount = 10, int albumCount = 20, int songCount = 50}) async {
    final words = matchKey(query).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const SearchResult();
    bool hit(String text) {
      final k = matchKey(text);
      return words.every(k.contains);
    }

    return SearchResult(
      artists: _artists.values.where((a) => hit(a.name)).take(artistCount).toList(),
      albums: _albums.values.where((a) => hit('${a.name} ${a.artist ?? ''}')).take(albumCount).map(_albumWithStats).toList(),
      songs: _songs
          .where((s) => hit('${s.title} ${s.displayArtist} ${s.album ?? ''}'))
          .take(songCount)
          .map(_withStats)
          .toList(),
    );
  }

  @override
  Future<List<Song>> allSongs({int count = 200, int offset = 0}) async => _page(_songs, offset, count).map(_withStats).toList();

  @override
  Future<List<Playlist>> playlists() async =>
      _playlists.values.map((pl) => _playlistModel(pl)).toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Playlist> playlist(String id) async {
    final pl = _playlists[id];
    if (pl == null) throw StateError('playlist não encontrada');
    return _playlistModel(pl, songs: true);
  }

  @override
  Future<Playlist> createPlaylist(String name, {List<String> songIds = const []}) async {
    final pl = _LocalPlaylist(_id('p', '$name${DateTime.now().microsecondsSinceEpoch}'), name, List.of(songIds), DateTime.now());
    _playlists[pl.id] = pl;
    await _savePlaylists();
    return _playlistModel(pl);
  }

  @override
  Future<void> addToPlaylist(String playlistId, List<String> songIds) async {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    pl.songIds.addAll(songIds);
    pl.changed = DateTime.now();
    await _savePlaylists();
  }

  @override
  Future<void> removeFromPlaylist(String playlistId, List<int> indexes) async {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    for (final i in indexes.toList()..sort((a, b) => b.compareTo(a))) {
      if (i >= 0 && i < pl.songIds.length) pl.songIds.removeAt(i);
    }
    pl.changed = DateTime.now();
    await _savePlaylists();
  }

  @override
  Future<void> renamePlaylist(String playlistId, String name) async {
    final pl = _playlists[playlistId];
    if (pl == null) return;
    pl.name = name;
    pl.changed = DateTime.now();
    await _savePlaylists();
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _playlists.remove(playlistId);
    await _savePlaylists();
  }

  @override
  Future<List<Song>> starredSongs() async =>
      _songs.where((s) => _stats[s.id]?.starred != null).map(_withStats).toList();

  @override
  Future<void> setStarred({String? songId, String? albumId, String? artistId, required bool starred}) async {
    for (final id in [songId, albumId, artistId].whereType<String>()) {
      _st(id).starred = starred ? DateTime.now() : null;
    }
    _saveStatsSoon();
  }

  @override
  Future<void> setRating(String id, int rating) async {
    _st(id).rating = rating;
    _saveStatsSoon();
  }

  @override
  Future<void> scrobble(String songId, {required bool submission, DateTime? time}) async {
    if (!submission || !_byId.containsKey(songId)) return;
    final st = _st(songId);
    st.plays++;
    st.lastPlayed = time ?? DateTime.now();
    _saveStatsSoon();
  }

  @override
  Future<Lyrics?> lyrics(Song song) async {
    final path = song.path;
    if (path == null) return null;
    final lrc = File('${p.withoutExtension(path)}.lrc');
    try {
      if (await lrc.exists()) return parseLrc(await lrc.readAsString());
    } catch (_) {}
    return null;
  }

  @override
  Future<List<Song>> similarSongs(String songId, {int count = 50}) async {
    final seed = _byId[songId];
    if (seed == null) return const [];
    final out = <Song>[];
    final seen = <String>{songId};
    void add(Iterable<Song> list) {
      for (final s in list) {
        if (out.length >= count) return;
        if (seen.add(s.id)) out.add(s);
      }
    }

    final fm = lastFm;
    final artist = seed.artist ?? seed.albumArtist;
    if (fm != null && artist != null) {
      try {
        final byKey = <String, Song>{for (final s in _songs) '${matchKey(s.displayArtist)}|${matchKey(s.title)}': s};
        final similar = await fm.similarTracks(artist, seed.title, limit: 100);
        add(similar.map((t) => byKey['${matchKey(t.artist)}|${matchKey(t.title)}']).whereType<Song>());
        if (out.length < count) {
          final artists = await fm.similarArtists(artist, limit: 30);
          final names = artists.map((a) => matchKey(a.name)).toSet();
          final pool = _songs.where((s) => names.contains(matchKey(s.displayArtist))).toList()..shuffle(_rnd);
          add(pool.take(count));
        }
      } catch (_) {}
    }
    // Sem Last.fm (ou pouco resultado): mesmo artista e mesmo gênero.
    if (out.length < count) {
      final same = _songs.where((s) => s.artist != null && s.artist == seed.artist).toList()..shuffle(_rnd);
      add(same.take(max(3, count ~/ 4)));
      final genre = _songs.where((s) => s.genres.any(seed.genres.contains)).toList()..shuffle(_rnd);
      add(genre);
    }
    return out.map(_withStats).toList();
  }

  @override
  Future<List<SonicMatch>> sonicSimilar(String songId, {int count = 50}) async => const [];

  @override
  Future<List<SonicMatch>> sonicPath(String startSongId, String endSongId, {int count = 25}) async => const [];

  @override
  Future<void> savePlayQueue(List<String> songIds, {String? current, Duration position = Duration.zero}) async {}

  @override
  Future<({List<Song> songs, String? current, Duration position})?> playQueue() async => null;

  @override
  Uri streamUri(Song song, {String? format, int? maxBitRate}) => Uri.file(song.path ?? '');

  @override
  String streamCacheKey(Song song, {String? format, int? maxBitRate}) => 'local:${song.id}';

  @override
  Uri? coverUri(String? coverArtId, {int? size}) => coverArtId == null ? null : Uri.file(coverArtId);

  @override
  String? coverCacheKey(String? coverArtId, {int? size}) => coverArtId;
}

/// Letra .lrc: "[mm:ss.xx] texto" (sincronizada) ou texto puro.
Lyrics? parseLrc(String text) {
  final stamp = RegExp(r'\[(\d+):(\d+(?:[.:]\d+)?)\]');
  final offsetTag = RegExp(r'\[offset:\s*([+-]?\d+)\]', caseSensitive: false);
  var offset = Duration.zero;
  final synced = <LyricLine>[];
  final plain = <LyricLine>[];
  for (final raw in const LineSplitter().convert(text)) {
    final o = offsetTag.firstMatch(raw);
    if (o != null) {
      offset = Duration(milliseconds: int.parse(o.group(1)!));
      continue;
    }
    final stamps = stamp.allMatches(raw).toList();
    final body = raw.replaceAll(stamp, '').trim();
    if (stamps.isEmpty) {
      if (!RegExp(r'^\[[a-z]+:').hasMatch(raw.trim())) plain.add(LyricLine(text: raw.trim()));
      continue;
    }
    for (final m in stamps) {
      final secs = double.parse(m.group(2)!.replaceFirst(':', '.'));
      synced.add(LyricLine(
        start: Duration(milliseconds: (int.parse(m.group(1)!) * 60000 + secs * 1000).round()),
        text: body,
      ));
    }
  }
  if (synced.isNotEmpty) {
    synced.sort((a, b) => a.start!.compareTo(b.start!));
    return Lyrics(synced: true, lines: synced, offset: offset);
  }
  final lines = plain.where((l) => l.text.isNotEmpty).toList();
  return lines.isEmpty ? null : Lyrics(synced: false, lines: lines);
}
