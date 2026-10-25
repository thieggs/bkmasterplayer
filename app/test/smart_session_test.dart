import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/recommend.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/player/radio.dart';
import 'package:player_musica/player/smart_session.dart';

/// O aleatório smart: ímãs que não se misturam, pulos que afastam, exploração,
/// esquecimento. A conta das distâncias é do motor (testada no Rust); aqui a
/// fonte é de mentira. Ver `player/smart_session.dart`.

Song _s(String id, {String? artist, Duration? duration}) =>
    Song(id: id, title: id, artist: artist ?? 'artista $id', duration: duration ?? const Duration(minutes: 3));

List<Song> _many(String prefix, int n) => [for (var i = 0; i < n; i++) _s('$prefix$i')];

/// Fonte de mentira: cada ímã tem uma lista fixa de vizinhas, as amostras
/// saem de uma lista fixa, e cada pulada leva junto as gêmeas declaradas.
class _Fake implements SmartSource {
  _Fake({this.neighbors = const {}, this.samples = const [], this.twins = const {}});

  final Map<String, List<Song>> neighbors;
  final List<Song> samples;
  final Map<String, Set<String>> twins;
  final asked = <List<String>>[];
  final explored = <({int count, bool spread, List<String> known})>[];

  Set<String> _blocked(List<Song> avoid) => {for (final a in avoid) ...{a.id, ...?twins[a.id]}};

  @override
  Future<List<(Song, int, double)>> smartNeighbors(
    List<Song> anchors, {
    required List<Song> avoid,
    required RecommendStyle style,
    required int perAnchor,
    required Set<String> exclude,
  }) async {
    asked.add([for (final a in anchors) a.id]);
    final fora = _blocked(avoid);
    return [
      for (final (i, a) in anchors.indexed)
        for (final (j, s) in (neighbors[a.id] ?? const <Song>[])
            .where((s) => !exclude.contains(s.id) && !fora.contains(s.id))
            .take(perAnchor)
            .indexed)
          (s, i, 1 - j / 100),
    ];
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
    explored.add((count: count, spread: spread, known: [for (final s in known) s.id]));
    final fora = _blocked(avoid);
    return samples.where((s) => !exclude.contains(s.id) && !fora.contains(s.id)).take(count).toList();
  }

  @override
  Future<Set<String>> smartAvoided(List<Song> songs, List<Song> avoid, List<Song> liked) async {
    final fora = _blocked(avoid);
    return {for (final s in songs) if (fora.contains(s.id)) s.id};
  }
}

