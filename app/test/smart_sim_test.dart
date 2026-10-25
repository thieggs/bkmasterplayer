import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/recommend.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/player/smart_session.dart';
import 'package:player_musica/src/rust/api/recommend.dart' as rust;
import 'package:player_musica/src/rust/frb_generated.dart';

/// Simulação do aleatório smart com a biblioteca de verdade, o motor de
/// verdade e a sessão de verdade.
///
/// Um ouvinte de mentira gosta de um gênero — pelas tags do Navidrome, que o
/// modo não vê — e se comporta como gente: ouve inteiro quase tudo o que gosta
/// (às vezes enjoa no meio), pula logo quase tudo o que não gosta (às vezes
/// enjoa no meio, às vezes deixa tocar distraído). Mede quantas das músicas
/// escolhidas são do gosto dele, por trecho da sessão, contra o sorteio puro
/// (a parte da biblioteca que é do gênero).
///
/// Não roda na suíte normal: precisa do motor em release, dos vetores e dos
/// gêneros.
///
///     python3 dev/generos_navidrome.py > /tmp/generos.json
///     SMART_SIM_VETORES=~/.local/share/io.github.playermusica.player_musica/vetores.bkvec \
///     SMART_SIM_GENEROS=/tmp/generos.json flutter test test/smart_sim_test.dart
void main() {
  final lib = File('rust/target/release/libplayer_engine.so');
  final vetores = Platform.environment['SMART_SIM_VETORES'];
  final generos = Platform.environment['SMART_SIM_GENEROS'];
  final skip = vetores == null || generos == null || !lib.existsSync() ? 'simulação: ver o comentário do arquivo' : null;

  test('o modo acha o gosto escondido e acompanha quando ele muda', () async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(lib.absolute.path));
    await rust.recommendLoad(path: vetores!);
    final j = jsonDecode(await File(generos!).readAsString()) as Map<String, dynamic>;
    final songs = <String, Song>{};
    final genero = <String, Set<String>>{};
    for (final MapEntry(:key, :value) in j.entries) {
      final m = value as Map<String, dynamic>;
      songs[key] = Song(
        id: key,
        title: m['t'] as String? ?? key,
        artist: m['a'] as String?,
        duration: Duration(milliseconds: (((m['d'] as num?) ?? 180) * 1000).round()),
      );
      genero[key] = {for (final g in (m['g'] as List? ?? const [])) (g as String).toLowerCase()};
    }
    // O modo só escolhe entre as que têm vetor; a régua do sorteio também.
    final comVetor = [for (final id in songs.keys) if (await rust.recommendKnows(id: id)) id];
    final source = _Sim(songs);

    bool gosta(Song s, Set<String> gosto) => (genero[s.id] ?? const {}).any(gosto.contains);
    double base(Set<String> gosto) => comVetor.where((id) => gosta(songs[id]!, gosto)).length / comVetor.length;

    var rodadasTarde = 0, semIma = 0, procurando = 0;

    /// Uma sessão de [n] músicas, como o player faz: rodada nova quando sobra
    /// menos da metade, e depois de um "não gostei" saem da fila as que caíram
    /// no que é para evitar. [gostaAgora] diz se a pessoa gosta da música que
    /// toca na posição t. Devolve, para cada posição, se ela gostou e se a
    /// música veio de um ímã (o resto é amostra).
    Future<List<(bool, bool)>> sessao(int seed, bool Function(Song, int) gostaAgora, {int n = 60}) async {
      final r = Random(seed);
      final session = SmartSession(random: Random(seed + 7919));
      final played = <Song>[];
      final upcoming = await session.next(want: 4, history: const [], source: source);
      Future<void> completa() async {
        if (upcoming.length < 2) {
          if (played.length > 20) {
            rodadasTarde++;
            if (session.anchors().isEmpty) semIma++;
            if (session.searching) procurando++;
          }
          upcoming.addAll(await session.next(want: 4, history: [...played, ...upcoming], source: source));
        }
      }

      final acertos = <(bool, bool)>[];
      for (var t = 0; t < n && upcoming.isNotEmpty; t++) {
        final song = upcoming.removeAt(0);
        played.add(song);
        await completa();
        final ok = gostaAgora(song, t);
        final x = r.nextDouble();
        // Do que gosta: ouve inteira 85%, enjoa no meio 15%. Do que não gosta:
        // pula logo 80%, enjoa no meio 15%, deixa tocar distraído 5%.
        final sinal = ok ? (x < 0.85 ? 1 : 0) : (x < 0.8 ? -1 : (x < 0.95 ? 0 : 1));
        acertos.add((ok, session.originOf(song.id) != null));
        session.left(song, sinal);
        if (sinal < 0) {
          final ruins = await source.smartAvoided(upcoming, session.avoided(), [for (final (s, _) in session.anchors()) s]);
          upcoming.removeWhere((s) => ruins.contains(s.id));
          await completa();
        }
      }
      return acertos;
    }

    String pct(double x) => '${(x * 100).round()}%'.padLeft(4);
    double media(List<List<(bool, bool)>> runs, int de, int ate, {bool? doIma}) {
      var sim = 0, total = 0;
      for (final a in runs) {
        for (var i = de; i < ate && i < a.length; i++) {
          if (doIma != null && a[i].$2 != doIma) continue;
          total++;
          if (a[i].$1) sim++;
        }
      }
      return total == 0 ? 0 : sim / total;
    }

    double parte(List<List<(bool, bool)>> runs, int de, int ate) {
      var ima = 0, total = 0;
      for (final a in runs) {
        for (var i = de; i < ate && i < a.length; i++) {
          total++;
          if (a[i].$2) ima++;
        }
      }
      return total == 0 ? 0 : ima / total;
    }

    const rodadas = 40;
    final gostos = <String, Set<String>>{
      'samba/pagode': {'samba', 'pagode'},
      'metal/rock': {'metal', 'rock', 'hard rock'},
      'religiosa': {'música religiosa', 'gospel', 'christian', 'ccm', 'inspirational'},
      'jazz/soul/r&b': {'jazz', 'soul & funk', 'r&b'},
      'rap/hip hop': {'rap', 'hip hop', 'hip-hop'},
    };
    debugPrint('Aleatório smart, ${comVetor.length} músicas com vetor, $rodadas sessões de 60 por gosto');
    debugPrint('gosto            sorteio   1–10  11–20  21–40  41–60 | 21–60: dos ímãs (acerto) · amostras (acerto)');
    for (final MapEntry(key: nome, value: gosto) in gostos.entries) {
      final runs = [for (var s = 0; s < rodadas; s++) await sessao(s, (song, _) => gosta(song, gosto))];
      final b = base(gosto);
      debugPrint('${nome.padRight(16)} ${pct(b)}     ${pct(media(runs, 0, 10))}  ${pct(media(runs, 10, 20))}  '
          '${pct(media(runs, 20, 40))}  ${pct(media(runs, 40, 60))} | '
          '${pct(parte(runs, 20, 60))} (${pct(media(runs, 20, 60, doIma: true))}) · '
          '${pct(1 - parte(runs, 20, 60))} (${pct(media(runs, 20, 60, doIma: false))})');
      expect(media(runs, 20, 60), greaterThan(b), reason: '$nome: o modo tem de ganhar do sorteio');
      debugPrint('    rodadas depois da 20ª: $rodadasTarde, sem ímã: $semIma, procurando: $procurando');
      rodadasTarde = semIma = procurando = 0;
    }

    // O gosto muda no meio: samba/pagode até a 30ª, metal/rock depois.
    final antes = gostos['samba/pagode']!, depois = gostos['metal/rock']!;
    final troca = [
      for (var s = 0; s < rodadas; s++) await sessao(100 + s, (song, t) => gosta(song, t < 30 ? antes : depois)),
    ];
    debugPrint('troca de gosto na 30ª (samba/pagode → metal/rock): 21–30 ${pct(media(troca, 20, 30))} · '
        '31–35 ${pct(media(troca, 30, 35))} · 36–40 ${pct(media(troca, 35, 40))} · '
        '41–50 ${pct(media(troca, 40, 50))} · 51–60 ${pct(media(troca, 50, 60))}');

    // Dois gostos ao mesmo tempo: os dois têm de continuar vindo.
    final dois = antes.union(depois);
    final tocadas = <Song>[];
    for (var s = 0; s < rodadas; s++) {
      await sessao(200 + s, (song, t) {
        if (t >= 20) tocadas.add(song);
        return gosta(song, dois);
      });
    }
    final deA = tocadas.where((x) => gosta(x, antes)).length, deB = tocadas.where((x) => gosta(x, depois)).length;
    debugPrint('dois gostos (samba/pagode + metal/rock), músicas 21–60: $deA de samba/pagode, $deB de metal/rock, '
        '${tocadas.length - deA - deB} de outros');
    expect(min(deA, deB), greaterThan(0), reason: 'os dois estilos continuam vindo');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 30)));
}

