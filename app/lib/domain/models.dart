// Modelos independentes de servidor. Os provedores (Subsonic, Jellyfin no
// futuro) convertem as respostas deles para estes tipos.

class ArtistRef {
  const ArtistRef({required this.id, required this.name});
  final String? id;
  final String name;
}

class ReplayGain {
  const ReplayGain({
    this.trackGain,
    this.albumGain,
    this.trackPeak,
    this.albumPeak,
    this.baseGain,
    this.fallbackGain,
  });
  final double? trackGain;
  final double? albumGain;
  final double? trackPeak;
  final double? albumPeak;
  final double? baseGain;
  final double? fallbackGain;

  bool get isEmpty => trackGain == null && albumGain == null;
}

class Song {
  const Song({
    required this.id,
    required this.title,
    this.album,
    this.albumId,
    this.artist,
    this.artistId,
    this.artists = const [],
    this.albumArtist,
    this.track,
    this.disc,
    this.year,
    this.genre,
    this.genres = const [],
    this.coverArt,
    this.duration,
    this.bitRate,
    this.sampleRate,
    this.bitDepth,
    this.channels,
    this.suffix,
    this.contentType,
    this.size,
    this.starred,
    this.userRating,
    this.playCount,
    this.bpm,
    this.replayGain,
    this.musicBrainzId,
    this.comment,
    this.explicitStatus,
    this.path,
  });

  final String id;
  final String title;
  final String? album;
  final String? albumId;
  final String? artist;
  final String? artistId;
  final List<ArtistRef> artists;
  final String? albumArtist;
  final int? track;
  final int? disc;
  final int? year;
  final String? genre;
  final List<String> genres;
  final String? coverArt;
  final Duration? duration;
  final int? bitRate;
  final int? sampleRate;
  final int? bitDepth;
  final int? channels;
  final String? suffix;
  final String? contentType;
  final int? size;
  final DateTime? starred;
  final int? userRating;
  final int? playCount;
  final int? bpm;
  final ReplayGain? replayGain;
  final String? musicBrainzId;
  final String? comment;
  final String? explicitStatus;

  /// Arquivo no aparelho (biblioteca local ou música recebida numa Jam).
  final String? path;

  String get displayArtist =>
      artist ?? (artists.isNotEmpty ? artists.map((a) => a.name).join(', ') : '');

  bool get isStarred => starred != null;

  /// Serialização compacta (fila salva no disco).
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (album != null) 'album': album,
        if (albumId != null) 'albumId': albumId,
        if (artist != null) 'artist': artist,
        if (artistId != null) 'artistId': artistId,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (track != null) 'track': track,
        if (disc != null) 'disc': disc,
        if (year != null) 'year': year,
        if (genre != null) 'genre': genre,
        if (coverArt != null) 'coverArt': coverArt,
        if (duration != null) 'duration': duration!.inMilliseconds,
        if (bitRate != null) 'bitRate': bitRate,
        if (sampleRate != null) 'sampleRate': sampleRate,
        if (bitDepth != null) 'bitDepth': bitDepth,
        if (suffix != null) 'suffix': suffix,
        if (starred != null) 'starred': starred!.toIso8601String(),
        if (bpm != null) 'bpm': bpm,
        if (path != null) 'path': path,
        if (replayGain != null)
          'rg': [replayGain!.trackGain, replayGain!.albumGain, replayGain!.trackPeak, replayGain!.albumPeak, replayGain!.baseGain, replayGain!.fallbackGain],
      };

  factory Song.fromJson(Map<String, dynamic> j) {
    double? d(List? l, int i) => (l != null && l.length > i && l[i] is num) ? (l[i] as num).toDouble() : null;
    final rg = j['rg'] as List?;
    return Song(
      id: j['id'] as String,
      title: j['title'] as String? ?? '?',
      album: j['album'] as String?,
      albumId: j['albumId'] as String?,
      artist: j['artist'] as String?,
      artistId: j['artistId'] as String?,
      albumArtist: j['albumArtist'] as String?,
      track: j['track'] as int?,
      disc: j['disc'] as int?,
      year: j['year'] as int?,
      genre: j['genre'] as String?,
      coverArt: j['coverArt'] as String?,
      duration: j['duration'] is int ? Duration(milliseconds: j['duration'] as int) : null,
      bitRate: j['bitRate'] as int?,
      sampleRate: j['sampleRate'] as int?,
      bitDepth: j['bitDepth'] as int?,
      suffix: j['suffix'] as String?,
      starred: j['starred'] is String ? DateTime.tryParse(j['starred'] as String) : null,
      bpm: j['bpm'] as int?,
      path: j['path'] as String?,
      replayGain: rg == null
          ? null
          : ReplayGain(trackGain: d(rg, 0), albumGain: d(rg, 1), trackPeak: d(rg, 2), albumPeak: d(rg, 3), baseGain: d(rg, 4), fallbackGain: d(rg, 5)),
    );
  }

  Song copyWith({DateTime? starred, bool clearStarred = false, int? userRating}) => Song(
        id: id,
        title: title,
        album: album,
        albumId: albumId,
        artist: artist,
        artistId: artistId,
        artists: artists,
        albumArtist: albumArtist,
        track: track,
        disc: disc,
        year: year,
        genre: genre,
        genres: genres,
        coverArt: coverArt,
        duration: duration,
        bitRate: bitRate,
        sampleRate: sampleRate,
        bitDepth: bitDepth,
        channels: channels,
        suffix: suffix,
        contentType: contentType,
        size: size,
        starred: clearStarred ? null : (starred ?? this.starred),
        userRating: userRating ?? this.userRating,
        playCount: playCount,
        bpm: bpm,
        replayGain: replayGain,
        musicBrainzId: musicBrainzId,
        comment: comment,
        explicitStatus: explicitStatus,
        path: path,
      );
}

