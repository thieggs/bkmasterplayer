import '../domain/models.dart';
import '../domain/music_provider.dart';
import 'lastfm.dart';
import 'local/local_provider.dart';

/// "Parecidas" com [seed] (mix instantâneo e rádio):
/// - servidor com AudioMuse: o "similar" do servidor (análise sônica);
/// - sem AudioMuse e com Last.fm: parecidas do Last.fm achadas no servidor;
/// - senão: o "similar" do servidor (a biblioteca local já usa o Last.fm).
Future<List<Song>> findSimilar(MusicProvider p, Song seed, {int count = 50, LastFm? lastFm}) async {
  final sonic = p.serverInfo?.sonicSimilarity ?? false;
  if (!sonic && lastFm != null && p is! LocalProvider) {
    try {
      final r = await similarViaLastFm(p, lastFm, seed, count: count);
      if (r.length >= 5) return r;
    } catch (_) {}
  }
  return p.similarSongs(seed.id, count: count);
}
