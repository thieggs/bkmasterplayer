import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../domain/models.dart';
import 'lastfm.dart' show matchKey;
import 'local/local_provider.dart' show parseLrc;

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 15),
  // Só ASCII: o HttpClient recusa acento em cabeçalho.
  headers: {'User-Agent': 'BKTPlayer/1.0 (open source music player)'},
  validateStatus: (_) => true,
));

String _hash(String s) => sha1.convert(utf8.encode(s)).toString().substring(0, 20);

/// Letras que faltam no servidor/arquivo, buscadas na internet:
/// - LRCLIB (aberto, com letras sincronizadas): guardada no disco;
/// - Musixmatch (API oficial, com a chave do usuário; só letra inteira, que
///   exige plano comercial): mostra o aviso de direitos, avisa o rastreio que
///   a API pede e não guarda a letra no disco, como os termos pedem.
/// Falta de letra fica guardada por 7 dias. (O lyrics.ovh saiu: ele copia de
/// sites de letras sem autorização.)
class OnlineLyrics {
  OnlineLyrics({required this.cacheDir, this.musixmatchKey});
  final String cacheDir;
  final String? musixmatchKey;

  Future<Lyrics?> fetch(Song song) async {
    final artist = song.artist ?? song.displayArtist;
    if (artist.isEmpty || song.title.isEmpty) return null;
    final file = File(p.join(cacheDir, 'lyrics', '${_hash('$artist|${song.title}')}.json'));
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString()) as Map;
        // Só vale o cache com a fonte anotada (os antigos podiam ser do lyrics.ovh).
        if (j['lrc'] is String && j['source'] == 'LRCLIB') return parseLrc(j['lrc'] as String)?.withSource('LRCLIB');
        final missed = DateTime.fromMillisecondsSinceEpoch(j['missed'] as int? ?? 0);
        if (j['missed'] != null && DateTime.now().difference(missed) < const Duration(days: 7)) return null;
      }
    } catch (_) {}
    String? lrc;
    try {
      lrc = await _lrclib(song, artist);
    } catch (_) {}
    if (lrc != null && lrc.trim().isNotEmpty) {
      await _save(file, {'lrc': lrc, 'source': 'LRCLIB'});
      return parseLrc(lrc)?.withSource('LRCLIB');
    }
    try {
      final mxm = await _musixmatch(song, artist);
      if (mxm != null) return mxm;
    } catch (_) {}
    await _save(file, {'missed': DateTime.now().millisecondsSinceEpoch});
    return null;
  }

  Future<void> _save(File file, Map<String, dynamic> data) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<String?> _lrclib(Song s, String artist) async {
    final secs = s.duration?.inSeconds;
    final res = await _dio.get('https://lrclib.net/api/get', queryParameters: {
      'artist_name': artist,
      'track_name': s.title,
      if (s.album != null) 'album_name': s.album,
      'duration': ?secs,
    });
    Map? hit = res.statusCode == 200 && res.data is Map ? res.data as Map : null;
    if (hit == null) {
      final search = await _dio.get('https://lrclib.net/api/search', queryParameters: {'artist_name': artist, 'track_name': s.title});
      if (search.data is List) {
        for (final e in search.data as List) {
          if (e is! Map) continue;
          final d = (e['duration'] as num?)?.toDouble();
          if (secs == null || d == null || (d - secs).abs() <= 3) {
            hit = e;
            break;
          }
        }
      }
    }
    if (hit == null || hit['instrumental'] == true) return null;
    return (hit['syncedLyrics'] as String?) ?? (hit['plainLyrics'] as String?);
  }

  /// Musixmatch: sincronizada (subtitle) ou texto, sempre com o aviso de
  /// direitos e o rastreio que os termos da API exigem.
  Future<Lyrics?> _musixmatch(Song s, String artist) async {
    final key = musixmatchKey;
    if (key == null || key.isEmpty) return null;
    const base = 'https://api.musixmatch.com/ws/1.1';
    Map? bodyOf(Response r) => (((r.data is String ? jsonDecode(r.data as String) : r.data) as Map?)?['message'] as Map?)?['body'] as Map?;
    final sub = await _dio.get('$base/matcher.subtitle.get', queryParameters: {
      'q_track': s.title,
      'q_artist': artist,
      if (s.duration != null) 'f_subtitle_length': s.duration!.inSeconds,
      'f_subtitle_length_max_deviation': 3,
      'apikey': key,
    });
    final subtitle = bodyOf(sub)?['subtitle'];
    if (subtitle is Map && (subtitle['subtitle_body'] as String?)?.isNotEmpty == true) {
      _track(subtitle);
      return parseLrc(subtitle['subtitle_body'] as String)?.withSource('Musixmatch', copyright: subtitle['lyrics_copyright'] as String?);
    }
    final ly = await _dio.get('$base/matcher.lyrics.get', queryParameters: {'q_track': s.title, 'q_artist': artist, 'apikey': key});
    final lyrics = bodyOf(ly)?['lyrics'];
    final text = lyrics is Map ? lyrics['lyrics_body'] as String? : null;
    // O plano gratuito devolve só um pedaço ("...NOT for Commercial use"): não serve.
    if (text == null || text.trim().isEmpty || text.contains('NOT for Commercial use')) return null;
    _track(lyrics as Map);
    return parseLrc(text)?.withSource('Musixmatch', copyright: lyrics['lyrics_copyright'] as String?);
  }

  /// Rastreio de exibição que a Musixmatch pede em cada letra mostrada.
  void _track(Map m) {
    final url = m['pixel_tracking_url'];
    if (url is String && url.startsWith('https://')) {
      _dio.get<void>(url).catchError((_) => Response<void>(requestOptions: RequestOptions()));
    }
  }
}

