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

  String get displayArtist =>
      artist ?? (artists.isNotEmpty ? artists.map((a) => a.name).join(', ') : '');

  bool get isStarred => starred != null;

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
  const Lyrics({required this.synced, required this.lines, this.lang, this.offset = Duration.zero});
  final bool synced;
  final List<LyricLine> lines;
  final String? lang;
  final Duration offset;
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
