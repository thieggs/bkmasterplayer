import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/ui_prefs.dart';
import 'package:player_musica/ui/player/vinyl_disc.dart';

void main() {
  test('o padrão é a volta de um LP, e girar nesse ritmo cabe no limite', () {
    // 33⅓ RPM dá 1,8 s por volta: é o que um disco de verdade anda.
    expect(UiPrefs.defaultVinylSecondsPerTurn, closeTo(60 / (100 / 3), 0.01));
    // Girando uma volta por segundo, a agulha vai a 1,8x — dentro do limite
    // de fábrica, então o som sai em vez de a agulha levantar.
    expect(UiPrefs.defaultVinylSecondsPerTurn, lessThan(UiPrefs.defaultVinylMaxSpeed));
    // E mesmo no teto do ajuste ainda cabe.
    expect(UiPrefs.maxVinylSecondsPerTurn, lessThanOrEqualTo(UiPrefs.defaultVinylMaxSpeed));
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
