// Conversão das respostas JSON (Subsonic + campos OpenSubsonic) para os modelos.

import '../../domain/models.dart';

typedef Json = Map<String, dynamic>;

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int? _int(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _double(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v) : null;

Duration? _seconds(dynamic v) {
  final s = _int(v);
  return s == null ? null : Duration(seconds: s);
}

List<Json> list(dynamic v) {
  if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  if (v is Map) return [Map<String, dynamic>.from(v)];
  return const [];
}

List<ArtistRef> _artistRefs(dynamic v) =>
    list(v).map((a) => ArtistRef(id: _str(a['id']), name: _str(a['name']) ?? '')).toList();

List<String> _names(dynamic v) {
  if (v is List) {
    return v
        .map((e) => e is Map ? _str(e['name']) : _str(e))
        .whereType<String>()
        .toList();
  }
  return const [];
}

ReplayGain? _replayGain(dynamic v) {
  if (v is! Map) return null;
  final rg = ReplayGain(
    trackGain: _double(v['trackGain']),
    albumGain: _double(v['albumGain']),
    trackPeak: _double(v['trackPeak']),
    albumPeak: _double(v['albumPeak']),
    baseGain: _double(v['baseGain']),
    fallbackGain: _double(v['fallbackGain']),
  );
  return rg.isEmpty ? null : rg;
}

Song parseSong(Json j) {
  final artists = _artistRefs(j['artists']);
  final bpm = _int(j['bpm']);
  return Song(
    id: j['id'].toString(),
    title: _str(j['title']) ?? _str(j['name']) ?? '?',
    album: _str(j['album']),
    albumId: _str(j['albumId']),
    artist: _str(j['displayArtist']) ?? _str(j['artist']),
    artistId: _str(j['artistId']) ?? (artists.isNotEmpty ? artists.first.id : null),
    artists: artists,
    albumArtist: _str(j['displayAlbumArtist']),
    track: _int(j['track']),
    disc: _int(j['discNumber']),
    year: _int(j['year']),
    genre: _str(j['genre']),
    genres: _names(j['genres']),
    coverArt: _str(j['coverArt']),
    duration: _seconds(j['duration']),
    bitRate: _int(j['bitRate']),
    sampleRate: _int(j['samplingRate']),
    bitDepth: _int(j['bitDepth']),
    channels: _int(j['channelCount']),
    suffix: _str(j['suffix']),
    contentType: _str(j['contentType']),
    size: _int(j['size']),
    starred: _date(j['starred']),
    userRating: _int(j['userRating']),
    playCount: _int(j['playCount']),
    bpm: (bpm == null || bpm == 0) ? null : bpm,
    replayGain: _replayGain(j['replayGain']),
    musicBrainzId: _str(j['musicBrainzId']),
    comment: _str(j['comment']),
    explicitStatus: _str(j['explicitStatus']),
  );
}

Album parseAlbum(Json j) {
  return Album(
    id: j['id'].toString(),
    name: _str(j['name']) ?? _str(j['title']) ?? '?',
    artist: _str(j['displayArtist']) ?? _str(j['artist']),
    artistId: _str(j['artistId']),
    artists: _artistRefs(j['artists']),
    coverArt: _str(j['coverArt']),
    songCount: _int(j['songCount']),
    duration: _seconds(j['duration']),
    year: _int(j['year']),
    genre: _str(j['genre']),
    genres: _names(j['genres']),
    starred: _date(j['starred']),
    playCount: _int(j['playCount']),
    userRating: _int(j['userRating']),
    created: _date(j['created']),
    isCompilation: j['isCompilation'] == true,
    recordLabels: _names(j['recordLabels']),
    releaseTypes: _names(j['releaseTypes']),
    songs: list(j['song']).map(parseSong).toList(),
  );
}

Artist parseArtist(Json j) {
  return Artist(
    id: j['id'].toString(),
    name: _str(j['name']) ?? '?',
    coverArt: _str(j['coverArt']),
    albumCount: _int(j['albumCount']),
    starred: _date(j['starred']),
    imageUrl: _str(j['artistImageUrl']),
    albums: list(j['album']).map(parseAlbum).toList(),
  );
}

ArtistInfo parseArtistInfo(Json j) {
  return ArtistInfo(
    biography: _str(j['biography']),
    similarArtists: list(j['similarArtist']).map(parseArtist).toList(),
    imageUrl: _str(j['largeImageUrl']) ?? _str(j['mediumImageUrl']),
    lastFmUrl: _str(j['lastFmUrl']),
  );
}

Playlist parsePlaylist(Json j) {
  return Playlist(
    id: j['id'].toString(),
    name: _str(j['name']) ?? '?',
    comment: _str(j['comment']),
    owner: _str(j['owner']),
    isPublic: j['public'] == true,
    songCount: _int(j['songCount']) ?? 0,
    duration: _seconds(j['duration']),
    coverArt: _str(j['coverArt']),
    changed: _date(j['changed']),
    songs: list(j['entry']).map(parseSong).toList(),
  );
}

Genre parseGenre(Json j) => Genre(
      name: _str(j['value']) ?? _str(j['name']) ?? '?',
      songCount: _int(j['songCount']) ?? 0,
      albumCount: _int(j['albumCount']) ?? 0,
    );

/// `getLyricsBySongId` (OpenSubsonic): prefere a versão sincronizada.
Lyrics? parseStructuredLyrics(Json body) {
  final all = list((body['lyricsList'] as Map?)?['structuredLyrics']);
  if (all.isEmpty) return null;
  all.sort((a, b) => (b['synced'] == true ? 1 : 0) - (a['synced'] == true ? 1 : 0));
  final l = all.first;
  final synced = l['synced'] == true;
  return Lyrics(
    synced: synced,
    lang: _str(l['lang']),
    offset: Duration(milliseconds: _int(l['offset']) ?? 0),
    lines: list(l['line'])
        .map((ln) => LyricLine(
              start: synced && ln['start'] != null ? Duration(milliseconds: _int(ln['start'])!) : null,
              text: _str(ln['value']) ?? '',
            ))
        .toList(),
  );
}

/// `getLyrics` clássico: só texto, sem tempo.
Lyrics? parsePlainLyrics(Json body) {
  final text = _str((body['lyrics'] as Map?)?['value']);
  if (text == null) return null;
  return Lyrics(synced: false, lines: text.split('\n').map((t) => LyricLine(text: t)).toList());
}

List<SonicMatch> parseSonicMatches(Json body) => list(body['sonicMatch'])
    .where((m) => m['entry'] is Map)
    .map((m) => SonicMatch(
          song: parseSong(Map<String, dynamic>.from(m['entry'] as Map)),
          similarity: _double(m['similarity']) ?? -1,
        ))
    .toList();

ServerInfo parseServerInfo(Json ping, Json? ext) {
  final extensions = <String, List<int>>{};
  for (final e in list(ext?['openSubsonicExtensions'])) {
    final name = _str(e['name']);
    if (name == null) continue;
    extensions[name] = (e['versions'] as List? ?? const []).map((v) => _int(v) ?? 0).toList();
  }
  return ServerInfo(
    type: _str(ping['type']) ?? 'subsonic',
    version: _str(ping['serverVersion']) ?? '',
    apiVersion: _str(ping['version']) ?? '',
    openSubsonic: ping['openSubsonic'] == true,
    extensions: extensions,
  );
}
