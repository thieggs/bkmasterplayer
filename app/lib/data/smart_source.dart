import '../domain/models.dart';
import '../domain/music_provider.dart';
import 'lastfm.dart';
import 'recommend.dart';
import 'similar.dart';

/// Aleatório smart sem a análise guardada no aparelho: o servidor responde do
/// jeito que der (ver `player/smart_session.dart`).
///
/// As parecidas de cada ímã vêm de [findSimilarScored] pelo servidor (a
/// análise sônica do AudioMuse, o "similar" do Navidrome ou o Last.fm), e as
/// amostras são o aleatório dele. Sem os vetores não há distância para medir,
/// então não existem gêmeas nem zonas: só a própria música pulada sai. A tela
/// avisa, como a rádio já faz.
class ServerSmartSource implements SmartSource {
  ServerSmartSource(this.provider, {this.lastFm});

  final MusicProvider provider;
  final LastFm? lastFm;

  @override
  Future<List<(Song, int, double)>> smartNeighbors(
    List<Song> anchors, {
    required List<Song> avoid,
    required RecommendStyle style,
    required int perAnchor,
    required Set<String> exclude,
  }) async {
    final out = <(Song, int, double)>[];
    for (final (i, a) in anchors.indexed) {
      final r = await findSimilarScored(provider, a, count: perAnchor * 2, lastFm: lastFm, style: RecommendStyle.server);
      out.addAll([for (final (s, nota) in r) if (!exclude.contains(s.id)) (s, i, nota)].take(perAnchor));
    }
    return out;
  }

  @override
  Future<List<Song>> smartExplore(
    int count, {
    required List<Song> known,
    required List<Song> avoid,
    required List<Song> liked,
    required Set<String> exclude,
    required bool spread,
    required int seed,
  }) async {
    final r = await provider.randomSongs(size: count + 10);
    return [for (final s in r) if (!exclude.contains(s.id)) s].take(count).toList();
  }

  @override
  Future<Set<String>> smartAvoided(List<Song> songs, List<Song> avoid, List<Song> liked) async => const {};
}
