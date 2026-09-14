import 'package:dio/dio.dart';

import '../domain/models.dart';
import '../domain/music_provider.dart';

class LastFmException implements Exception {
  LastFmException(this.message);
  final String message;
  @override
  String toString() => 'Last.fm: $message';
}

/// Last.fm: músicas e artistas parecidos para a rádio e o mix quando não há
/// análise sônica (AudioMuse), e informações de artista para a biblioteca
/// local. A chave da API é do usuário (grátis em last.fm/api/account/create).
class LastFm {
  LastFm(this.apiKey);
  final String apiKey;

  static final _dio = Dio(BaseOptions(
    baseUrl: 'https://ws.audioscrobbler.com/2.0/',
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
    responseType: ResponseType.json,
  ));

  Future<Map<String, dynamic>> _call(String method, Map<String, dynamic> params) async {
    final Response<dynamic> res;
    try {
      res = await _dio.get('', queryParameters: {
        'method': method,
        'api_key': apiKey,
        'format': 'json',
        'autocorrect': 1,
        ...params,
      }, options: Options(validateStatus: (_) => true));
    } on DioException catch (e) {
      throw LastFmException(e.message ?? 'sem conexão');
    }
    final data = res.data;
    if (data is! Map) throw LastFmException('resposta inválida (HTTP ${res.statusCode})');
    if (data['error'] != null) throw LastFmException('${data['message'] ?? data['error']}');
    return Map<String, dynamic>.from(data);
  }

  static List<Map<String, dynamic>> _list(dynamic v) => switch (v) {
        List l => [for (final e in l) if (e is Map) Map<String, dynamic>.from(e)],
        Map m => [Map<String, dynamic>.from(m)],
        _ => const [],
      };

  static double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  /// Confere a chave (true = funciona).
  Future<bool> check() async {
    try {
      await _call('artist.getInfo', {'artist': 'Daft Punk'});
      return true;
    } on LastFmException {
      return false;
    }
  }

  Future<List<({String artist, String title, double match})>> similarTracks(String artist, String title,
      {int limit = 50}) async {
    final j = await _call('track.getSimilar', {'artist': artist, 'track': title, 'limit': limit});
    return [
      for (final t in _list((j['similartracks'] as Map?)?['track']))
        (artist: '${(t['artist'] as Map?)?['name'] ?? ''}', title: '${t['name'] ?? ''}', match: _num(t['match'])),
    ];
  }

  Future<List<({String name, double match})>> similarArtists(String artist, {int limit = 30}) async {
    final j = await _call('artist.getSimilar', {'artist': artist, 'limit': limit});
    return [
      for (final a in _list((j['similarartists'] as Map?)?['artist'])) (name: '${a['name'] ?? ''}', match: _num(a['match'])),
    ];
  }

  Future<List<String>> topTracks(String artist, {int limit = 30}) async {
    final j = await _call('artist.getTopTracks', {'artist': artist, 'limit': limit});
    return [for (final t in _list((j['toptracks'] as Map?)?['track'])) '${t['name'] ?? ''}'];
  }

  Future<ArtistInfo?> artistInfo(String artist) async {
    final j = await _call('artist.getInfo', {'artist': artist});
    final a = j['artist'] as Map?;
    if (a == null) return null;
    final bio = ((a['bio'] as Map?)?['summary'] as String?)?.replaceAll(RegExp(r'<a [^>]*>.*?</a>'), '').trim();
    return ArtistInfo(biography: (bio == null || bio.isEmpty) ? null : bio, lastFmUrl: a['url'] as String?);
  }
}

/// Nome para comparar entre Last.fm e a biblioteca: minúsculas, sem acento,
/// sem "(Remastered…)", "[Live]", "feat. X" e pontuação.
String matchKey(String s) {
  var t = s.toLowerCase();
  const from = 'áàâãäåéèêëíìîïóòôõöúùûüçñýÿ';
  const to = 'aaaaaaeeeeiiiiooooouuuucnyy';
  final b = StringBuffer();
  for (final ch in t.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  t = b.toString();
  t = t.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
  t = t.replaceAll(RegExp(r'\b(feat|ft|featuring)\.?\s.*$'), ' ');
  t = t.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  return t;
}

/// Músicas parecidas pelo Last.fm, procuradas no servidor (para quem não tem
/// o AudioMuse). Faz as buscas em lotes para não travar o servidor.
Future<List<Song>> similarViaLastFm(MusicProvider p, LastFm fm, Song seed, {int count = 40}) async {
  final artist = seed.artist ?? seed.displayArtist;
  if (artist.isEmpty) return const [];
  final similar = await fm.similarTracks(artist, seed.title, limit: count * 2);
  final out = <Song>[];
  final seen = <String>{seed.id};
  for (var i = 0; i < similar.length && out.length < count; i += 6) {
    final batch = similar.skip(i).take(6).toList();
    final found = await Future.wait(batch.map((s) async {
      try {
        final r = await p.search('${s.artist} ${s.title}', artistCount: 0, albumCount: 0, songCount: 5);
        final want = (matchKey(s.artist), matchKey(s.title));
        return r.songs.where((x) => matchKey(x.title) == want.$2 && matchKey(x.displayArtist).contains(want.$1)).firstOrNull;
      } catch (_) {
        return null;
      }
    }));
    for (final s in found) {
      if (s != null && seen.add(s.id)) out.add(s);
    }
  }
  return out;
}