class Album {
  const Album({
    required this.id,
    required this.name,
    this.artist,
    this.artistId,
    this.artists = const [],
    this.coverArt,
    this.songCount,
    this.duration,
    this.year,
    this.genre,
    this.genres = const [],
    this.starred,
    this.playCount,
    this.userRating,
    this.created,
    this.isCompilation = false,
    this.recordLabels = const [],
    this.releaseTypes = const [],
    this.songs = const [],
  });

  final String id;
  final String name;
  final String? artist;
  final String? artistId;
  final List<ArtistRef> artists;
  final String? coverArt;
  final int? songCount;
  final Duration? duration;
  final int? year;
  final String? genre;
  final List<String> genres;
  final DateTime? starred;
  final int? playCount;
  final int? userRating;
  final DateTime? created;
  final bool isCompilation;
  final List<String> recordLabels;
  final List<String> releaseTypes;
  final List<Song> songs;

  String get displayArtist =>
      artist ?? (artists.isNotEmpty ? artists.map((a) => a.name).join(', ') : '');
}

class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.coverArt,
    this.albumCount,
    this.starred,
    this.imageUrl,
    this.albums = const [],
  });

  final String id;
  final String name;
  final String? coverArt;
  final int? albumCount;
  final DateTime? starred;
  final String? imageUrl;
  final List<Album> albums;
}

class ArtistInfo {
  const ArtistInfo({this.biography, this.similarArtists = const [], this.imageUrl, this.lastFmUrl});
  final String? biography;
  final List<Artist> similarArtists;
  final String? imageUrl;
  final String? lastFmUrl;
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.comment,
    this.owner,
    this.isPublic = false,
    this.songCount = 0,
    this.duration,
    this.coverArt,
    this.changed,
    this.songs = const [],
  });

  final String id;
  final String name;
  final String? comment;
  final String? owner;
  final bool isPublic;
  final int songCount;
  final Duration? duration;
  final String? coverArt;
  final DateTime? changed;
  final List<Song> songs;
}

class Genre {
  const Genre({required this.name, this.songCount = 0, this.albumCount = 0});
  final String name;
  final int songCount;
  final int albumCount;
}

class LyricLine {
  const LyricLine({this.start, required this.text});
  final Duration? start;
  final String text;
}

class Lyrics {
  const Lyrics({required this.synced, required this.lines, this.lang, this.offset = Duration.zero, this.source, this.copyright});
  final bool synced;
  final List<LyricLine> lines;
  final String? lang;
  final Duration offset;

  /// De onde veio, quando não é do servidor/arquivo (ex.: LRCLIB, Musixmatch):
  /// aparece como crédito embaixo da letra.
  final String? source;

  /// Aviso de direitos que a fonte exige mostrar junto (Musixmatch).
  final String? copyright;

  Lyrics withSource(String source, {String? copyright}) =>
      Lyrics(synced: synced, lines: lines, lang: lang, offset: offset, source: source, copyright: copyright);
}

class SonicMatch {
  const SonicMatch({required this.song, required this.similarity});
  final Song song;
  final double similarity;
}

class SearchResult {
  const SearchResult({this.artists = const [], this.albums = const [], this.songs = const []});
  final List<Artist> artists;
  final List<Album> albums;
  final List<Song> songs;

  bool get isEmpty => artists.isEmpty && albums.isEmpty && songs.isEmpty;
}

class ServerInfo {
  const ServerInfo({
    required this.type,
    required this.version,
    required this.apiVersion,
    required this.openSubsonic,
    this.extensions = const {},
  });

  final String type;
  final String version;
  final String apiVersion;
  final bool openSubsonic;
  final Map<String, List<int>> extensions;

  bool supports(String ext, [int version = 1]) => extensions[ext]?.contains(version) ?? false;

  bool get sonicSimilarity => supports('sonicSimilarity');
  bool get songLyrics => supports('songLyrics');
  bool get playbackReport => supports('playbackReport');
  bool get apiKeyAuth => supports('apiKeyAuthentication');
  bool get transcoding => supports('transcoding');
}

enum AlbumListType {
  newest,
  recent,
  frequent,
  random,
  alphabeticalByName,
  alphabeticalByArtist,
  starred,
  highest,
  byYear,
  byGenre,
}
