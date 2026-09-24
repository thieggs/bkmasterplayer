import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../domain/models.dart';
import 'recommend.dart';

/// O que a pessoa pediu na tela de gerar playlist.
@immutable
class GenCriteria {
  const GenCriteria({
    this.seed,
    this.style = RecommendStyle.sound,
    this.genre,
    this.fromYear,
    this.toYear,
    this.minutes = 60,
    this.byMinutes = true,
    this.count = 25,
    this.onlyStarred = false,
    this.onlyDownloaded = false,
  });

  /// Música de partida (vem do menu de uma música, ou escolhida na tela).
  final Song? seed;

  /// Por onde a análise do AudioMuse se guia, quando há semente.
  final RecommendStyle style;
  final String? genre;
  final int? fromYear;
  final int? toYear;

  /// Tamanho: por tempo (mais natural para ouvir) ou por número de músicas.
  final int minutes;
  final bool byMinutes;
  final int count;

  final bool onlyStarred;
  final bool onlyDownloaded;

  GenCriteria copyWith({
    Song? seed,
    bool clearSeed = false,
    RecommendStyle? style,
    String? genre,
    bool clearGenre = false,
    int? fromYear,
    int? toYear,
    bool clearYears = false,
    int? minutes,
    bool? byMinutes,
    int? count,
    bool? onlyStarred,
    bool? onlyDownloaded,
  }) =>
      GenCriteria(
        seed: clearSeed ? null : (seed ?? this.seed),
        style: style ?? this.style,
        genre: clearGenre ? null : (genre ?? this.genre),
        fromYear: clearYears ? null : (fromYear ?? this.fromYear),
        toYear: clearYears ? null : (toYear ?? this.toYear),
        minutes: minutes ?? this.minutes,
        byMinutes: byMinutes ?? this.byMinutes,
        count: count ?? this.count,
        onlyStarred: onlyStarred ?? this.onlyStarred,
        onlyDownloaded: onlyDownloaded ?? this.onlyDownloaded,
      );
}

/// Serve para esta playlist? (época, favorita, gênero — o resto já vem
/// filtrado de onde as músicas foram buscadas.)
@visibleForTesting
bool serve(Song s, GenCriteria c) {
  if (c.onlyStarred && !s.isStarred) return false;
  final ano = s.year;
  if (c.fromYear != null && (ano == null || ano < c.fromYear!)) return false;
  if (c.toYear != null && (ano == null || ano > c.toYear!)) return false;
  if (c.genre != null) {
    final g = [if (s.genre != null) s.genre!, ...s.genres].map((x) => x.toLowerCase());
    if (!g.contains(c.genre!.toLowerCase())) return false;
  }
  return true;
}

/// Monta a lista final a partir das candidatas.
///
/// [candidatas] já vem na ordem que importa: com semente, é a ordem de
/// parecença que o AudioMuse deu; sem semente, vem embaralhada. A semente
/// abre a playlist e nunca se repete no meio.
@visibleForTesting
List<Song> montaPlaylist(List<Song> candidatas, GenCriteria c) {
  final escolhidas = <Song>[];
  final vistas = <String>{};
  var total = Duration.zero;
  final limite = Duration(minutes: c.minutes);

  void tentar(Song s) {
    if (!vistas.add(s.id)) return;
    escolhidas.add(s);
    total += s.duration ?? const Duration(minutes: 4);
  }

  final semente = c.seed;
  if (semente != null && serve(semente, c)) tentar(semente);
  for (final s in candidatas) {
    if (c.byMinutes ? total >= limite : escolhidas.length >= c.count) break;
    if (!serve(s, c)) continue;
    tentar(s);
  }
  return escolhidas;
}

class GenState {
  const GenState({this.criteria = const GenCriteria(), this.songs = const [], this.working = false, this.error});

  final GenCriteria criteria;
  final List<Song> songs;
  final bool working;
  final String? error;

  GenState copyWith({GenCriteria? criteria, List<Song>? songs, bool? working, String? error, bool clearError = false}) =>
      GenState(
        criteria: criteria ?? this.criteria,
        songs: songs ?? this.songs,
        working: working ?? this.working,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Gera a playlist: junta um monte de candidatas, ordena e corta no tamanho.
class GenNotifier extends Notifier<GenState> {
  @override
  GenState build() => const GenState();

  void set(GenCriteria Function(GenCriteria) f) =>
      state = state.copyWith(criteria: f(state.criteria), clearError: true);

  /// De onde saem as candidatas, da mais específica para a mais ampla.
  Future<List<Song>> _candidatas(GenCriteria c) async {
    final rec = ref.read(recommendProvider.notifier);
    if (c.onlyDownloaded) return rec.downloaded();
    final p = ref.read(musicProvider);
    if (c.genre != null) return p.songsByGenre(c.genre!, count: 500);
    if (c.onlyStarred) return p.starredSongs();
    return p.randomSongs(size: 500);
  }

  Future<void> generate() async {
    if (state.working) return;
    final c = state.criteria;
    state = state.copyWith(working: true, clearError: true);
    try {
      var candidatas = await _candidatas(c);
      final semente = c.seed;
      if (semente != null) {
        final rec = ref.read(recommendProvider.notifier);
        // Com os vetores no aparelho a ordem é por parecença; o `pool` faz a
        // recomendação respeitar os filtros em vez de brigar com eles.
        final pool = [for (final s in candidatas) if (serve(s, c)) s];
        final parecidas = await rec.similar(semente, style: c.style, count: 300, pool: pool);
        if (parecidas.isNotEmpty) {
          candidatas = parecidas;
        } else {
          candidatas = [...candidatas]..shuffle(Random());
        }
      } else {
        candidatas = [...candidatas]..shuffle(Random());
      }
      state = state.copyWith(songs: montaPlaylist(candidatas, c), working: false);
    } catch (e) {
      state = state.copyWith(working: false, error: '$e');
    }
  }

  void clear() => state = state.copyWith(songs: const []);
}

final generateProvider = NotifierProvider<GenNotifier, GenState>(GenNotifier.new);
