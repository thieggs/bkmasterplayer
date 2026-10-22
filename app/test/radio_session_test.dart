import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/player/radio.dart';

/// A rádio: semente fixa com vizinhança, sem repetir artista, sem mix de uma
/// hora, e sem parar quando a semente é desconhecida. Ver `player/radio.dart`.

Song _s(String id, String artist, {String? title, Duration? duration}) =>
    Song(id: id, title: title ?? id, artist: artist, duration: duration ?? const Duration(minutes: 3));

/// "Servidor" de mentira: para cada semente, uma lista fixa (com notas), e
/// anota quem foi perguntado e até que fundo.
class _Fake {
  _Fake(this.lists);
  final Map<String, List<Song>> lists;
  final asked = <(String, int)>[];

  Future<List<(Song, double)>> call(Song seed, int count) async {
    asked.add((seed.id, count));
    final l = lists[seed.id] ?? const [];
    return [for (final (i, s) in l.take(count).indexed) (s, 1 - i / 100)];
  }
}

void main() {
  test('não repete artista colado, nem quando ele vem em parceria', () async {
    final seed = _s('semente', 'Semente');
    final fake = _Fake({
      'semente': [
        _s('a1', 'Mandragora'),
        _s('a2', 'Mandragora • L3AF'),
        _s('b1', 'Outro'),
        _s('c1', 'Terceiro'),
        _s('d1', 'Quarto'),
        _s('e1', 'Quinto'),
        _s('f1', 'Sexto'),
        _s('a3', 'Mandragora'),
      ],
    });
    final r = await RadioSession(seed).next(want: 6, history: [seed], fetch: fake.call);
    final ids = r.map((s) => s.id).toList();
    expect(ids.take(2), ['a1', 'b1'], reason: '"Mandragora • L3AF" é Mandragora: espera a vez');
    for (var i = 1; i < r.length; i++) {
      final antes = r.skip(i < 5 ? 0 : i - 5).take(i < 5 ? i : 5).map(RadioSession.artistKeys).expand((e) => e).toSet();
      expect(RadioSession.artistKeys(r[i]).intersection(antes), isEmpty, reason: '${r[i].artist} em $ids');
    }
  });

  test('mix de uma hora não entra (a não ser que a semente também seja)', () async {
    final longa = _s('mix', 'DJ', duration: const Duration(minutes: 58));
    final lists = {
      'semente': [longa, _s('b', 'B'), _s('c', 'C')],
      'longa': [longa, _s('b', 'B'), _s('c', 'C')],
    };
    final curta = await RadioSession(_s('semente', 'S')).next(want: 3, history: const [], fetch: _Fake(lists).call);
    expect(curta.map((s) => s.id), isNot(contains('mix')));
    final seedLonga = _s('longa', 'S', duration: const Duration(minutes: 40));
    final r = await RadioSession(seedLonga).next(want: 3, history: const [], fetch: _Fake(lists).call);
    expect(r.map((s) => s.id), contains('mix'), reason: 'quem começou num mix quer mix');
  });

  test('a mesma gravação noutro álbum (ou a versão trocada) não volta', () async {
    final seed = _s('semente', 'S');
    final fake = _Fake({
      'semente': [
        _s('x-single', 'Banda', title: 'Canção'),
        _s('x-album', 'Banda', title: 'Canção!'),
        _s('y', 'Outra'),
      ],
    });
    final r = await RadioSession(seed).next(want: 3, history: [seed], fetch: fake.call);
    expect(r.map((s) => s.id), ['x-single', 'y']);
  });

  test('semente desconhecida: a música anterior faz o papel dela', () async {
    final antes = _s('antes', 'A');
    final seed = _s('nova', 'N'); // recém-trocada, o AudioMuse ainda não conhece
    final fake = _Fake({
      'antes': [_s('p1', 'P1'), _s('p2', 'P2')],
    });
    final r = await RadioSession(seed).next(want: 2, history: [antes, seed], fetch: fake.call);
    expect(r.map((s) => s.id), ['p1', 'p2']);
  });

  test('a semente fica fixa: a segunda leva não parte da última música', () async {
    final seed = _s('semente', 'S');
    final lista = [for (var i = 0; i < 60; i++) _s('m$i', 'Artista $i')];
    final fake = _Fake({'semente': lista});
    final radio = RadioSession(seed);
    final hist = [seed];
    hist.addAll(await radio.next(want: 10, history: hist, fetch: fake.call));
    hist.addAll(await radio.next(want: 10, history: hist, fetch: fake.call));
    // Só a semente e a vizinhança dela (as primeiras da lista) são perguntadas,
    // nunca a décima música que entrou.
    final perguntadas = fake.asked.map((a) => a.$1).toSet();
    expect(perguntadas.difference({'semente', 'm0', 'm1', 'm2', 'm3'}), isEmpty, reason: '$perguntadas');
    expect(hist.length, 21);
    expect(hist.map((s) => s.id).toSet().length, 21, reason: 'sem repetir');
  });

  test('só sobrou artista repetido: entra assim mesmo (rádio não para)', () async {
    final seed = _s('semente', 'Racionais');
    final fake = _Fake({
      'semente': [for (var i = 0; i < 5; i++) _s('r$i', "Racionais MC's")],
    });
    final r = await RadioSession(seed).next(want: 3, history: [seed], fetch: fake.call);
    expect(r.length, 3);
  });

  test('semente desconhecida e fila vazia: o último recurso vira ponte', () async {
    final seed = _s('nova', 'N');
    final fake = _Fake({
      'g2': [_s('p1', 'P1'), _s('p2', 'P2'), _s('p3', 'P3')],
    });
    final radio = RadioSession(seed);
    final hist = [seed];
    // O "similar" genérico devolve duas; a segunda o AudioMuse conhece.
    hist.addAll(await radio.next(
        want: 5, history: hist, fetch: fake.call, fallback: () async => [_s('g1', 'G1'), _s('g2', 'G2')]));
    expect(hist.map((s) => s.id), ['nova', 'g1', 'g2']);
    hist.addAll(await radio.next(want: 3, history: hist, fetch: fake.call, fallback: () async => const []));
    expect(hist.skip(3).map((s) => s.id), ['p1', 'p2', 'p3'], reason: 'a próxima leva já sai pela análise');
  });

  test('nada responde: usa o último recurso', () async {
    final r = await RadioSession(_s('semente', 'S')).next(
      want: 2,
      history: const [],
      fetch: _Fake(const {}).call,
      fallback: () async => [_s('aleatoria', 'Z')],
    );
    expect(r.map((s) => s.id), ['aleatoria']);
  });

  group('artista repetido: escolha da pessoa (a música nunca repete)', () {
    final seed = _s('semente', 'Peso Pluma');
    List<Song> lista() => [
          _s('a1', 'Peso Pluma • Natanael Cano'),
          _s('a2', 'Peso Pluma'),
          _s('b1', 'Fuerza Regida'),
          _s('a3', 'Peso Pluma • Junior H'),
          _s('a1', 'Peso Pluma • Natanael Cano'), // a mesma de novo
        ];

    test('à vontade: o artista repete, até seguido', () async {
      final r = await RadioSession(seed, artists: RadioArtists.free)
          .next(want: 4, history: [seed], fetch: _Fake({'semente': lista()}).call);
      expect(r.map((s) => s.id), ['a1', 'a2', 'b1', 'a3'], reason: 'a1 não volta: música nunca repete');
    });

    test('só não colar: nunca dois seguidos do mesmo artista', () async {
      // Com alternativas suficientes (sem elas, repete — rádio não para).
      final r = await RadioSession(seed, artists: RadioArtists.spread).next(
          want: 5, history: [seed], fetch: _Fake({'semente': [...lista(), _s('c1', 'Junior H'), _s('d1', 'Grupo Frontera')]}).call);
      final ids = r.map((s) => s.id).toList();
      expect(ids.first, 'b1', reason: 'a semente é Peso Pluma: a primeira não pode ser dele');
      expect(r.where((s) => RadioSession.artistKeys(s).contains('pesopluma')).length, greaterThan(1),
          reason: 'pode repetir o artista, só não colado: $ids');
      for (var i = 1; i < r.length; i++) {
        expect(RadioSession.artistKeys(r[i]).intersection(RadioSession.artistKeys(r[i - 1])), isEmpty, reason: '$ids');
      }
    });

    test('trocar a regra vale na hora, na mesma rádio', () async {
      final radio = RadioSession(seed);
      radio.artists = RadioArtists.free;
      final r = await radio.next(want: 2, history: [seed], fetch: _Fake({'semente': lista()}).call);
      expect(r.map((s) => s.id), ['a1', 'a2']);
    });

    test('o ajuste guardado volta igual e o padrão é variar', () {
      expect(RadioArtists.parse(null), RadioArtists.vary);
      for (final v in RadioArtists.values) {
        expect(RadioArtists.parse(v.id), v);
      }
    });
  });

  test('créditos separados do jeito que o servidor escreve', () {
    expect(RadioSession.artistKeys(_s('x', 'BaianaSystem • Seu Jorge • Antonio Carlos & Jocafi')),
        {'baianasystem', 'seujorge', 'antoniocarlos', 'jocafi'});
    expect(RadioSession.artistKeys(_s('x', 'Calvin Harris feat. Ellie Goulding')), {'calvinharris', 'elliegoulding'});
    expect(RadioSession.artistKeys(const Song(id: 'x', title: 'x', artists: [ArtistRef(id: '1', name: 'Djavan')])), {'djavan'});
  });
}
