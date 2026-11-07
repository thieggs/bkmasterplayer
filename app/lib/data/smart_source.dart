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
/// então não existem gêmeas nem zonas: só a própria música pulada sai. A
/// marcada com o botão "−" leva junto o artista dela — o mais perto de "esse
/// tipo de música" que dá para dizer sem os vetores. A tela avisa, como a
/// rádio já faz.
class ServerSmartSource implements SmartSource {
  ServerSmartSource(this.provider, {this.lastFm});

  final MusicProvider provider;
  final LastFm? lastFm;

  /// O artista de [s] para a regra do "−" (o id, ou o nome sem maiúsculas).
  static String? _artist(Song s) => s.artistId ?? s.artist?.trim().toLowerCase();

  static bool Function(Song) _outside(List<Song> never) {
    if (never.isEmpty) return (_) => true;
    final ids = {for (final s in never) s.id};
    final artistas = {for (final s in never) ?_artist(s)};
    return (s) => !ids.contains(s.id) && !artistas.contains(_artist(s));
  }

  @override
  Future<List<(Song, int, double)>> smartNeighbors(
    List<Song> anchors, {
    required List<Song> avoid,
    List<Song> never = const [],
    List<Song> keep = const [],
    required RecommendStyle style,
    required int perAnchor,
    required Set<String> exclude,
  }) async {
    final ok = _outside(never);
    final out = <(Song, int, double)>[];
    for (final (i, a) in anchors.indexed) {
      final r = await findSimilarScored(provider, a, count: perAnchor * 2, lastFm: lastFm, style: RecommendStyle.server);
      out.addAll([for (final (s, nota) in r) if (!exclude.contains(s.id) && ok(s)) (s, i, nota)].take(perAnchor));
    }
    return out;
  }

  @override
  Future<List<Song>> smartExplore(
    int count, {
    required List<Song> known,
    required List<Song> avoid,
    List<Song> never = const [],
    required List<Song> liked,
    List<Song> keep = const [],
    required Set<String> exclude,
    required bool spread,
    required int seed,
  }) async {
    final ok = _outside(never);
    final r = await provider.randomSongs(size: count + 10);
    return [for (final s in r) if (!exclude.contains(s.id) && ok(s)) s].take(count).toList();
  }

  @override
  Future<Set<String>> smartAvoided(List<Song> songs, List<Song> avoid, List<Song> liked,
      {List<Song> never = const [], List<Song> keep = const []}) async {
    final ok = _outside(never);
    return {for (final s in songs) if (!ok(s)) s.id};
  }
}
