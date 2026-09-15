import '../../domain/models.dart';
import '../../domain/music_provider.dart';
import 'subsonic_client.dart';
import 'subsonic_parse.dart';

class SubsonicProvider implements MusicProvider {
  SubsonicProvider({required this.accountId, required this.client});

  @override
  final String accountId;
  final SubsonicClient client;

  ServerInfo? _info;
  @override
  ServerInfo? get serverInfo => _info;

  @override
  bool get hasLocalAddress => client.localUrl != null;

  @override
  bool get onLocalAddress => client.onLocal;

  @override
  String get activeAddress => client.baseUrl;

  @override
  set localAddress(String? url) => client.localUrl = url;

  @override
  Future<bool> checkLocalAddress() => client.checkLocal();

  @override
  Stream<bool> get endpointChanges => client.endpointChanges;

  @override
  Map<String, String> get authParams => client.auth.params;

  @override
  Future<bool> validateAuth(Map<String, String> params) => client.validate(params);

  @override
  Future<ServerInfo> connect() async {
    final ping = await client.get('ping');
    final ext = ping['openSubsonic'] == true ? await client.openSubsonicExtensions() : null;
    return _info = parseServerInfo(ping, ext);
  }

  static String _albumListType(AlbumListType t) => switch (t) {
        AlbumListType.newest => 'newest',
        AlbumListType.recent => 'recent',
        AlbumListType.frequent => 'frequent',
        AlbumListType.random => 'random',
        AlbumListType.alphabeticalByName => 'alphabeticalByName',
        AlbumListType.alphabeticalByArtist => 'alphabeticalByArtist',
        AlbumListType.starred => 'starred',
        AlbumListType.highest => 'highest',
        AlbumListType.byYear => 'byYear',
        AlbumListType.byGenre => 'byGenre',
      };

  @override
  Future<List<Album>> albumList(AlbumListType type,
      {int size = 50, int offset = 0, String? genre, int? fromYear, int? toYear}) async {
    final body = await client.get('getAlbumList2', {
      'type': _albumListType(type),
      'size': size,
      'offset': offset,
      'genre': genre,
      'fromYear': fromYear ?? (type == AlbumListType.byYear ? 0 : null),
      'toYear': toYear ?? (type == AlbumListType.byYear ? 9999 : null),
    });
    return list((body['albumList2'] as Map?)?['album']).map(parseAlbum).toList();
  }

  @override
  Future<Album> album(String id) async {
    final body = await client.get('getAlbum', {'id': id});
    return parseAlbum(Map<String, dynamic>.from(body['album'] as Map));
  }

  @override
  Future<List<Artist>> artists() async {
    final body = await client.get('getArtists');
    final index = list((body['artists'] as Map?)?['index']);
    return [for (final i in index) ...list(i['artist']).map(parseArtist)];
  }

  @override
  Future<Artist> artist(String id) async {
    final body = await client.get('getArtist', {'id': id});
    return parseArtist(Map<String, dynamic>.from(body['artist'] as Map));
  }

  @override
  Future<ArtistInfo?> artistInfo(String id) async {
    try {
      final body = await client.get('getArtistInfo2', {'id': id, 'count': 12});
      final info = body['artistInfo2'];
      return info is Map ? parseArtistInfo(Map<String, dynamic>.from(info)) : null;
    } on SubsonicException {
      return null;
    }
  }

  @override
  Future<List<Song>> topSongs(String artistName, {int count = 10}) async {
    try {
      final body = await client.get('getTopSongs', {'artist': artistName, 'count': count});
      return list((body['topSongs'] as Map?)?['song']).map(parseSong).toList();
    } on SubsonicException {
      return const [];
    }
  }

  @override
  Future<List<Song>> randomSongs({int size = 50, String? genre}) async {
    final body = await client.get('getRandomSongs', {'size': size, 'genre': genre});
    return list((body['randomSongs'] as Map?)?['song']).map(parseSong).toList();
  }

  @override
  Future<List<Genre>> genres() async {
    final body = await client.get('getGenres');
    final g = list((body['genres'] as Map?)?['genre']).map(parseGenre).toList();
    g.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return g;
  }

  @override
  Future<List<Song>> songsByGenre(String genre, {int count = 100, int offset = 0}) async {
    final body = await client.get('getSongsByGenre', {'genre': genre, 'count': count, 'offset': offset});
    return list((body['songsByGenre'] as Map?)?['song']).map(parseSong).toList();
  }

  @override
  Future<List<Song>> allSongs({int count = 200, int offset = 0}) async {
    // Busca vazia = biblioteca inteira (Navidrome e servidores OpenSubsonic).
    final body = await client.get('search3', {
      'query': '',
      'artistCount': 0,
      'albumCount': 0,
      'songCount': count,
      'songOffset': offset,
    });
    final r = body['searchResult3'] as Map? ?? const {};
    return list(r['song']).map(parseSong).toList();
  }

  @override
  Future<SearchResult> search(String query, {int artistCount = 10, int albumCount = 20, int songCount = 50}) async {
    final body = await client.get('search3', {
      'query': query,
      'artistCount': artistCount,
      'albumCount': albumCount,
      'songCount': songCount,
    });
    final r = body['searchResult3'] as Map? ?? const {};
    return SearchResult(
      artists: list(r['artist']).map(parseArtist).toList(),
      albums: list(r['album']).map(parseAlbum).toList(),
      songs: list(r['song']).map(parseSong).toList(),
    );
  }

