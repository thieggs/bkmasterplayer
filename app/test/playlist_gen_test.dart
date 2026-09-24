import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/playlist_gen.dart';
import 'package:player_musica/domain/models.dart';

Song m(String id, {int? ano, String? genero, bool favorita = false, int min = 4}) => Song(
      id: id,
      title: id,
      year: ano,
      genre: genero,
      duration: Duration(minutes: min),
      starred: favorita ? DateTime(2026) : null,
    );

void main() {
  group('o que serve para a playlist', () {
    test('a época corta quem está fora', () {
      const c = GenCriteria(fromYear: 2010, toYear: 2019);
      expect(serve(m('a', ano: 2015), c), isTrue);
      expect(serve(m('b', ano: 2005), c), isFalse);
      expect(serve(m('c', ano: 2020), c), isFalse);
      // Sem ano não dá para afirmar que é da época: fica de fora.
      expect(serve(m('d'), c), isFalse);
    });

    test('só favoritas', () {
      const c = GenCriteria(onlyStarred: true);
      expect(serve(m('a', favorita: true), c), isTrue);
      expect(serve(m('b'), c), isFalse);
    });

    test('gênero não diferencia maiúscula', () {
      const c = GenCriteria(genre: 'Psytrance');
      expect(serve(m('a', genero: 'psytrance'), c), isTrue);
      expect(serve(m('b', genero: 'rock'), c), isFalse);
    });

    test('sem critério, tudo serve', () {
      expect(serve(m('a'), const GenCriteria()), isTrue);
    });
  });

  group('montar a playlist', () {
    test('por tempo, para ao encher', () {
      final r = montaPlaylist([for (var i = 0; i < 50; i++) m('s$i', min: 5)],
          const GenCriteria(minutes: 30, byMinutes: true));
      expect(r.length, 6); // 6 x 5 min = 30
    });

    test('por número, para na conta', () {
      final r = montaPlaylist([for (var i = 0; i < 50; i++) m('s$i')],
          const GenCriteria(count: 7, byMinutes: false));
      expect(r.length, 7);
    });

    test('a semente abre e não se repete', () {
      final semente = m('semente');
      final r = montaPlaylist([m('a'), semente, m('b')],
          GenCriteria(seed: semente, count: 5, byMinutes: false));
      expect(r.first.id, 'semente');
      expect(r.where((s) => s.id == 'semente').length, 1);
    });

    test('não repete música', () {
      final r = montaPlaylist([m('a'), m('a'), m('b')], const GenCriteria(count: 9, byMinutes: false));
      expect(r.map((s) => s.id), ['a', 'b']);
    });

    test('a semente também obedece aos filtros', () {
      final semente = m('velha', ano: 1990);
      final r = montaPlaylist([m('nova', ano: 2015)],
          GenCriteria(seed: semente, fromYear: 2010, count: 5, byMinutes: false));
      expect(r.map((s) => s.id), ['nova']);
    });

    test('mantém a ordem que veio (a parecença do AudioMuse)', () {
      final r = montaPlaylist([m('c'), m('a'), m('b')], const GenCriteria(count: 3, byMinutes: false));
      expect(r.map((s) => s.id), ['c', 'a', 'b']);
    });
  });
}