/// O motor de verdade, com as músicas montadas a partir do arquivo de gêneros.
class _Sim implements SmartSource {
  _Sim(this.songs);
  final Map<String, Song> songs;

  @override
  Future<List<(Song, int, double)>> smartNeighbors(
    List<Song> anchors, {
    required List<Song> avoid,
    required RecommendStyle style,
    required int perAnchor,
    required Set<String> exclude,
  }) async {
    final r = await rust.recommendSmart(
      anchors: [for (final a in anchors) a.id],
      avoid: [for (final a in avoid) a.id],
      style: style.id,
      perAnchor: perAnchor,
      exclude: exclude.toList(),
      allowed: const [],
    );
    return [for (final h in r) if (songs[h.id] case final s?) (s, h.anchor, h.score)];
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
    final ids = await rust.recommendExplore(
      count: count,
      known: [for (final s in known) s.id],
      avoid: [for (final s in avoid) s.id],
      liked: [for (final s in liked) s.id],
      exclude: exclude.toList(),
      allowed: const [],
      spread: spread,
      seed: seed,
    );
    return [for (final id in ids) ?songs[id]];
  }

  @override
  Future<Set<String>> smartAvoided(List<Song> list, List<Song> avoid, List<Song> liked) async =>
      (await rust.recommendAvoided(
        ids: [for (final s in list) s.id],
        avoid: [for (final s in avoid) s.id],
        liked: [for (final s in liked) s.id],
      ))
          .toSet();
}
