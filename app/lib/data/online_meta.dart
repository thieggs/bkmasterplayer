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
  headers: {'User-Agent': 'BKplayer/1.0 (open source music player)'},
  validateStatus: (_) => true,
));

String _hash(String s) => sha1.convert(utf8.encode(s)).toString().substring(0, 20);

/// Letras que faltam no servidor/arquivo, buscadas na internet:
/// LRCLIB (aberto, com letras sincronizadas) → Musixmatch (API oficial, com a
/// chave do usuário; só letras completas) → lyrics.ovh (texto). Guarda o
/// resultado (ou a falta dele, por 7 dias) no disco.
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
        if (j['lrc'] is String) return parseLrc(j['lrc'] as String);
        final missed = DateTime.fromMillisecondsSinceEpoch(j['missed'] as int? ?? 0);
        if (DateTime.now().difference(missed) < const Duration(days: 7)) return null;
      }
    } catch (_) {}
    String? lrc;
    for (final source in [_lrclib, _musixmatch, _lyricsOvh]) {
      try {
        lrc = await source(song, artist);
      } catch (_) {}
      if (lrc != null && lrc.trim().isNotEmpty) break;
      lrc = null;
    }
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(lrc == null ? {'missed': DateTime.now().millisecondsSinceEpoch} : {'lrc': lrc}));
    } catch (_) {}
    return lrc == null ? null : parseLrc(lrc);
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

  Future<String?> _musixmatch(Song s, String artist) async {
    final key = musixmatchKey;
    if (key == null || key.isEmpty) return null;
    const base = 'https://api.musixmatch.com/ws/1.1';
    final sub = await _dio.get('$base/matcher.subtitle.get', queryParameters: {
      'q_track': s.title,
      'q_artist': artist,
      if (s.duration != null) 'f_subtitle_length': s.duration!.inSeconds,
      'f_subtitle_length_max_deviation': 3,
      'apikey': key,
    });
    final body = (((sub.data is String ? jsonDecode(sub.data as String) : sub.data) as Map?)?['message'] as Map?)?['body'];
    final lrc = body is Map ? ((body['subtitle'] as Map?)?['subtitle_body'] as String?) : null;
    if (lrc != null && lrc.isNotEmpty) return lrc;
    final ly = await _dio.get('$base/matcher.lyrics.get', queryParameters: {'q_track': s.title, 'q_artist': artist, 'apikey': key});
    final lb = (((ly.data is String ? jsonDecode(ly.data as String) : ly.data) as Map?)?['message'] as Map?)?['body'];
    final text = lb is Map ? ((lb['lyrics'] as Map?)?['lyrics_body'] as String?) : null;
    // O plano gratuito devolve só um pedaço ("...NOT for Commercial use"): não serve.
    if (text == null || text.contains('NOT for Commercial use')) return null;
    return text;
  }

  Future<String?> _lyricsOvh(Song s, String artist) async {
    final res = await _dio.get('https://api.lyrics.ovh/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(s.title)}');
    return res.statusCode == 200 && res.data is Map ? (res.data as Map)['lyrics'] as String? : null;
  }
}

/// Capa de álbum que falta, buscada na internet (iTunes, Deezer). Salva em
/// [dir] e devolve o caminho (null = não achou).
Future<String?> fetchAlbumCover({required String artist, required String album, required String dir, required String id}) async {
  final want = (matchKey(artist), matchKey(album));
  bool same(String? a, String? b) =>
      a != null && b != null && matchKey(b).contains(want.$2) && (want.$1.isEmpty || matchKey(a).contains(want.$1));
  String? url;
  try {
    final r = await _dio.get('https://itunes.apple.com/search',
        queryParameters: {'term': '$artist $album', 'entity': 'album', 'limit': 8});
    final data = r.data is String ? jsonDecode(r.data as String) : r.data;
    for (final e in ((data as Map?)?['results'] as List? ?? const [])) {
      if (e is Map && same(e['artistName'] as String?, e['collectionName'] as String?)) {
        url = (e['artworkUrl100'] as String?)?.replaceAll('100x100bb', '600x600bb');
        break;
      }
    }
  } catch (_) {}
  if (url == null) {
    try {
      final r = await _dio.get('https://api.deezer.com/search/album', queryParameters: {'q': '$artist $album', 'limit': 8});
      for (final e in ((r.data as Map?)?['data'] as List? ?? const [])) {
        if (e is Map && same((e['artist'] as Map?)?['name'] as String?, e['title'] as String?)) {
          url = e['cover_xl'] as String? ?? e['cover_big'] as String?;
          break;
        }
      }
    } catch (_) {}
  }
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
