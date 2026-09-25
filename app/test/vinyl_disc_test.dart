import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/ui/player/vinyl_disc.dart';

void main() {
  test('uma volta anda a música inteira em ~6 voltas, com piso e teto', () {
    expect(vinylSecondsPerTurn(const Duration(minutes: 3)), 30);
    // Faixa curta: não desce dos 10 s por volta (senão vira um giro sem efeito).
    expect(vinylSecondsPerTurn(const Duration(seconds: 30)), 10);
    // Faixa longa (1 h): não passa de 60 s por volta (senão fica grosso demais).
    expect(vinylSecondsPerTurn(const Duration(hours: 1)), 60);
    // Sem duração conhecida ainda.
    expect(vinylSecondsPerTurn(Duration.zero), 30);
  });

  test('girar para frente e para trás anda a música na mesma medida', () {
    const from = Duration(minutes: 1);
    const total = Duration(minutes: 3);
    final ahead = vinylSeek(from: from, total: total, turns: 1, secondsPerTurn: 30);
    expect(ahead.at, const Duration(minutes: 1, seconds: 30));
    expect(ahead.turns, 1);
    final back = vinylSeek(from: from, total: total, turns: -0.5, secondsPerTurn: 30);
    expect(back.at, const Duration(seconds: 45));
  });

  test('nas pontas o disco trava e só conta o giro que coube', () {
    const total = Duration(minutes: 3);
    final start = vinylSeek(from: const Duration(seconds: 15), total: total, turns: -5, secondsPerTurn: 30);
    expect(start.at, Duration.zero);
    expect(start.turns, -0.5);
    final end = vinylSeek(from: const Duration(minutes: 2), total: total, turns: 5, secondsPerTurn: 30);
    expect(end.at, total);
    expect(end.turns, 2);
  });

  test('sem duração conhecida, girar para frente não trava', () {
    final r = vinylSeek(from: Duration.zero, total: Duration.zero, turns: 10, secondsPerTurn: 30);
    expect(r.at, const Duration(minutes: 5));
  });
}
