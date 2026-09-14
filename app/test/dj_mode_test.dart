import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/player/dj_mode.dart';

void main() {
  test('andamento: próximo, meio/dobro do tempo e distante', () {
    expect(tempoFit(124, 125), 1.0);
    expect(tempoFit(87, 174), 1.0); // dobro
    expect(tempoFit(128, 135), 0.85); // 5,5%
    expect(tempoFit(128, 136), 0.65); // 6,25%
    expect(tempoFit(100, 140), 0.1);
    expect(tempoFit(null, 120), 0.5);
  });

  test('tom pela roda Camelot', () {
    expect(keyFit('8A', '8A'), 1.0);
    expect(keyFit('8A', '9A'), 0.85);
    expect(keyFit('12A', '1A'), 0.85); // a roda dá a volta
    expect(keyFit('8A', '8B'), 0.8); // relativo maior/menor
    expect(keyFit('8A', '3B'), 0.2);
    expect(keyFit(null, '8A'), 0.5);
  });

  test('a melhor encaixada ganha de uma um pouco mais parecida que não encaixa', () {
    final encaixa = djScore(similarity: 0.80, tempo: 1.0, key: 1.0);
    final destoa = djScore(similarity: 0.90, tempo: 0.1, key: 0.2);
    final mesmoArtista = djScore(similarity: 0.95, tempo: 1.0, key: 1.0, sameArtist: true);
    expect(encaixa, greaterThan(destoa));
    expect(encaixa, greaterThan(mesmoArtista));
  });
}