/// Capa de álbum que falta, buscada na internet: Cover Art Archive
/// (MusicBrainz) e, se não achar, Deezer (API pública, uso não comercial).
/// Salva em [dir] e devolve o caminho (null = não achou).
Future<String?> fetchAlbumCover({required String artist, required String album, required String dir, required String id}) async {
  final url = await _coverArtArchive(artist, album) ?? await _deezerCover(artist, album);
  if (url == null) return null;
  try {
    final r = await _dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    if (r.statusCode != 200 || r.data == null || r.data!.length < 1000) return null;
    final out = File(p.join(dir, 'online_$id.jpg'));
    await out.parent.create(recursive: true);
    await out.writeAsBytes(r.data!);
    return out.path;
  } catch (_) {
    return null;
  }
}

bool _sameAlbum(String artist, String album, String? a, String? b) {
  final wantArtist = matchKey(artist), wantAlbum = matchKey(album);
  return a != null && b != null && matchKey(b).contains(wantAlbum) && (wantArtist.isEmpty || matchKey(a).contains(wantArtist));
}

/// MusicBrainz pede no máximo 1 consulta por segundo.
DateTime _lastMusicBrainz = DateTime.fromMillisecondsSinceEpoch(0);

Future<String?> _coverArtArchive(String artist, String album) async {
  try {
    final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_lastMusicBrainz);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastMusicBrainz = DateTime.now();
    String q(String v) => v.replaceAll(RegExp(r'["\\]'), ' ');
    final r = await _dio.get('https://musicbrainz.org/ws/2/release-group/', queryParameters: {
      'query': 'releasegroup:"${q(album)}" AND artist:"${q(artist)}"',
      'fmt': 'json',
      'limit': 5,
    });
    final groups = (r.data is Map ? (r.data as Map)['release-groups'] : null) as List? ?? const [];
    for (final g in groups) {
      if (g is! Map || ((g['score'] as num?) ?? 0) < 90) continue;
      final credit = (g['artist-credit'] as List?)?.whereType<Map>().map((c) => c['name']).join(' ');
      if (!_sameAlbum(artist, album, credit, g['title'] as String?)) continue;
      final url = 'https://coverartarchive.org/release-group/${g['id']}/front-500';
      final head = await _dio.head(url);
      if (head.statusCode == 200 || head.statusCode == 307 || head.statusCode == 302) return url;
    }
  } catch (_) {}
  return null;
}

Future<String?> _deezerCover(String artist, String album) async {
  try {
    final r = await _dio.get('https://api.deezer.com/search/album', queryParameters: {'q': '$artist $album', 'limit': 8});
    for (final e in ((r.data as Map?)?['data'] as List? ?? const [])) {
      if (e is Map && _sameAlbum(artist, album, (e['artist'] as Map?)?['name'] as String?, e['title'] as String?)) {
        return e['cover_xl'] as String? ?? e['cover_big'] as String?;
      }
    }
  } catch (_) {}
  return null;
}
