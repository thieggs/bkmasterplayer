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

  test('a curva do deslize sai de 0 e chega em 1, e cada forma tem seu jeito', () {
    for (final curva in UiPrefs.glideCurves) {
      expect(vinylGlideCurve(curva, 0), 0, reason: curva);
      expect(vinylGlideCurve(curva, 1), 1, reason: curva);
      // Nunca volta atrás: a velocidade só caminha para a normal.
      var antes = 0.0;
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final agora = vinylGlideCurve(curva, t);
        expect(agora, greaterThanOrEqualTo(antes - 1e-9), reason: '$curva em $t');
        antes = agora;
      }
      // Fora da faixa fica preso nas pontas (o deslize acabou).
      expect(vinylGlideCurve(curva, 2), 1, reason: curva);
      expect(vinylGlideCurve(curva, -1), 0, reason: curva);
    }
    // No meio do caminho: o vinil já andou mais da metade (freou forte no
    // começo) e o freio no fim ainda andou pouco.
    expect(vinylGlideCurve('vinyl', 0.5), greaterThan(0.5));
    expect(vinylGlideCurve('linear', 0.5), 0.5);
    expect(vinylGlideCurve('brake', 0.5), lessThan(0.5));
  });

  test('o tempo do deslize vem da força do arremesso, não do relógio', () {
    const rolamento = 0.6; // o ajuste: quanto desliza um arremesso forte (4x)
    final forte = vinylGlideSpan(rolamento, 4);
    final metade = vinylGlideSpan(rolamento, 2.5);
    final leve = vinylGlideSpan(rolamento, 1.1);
    // O ajuste é medido justo no arremesso de 4x.
    expect(forte, closeTo(rolamento, 1e-9));
    // Metade da velocidade, metade do tempo: a desaceleração é a mesma.
    expect(metade, closeTo(forte / 2, 1e-9));
    // Um empurrãozinho para quase na hora.
    expect(leve, lessThan(forte / 10));
    // Solto na velocidade normal não desliza nada.
    expect(vinylGlideSpan(rolamento, 1), 0);
    // Para trás vale o mesmo, pela distância até a velocidade normal.
    expect(vinylGlideSpan(rolamento, -2), closeTo(vinylGlideSpan(rolamento, 4), 1e-9));
    // Rolamento em zero: para na hora, por mais forte que seja o giro.
    expect(vinylGlideSpan(0, 4), 0);
  });

  test('deslize de fábrica é curto, e zero quer dizer parar na hora', () {
    expect(UiPrefs.defaultVinylGlide, 0.6);
    expect(const UiPrefs().vinylGlideCurve, 'linear');
    expect(UiPrefs.fromJson({'vinylGlide': 9}).vinylGlide, UiPrefs.maxVinylGlide);
    expect(UiPrefs.fromJson({'vinylGlide': -1}).vinylGlide, 0);
    expect(UiPrefs.fromJson({'vinylGlide': 'muito'}).vinylGlide, UiPrefs.defaultVinylGlide);
    expect(UiPrefs.fromJson({'vinylGlideCurve': 'foguete'}).vinylGlideCurve, 'linear');
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
