import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/music_provider.dart';
import 'lastfm.dart';
import 'local/local_provider.dart';
import 'recommend.dart';

/// "Parecidas" com [seed] (mix instantâneo e rádio):
/// - com os vetores do AudioMuse no aparelho: a conta é feita aqui, que
///   funciona sem internet, respeita o estilo escolhido e gasta menos
///   bateria que perguntar ao servidor;
/// - servidor com AudioMuse: o "similar" do servidor (análise sônica);
/// - sem AudioMuse e com Last.fm: parecidas do Last.fm achadas no servidor;
/// - senão: o "similar" do servidor (a biblioteca local já usa o Last.fm).
Future<List<Song>> findSimilar(MusicProvider p, Song seed, {int count = 50, LastFm? lastFm, RecommendNotifier? local}) async {
  if (local != null && local.ready) {
    try {
      final r = await local.similar(seed, count: count);
      if (r.isNotEmpty) return r;
    } catch (e) {
      debugPrint('parecidas no aparelho: $e');
    }
  }
  final sonic = p.serverInfo?.sonicSimilarity ?? false;
  if (!sonic && lastFm != null && p is! LocalProvider) {
    try {
      final r = await similarViaLastFm(p, lastFm, seed, count: count);
      if (r.length >= 5) return r;
    } catch (_) {}
  }
  return p.similarSongs(seed.id, count: count);
}