  @override
  Future<List<Playlist>> playlists() async {
    final body = await client.get('getPlaylists');
    return list((body['playlists'] as Map?)?['playlist']).map(parsePlaylist).toList();
  }

  @override
  Future<Playlist> playlist(String id) async {
    final body = await client.get('getPlaylist', {'id': id});
    return parsePlaylist(Map<String, dynamic>.from(body['playlist'] as Map));
  }

  @override
  Future<Playlist> createPlaylist(String name, {List<String> songIds = const []}) async {
    final body = await client.get('createPlaylist', {'name': name, 'songId': songIds});
    final p = body['playlist'];
    if (p is Map) return parsePlaylist(Map<String, dynamic>.from(p));
    final all = await playlists();
    return all.firstWhere((pl) => pl.name == name);
  }

  @override
  Future<void> addToPlaylist(String playlistId, List<String> songIds) =>
      client.get('updatePlaylist', {'playlistId': playlistId, 'songIdToAdd': songIds});

  @override
  Future<void> removeFromPlaylist(String playlistId, List<int> indexes) =>
      client.get('updatePlaylist', {'playlistId': playlistId, 'songIndexToRemove': indexes});

  @override
  Future<void> renamePlaylist(String playlistId, String name) =>
      client.get('updatePlaylist', {'playlistId': playlistId, 'name': name});

  @override
  Future<void> deletePlaylist(String playlistId) => client.get('deletePlaylist', {'id': playlistId});

  @override
  Future<List<Song>> starredSongs() async {
    final body = await client.get('getStarred2');
    return list((body['starred2'] as Map?)?['song']).map(parseSong).toList();
  }

  @override
  Future<void> setStarred({String? songId, String? albumId, String? artistId, required bool starred}) =>
      client.get(starred ? 'star' : 'unstar', {'id': songId, 'albumId': albumId, 'artistId': artistId});

  @override
  Future<void> setRating(String id, int rating) => client.get('setRating', {'id': id, 'rating': rating});

  @override
  Future<void> scrobble(String songId, {required bool submission, DateTime? time}) => client.get('scrobble', {
        'id': songId,
        'submission': submission,
        'time': time?.millisecondsSinceEpoch,
      });

  @override
  Future<Lyrics?> lyrics(Song song) async {
    if (_info?.songLyrics ?? false) {
      try {
        final body = await client.get('getLyricsBySongId', {'id': song.id});
        final l = parseStructuredLyrics(body);
        if (l != null) return l;
      } on SubsonicException {
        // cai no método clássico
      }
    }
    try {
      final body = await client.get('getLyrics', {'artist': song.artist, 'title': song.title});
      return parsePlainLyrics(body);
    } on SubsonicException {
      return null;
    }
  }

  @override
  Future<List<Song>> similarSongs(String songId, {int count = 50}) async {
    final body = await client.get('getSimilarSongs2', {'id': songId, 'count': count});
    return list((body['similarSongs2'] as Map?)?['song']).map(parseSong).toList();
  }

  @override
  Future<List<SonicMatch>> sonicSimilar(String songId, {int count = 50}) async {
    final body = await client.get('getSonicSimilarTracks', {'id': songId, 'count': count});
    return parseSonicMatches(body);
  }

  @override
  Future<List<SonicMatch>> sonicPath(String startSongId, String endSongId, {int count = 25}) async {
    final body = await client.get('findSonicPath', {
      'startSongId': startSongId,
      'endSongId': endSongId,
      'count': count,
    });
    return parseSonicMatches(body);
  }

  @override
  Future<void> savePlayQueue(List<String> songIds, {String? current, Duration position = Duration.zero}) =>
      client.get('savePlayQueue', {
        'id': songIds,
        'current': current,
        'position': position.inMilliseconds,
      });

  @override
  Future<({List<Song> songs, String? current, Duration position})?> playQueue() async {
    try {
      final body = await client.get('getPlayQueue');
      final q = body['playQueue'];
      if (q is! Map) return null;
      final songs = list(q['entry']).map(parseSong).toList();
      if (songs.isEmpty) return null;
      return (
        songs: songs,
        current: q['current']?.toString(),
        position: Duration(milliseconds: (q['position'] as num?)?.toInt() ?? 0),
      );
    } on SubsonicException {
      return null;
    }
  }

  @override
  Uri streamUri(Song song, {String? format, int? maxBitRate}) => client.uri('stream', {
        'id': song.id,
        'format': format ?? 'raw',
        'maxBitRate': (maxBitRate ?? 0) > 0 ? maxBitRate : null,
      });

  @override
  String streamCacheKey(Song song, {String? format, int? maxBitRate}) =>
      '$accountId:song:${song.id}:${format ?? 'raw'}:${maxBitRate ?? 0}';

  @override
  Uri? coverUri(String? coverArtId, {int? size}) =>
      coverArtId == null ? null : client.uri('getCoverArt', {'id': coverArtId, 'size': size});

  @override
  String? coverCacheKey(String? coverArtId, {int? size}) =>
      coverArtId == null ? null : '$accountId:cover:$coverArtId:${size ?? 0}';

  /// O servidor de análise confere este mesmo login no Navidrome.
  @override
  Uri? analyzerUri(String server, String path) {
    final base = server.trim().replaceAll(RegExp(r'/+$'), '');
    if (!base.startsWith('http://') && !base.startsWith('https://')) return null;
    return Uri.parse('$base$path').replace(queryParameters: client.auth.params);
  }
}