void main() {
  test('sem música escolhida, a primeira rodada é toda de amostras (variado ou puro)', () async {
    final fake = _Fake(samples: _many('x', 12));
    final r = await SmartSession(random: Random(1)).next(want: 4, history: const [], source: fake);
    expect(r.map((s) => s.id), ['x0', 'x1', 'x2', 'x3']);
    expect(fake.asked, isEmpty, reason: 'ainda não há ímã');
    expect(fake.explored.single.spread, isTrue, reason: 'padrão: cada amostra de um canto');

    final puro = _Fake(samples: _many('x', 12));
    await SmartSession(start: SmartStart.pure, random: Random(1)).next(want: 4, history: const [], source: puro);
    expect(puro.explored.single.spread, isFalse);
  });

  test('com música escolhida, a rodada vem em volta dela e uma vaga a cada quatro explora', () async {
    final seed = _s('semente');
    final fake = _Fake(neighbors: {'semente': _many('n', 20)}, samples: _many('x', 10));
    final session = SmartSession(seed: seed, random: Random(2));
    final r = await session.next(want: 4, history: [seed], source: fake);
    final fila = [seed, ...r].map((s) => s.id).toList();
    expect(fila, hasLength(5));
    // A semente conta como a primeira das quatro: a quarta música da fila explora.
    expect(fila[3], startsWith('x'), reason: '$fila');
    expect(fila.where((id) => id.startsWith('x')), hasLength(1), reason: '$fila');
    expect(fake.asked.single, ['semente']);

    // A seguinte continua contando de onde a fila parou, não do zero.
    final r2 = await session.next(want: 4, history: [seed, ...r], source: fake);
    expect([...fila, ...r2.map((s) => s.id)].indexed.where((e) => e.$2.startsWith('x')).map((e) => e.$1), [3, 7]);
  });

  test('ouviu inteira vira ímã; pulou rápido sai e leva as gêmeas', () async {
    final rock = _s('rock');
    final pulada = _s('pulada');
    final fake = _Fake(
      neighbors: {'rock': [_s('gemea'), _s('r1'), _s('r2'), _s('r3'), _s('r4')]},
      samples: [_s('pulada'), ..._many('x', 6)],
      twins: {'pulada': {'gemea'}},
    );
    final session = SmartSession(explore: SmartExplore.low, random: Random(3))
      ..left(rock, 1)
      ..left(pulada, -1);
    expect(session.anchors().map((a) => a.$1.id), ['rock']);
    expect(session.avoided().map((s) => s.id), ['pulada']);
    final r = await session.next(want: 4, history: [rock, pulada], source: fake);
    final ids = r.map((s) => s.id).toList();
    expect(ids, isNot(contains('gemea')), reason: 'gêmea da pulada');
    expect(ids, isNot(contains('pulada')));
    expect(ids.where((id) => id.startsWith('r')), hasLength(greaterThanOrEqualTo(3)));
  });

  test('dois estilos aprovados: os dois continuam vindo, sem misturar', () async {
    final rock = _s('rock');
    final samba = _s('samba');
    final fake = _Fake(
      neighbors: {'rock': _many('r', 10), 'samba': _many('s', 10)},
      samples: _many('x', 10),
    );
    for (var seed = 0; seed < 5; seed++) {
      final session = SmartSession(explore: SmartExplore.low, random: Random(seed))
        ..left(rock, 1)
        ..left(samba, 1);
      final ids = (await session.next(want: 8, history: [rock, samba], source: fake)).map((s) => s.id).toList();
      expect(ids.where((id) => id.startsWith('r')), isNotEmpty, reason: 'semente $seed: $ids');
      expect(ids.where((id) => id.startsWith('s')), isNotEmpty, reason: 'semente $seed: $ids');
    }
  });

  test('tudo esquece aos poucos: o gosto pode mudar no meio', () {
    final session = SmartSession()
      ..left(_s('antiga'), 1)
      ..left(_s('pulada'), -1);
    for (var i = 0; i < 30; i++) {
      session.left(_s('neutra$i'), 0);
    }
    expect(session.avoided().map((s) => s.id), ['pulada'], reason: 'pulo afasta por duas meias-vidas');
    expect(session.anchors().map((a) => a.$1.id), ['antiga']);
    session.left(_s('mais'), 0);
    expect(session.avoided(), isEmpty);
    for (var i = 0; i < 14; i++) {
      session.left(_s('outra$i'), 0);
    }
    expect(session.anchors(), isEmpty, reason: 'uma aprovada só, mais de quarenta músicas atrás');
  });

  test('rajada de pulos do que veio dos ímãs: metade da rodada vai procurar noutro canto', () async {
    final seed = _s('semente');
    final fake = _Fake(neighbors: {'semente': _many('n', 20)}, samples: _many('x', 10));
    final session = SmartSession(seed: seed, explore: SmartExplore.low, random: Random(4));
    final primeira = await session.next(want: 3, history: [seed], source: fake);
    expect(primeira.every((s) => session.originOf(s.id) == 'semente'), isTrue);
    for (final s in primeira) {
      session.left(s, -1);
    }
    expect(session.searching, isTrue);
    expect(session.exploreEvery, 4);
    final r = await session.next(want: 4, history: [seed, ...primeira], source: fake);
    expect(r.where((s) => s.id.startsWith('x')), hasLength(2));

    // Pular amostra não é rajada: com gosto estreito quase toda amostra é
    // pulada, e explorar mais por isso só traria mais amostras para pular.
    final outra = SmartSession(random: Random(4));
    for (final s in await outra.next(want: 3, history: const [], source: _Fake(samples: _many('x', 10)))) {
      outra.left(s, -1);
    }
    expect(outra.searching, isFalse);
  });

  test('seis aprovadas seguidas: explora menos, nunca menos de uma a cada oito', () async {
    final seed = _s('semente');
    final session = SmartSession(seed: seed, explore: SmartExplore.low, random: Random(5));
    final r = await session.next(want: 6, history: [seed], source: _Fake(neighbors: {'semente': _many('n', 10)}));
    for (final s in r) {
      session.left(s, 1);
    }
    expect(session.confident, isTrue);
    session.explore = SmartExplore.mid;
    expect(session.exploreEvery, 8);
    session.explore = SmartExplore.high;
    expect(session.exploreEvery, 4);
  });

  test('ímã que só traz pulo perde força; o que acerta ganha', () async {
    final boa = _s('boa'), distraida = _s('distraida');
    final fake = _Fake(neighbors: {'boa': _many('b', 10), 'distraida': _many('d', 10)}, samples: _many('x', 5));
    final session = SmartSession(explore: SmartExplore.low, random: Random(6))
      ..left(boa, 1)
      ..left(distraida, 1);
    final r = await session.next(want: 7, history: [boa, distraida], source: fake);
    final dosImas = r.where((s) => !s.id.startsWith('x')).toList();
    expect(dosImas.map((s) => s.id[0]).toSet(), {'b', 'd'}, reason: 'os dois ímãs trouxeram alguma');
    for (final s in dosImas) {
      session.left(s, s.id.startsWith('b') ? 1 : -1);
    }
    final peso = {for (final (s, w) in session.anchors()) s.id: w};
    expect(peso['boa']!, greaterThan(2 * (peso['distraida'] ?? 0)), reason: '$peso');
  });

  test('desfazer o aviso: o pulo não vale e a música pode voltar', () async {
    final session = SmartSession()..left(_s('dedo-errado'), -1);
    expect(session.avoided(), hasLength(1));
    session.undo('dedo-errado');
    expect(session.avoided(), isEmpty);
    final fake = _Fake(samples: [_s('dedo-errado'), ..._many('x', 5)]);
    final r = await session.next(want: 2, history: const [], source: fake);
    expect(r.map((s) => s.id), contains('dedo-errado'));
  });

  test('favoritar pesa mais que ouvir inteira, e desfavoritar tira o peso', () {
    final session = SmartSession()
      ..left(_s('boa'), 1)
      ..starred(_s('favorita'), true);
    expect(session.anchors().first.$1.id, 'favorita');
    expect(session.anchors().first.$2, closeTo(SmartWeights.star, 0.001));
    session.starred(_s('favorita'), false);
    expect(session.anchors().map((a) => a.$1.id), ['boa']);
  });

  test('a regra de artista da rádio vale aqui, e vinheta e mix de uma hora não entram', () async {
    final seed = _s('semente');
    final fake = _Fake(neighbors: {
      'semente': [
        _s('a1', artist: 'Mesmo'),
        _s('a2', artist: 'Mesmo'),
        _s('vinheta', duration: const Duration(seconds: 40)),
        _s('mix', duration: const Duration(minutes: 58)),
        ..._many('n', 8),
      ],
    });
    final session = SmartSession(seed: seed, explore: SmartExplore.low, random: Random(5));
    final r = await session.next(want: 6, history: [seed], source: fake);
    final ids = r.map((s) => s.id).toList();
    expect(ids, isNot(contains('vinheta')));
    expect(ids, isNot(contains('mix')));
    for (var i = 1; i < r.length; i++) {
      final antes = r.sublist(max(0, i - RadioSession.artistGap), i).expand(RadioSession.artistKeys).toSet();
      expect(RadioSession.artistKeys(r[i]).intersection(antes), isEmpty, reason: '$ids');
    }
  });

  test('guardada com a fila e aberta de novo: lembra o que aprendeu', () async {
    final session = SmartSession(seed: _s('semente'))
      ..left(_s('semente'), 1)
      ..left(_s('boa'), 1)
      ..left(_s('pulada'), -1)
      ..left(_s('neutra'), 0);
    final volta = SmartSession.fromJson(jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>);
    expect(volta.played, session.played);
    expect(volta.anchors().map((a) => (a.$1.id, a.$2.toStringAsFixed(3))),
        session.anchors().map((a) => (a.$1.id, a.$2.toStringAsFixed(3))));
    expect(volta.avoided().map((s) => s.id), ['pulada']);
    final fake = _Fake(samples: [_s('pulada'), ..._many('x', 5)]);
    final r = await volta.next(want: 3, history: const [], source: fake);
    expect(r.map((s) => s.id), isNot(contains('pulada')), reason: 'pulada não volta na sessão');
  });
}
