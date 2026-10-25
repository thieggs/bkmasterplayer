import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/player/listen_signal.dart';

/// A régua do aleatório smart para cada música que sai de cena. Ver
/// `player/listen_signal.dart`.
void main() {
  const musica = Duration(minutes: 3, seconds: 30);

  int sinal(TrackExit exit, {required int ouviu, int? pos, Duration duration = musica, bool meio = false, bool pausa = false}) =>
      listenSignal(
        exit: exit,
        heard: Duration(seconds: ouviu),
        position: Duration(seconds: pos ?? ouviu),
        duration: duration,
        fromMiddle: meio,
        pausedLong: pausa,
      );

  test('ouviu inteira: gostou', () {
    expect(sinal(TrackExit.ended, ouviu: 210), 1);
    expect(sinal(TrackExit.ended, ouviu: 180), 1, reason: 'o AutoMix começou a passar para a próxima antes do fim');
    expect(sinal(TrackExit.skipped, ouviu: 190), 1, reason: 'pulou o fade-out');
  });

  test('pulou rápido: não gostou, inclusive antes de 3 segundos', () {
    expect(sinal(TrackExit.skipped, ouviu: 12), -1);
    expect(sinal(TrackExit.skipped, ouviu: 1), -1, reason: 'pedido do usuário: antes de 3 s também vale -1');
    expect(sinal(TrackExit.skipped, ouviu: 0), -1);
    expect(sinal(TrackExit.jumped, ouviu: 20), -1, reason: 'foi para outra da fila logo no começo desta');
  });

  test('enjoou no meio: não diz nada', () {
    expect(sinal(TrackExit.skipped, ouviu: 31), 0);
    expect(sinal(TrackExit.skipped, ouviu: 100), 0);
  });

  test('arrastar até o fim não é ouvir inteira', () {
    expect(sinal(TrackExit.ended, ouviu: 20, pos: 210), 0);
    expect(sinal(TrackExit.skipped, ouviu: 20, pos: 195), 0);
  });

  test('música curta: a régua vira proporção', () {
    const curta = Duration(seconds: 50);
    expect(sinal(TrackExit.skipped, ouviu: 15, duration: curta), -1);
    expect(sinal(TrackExit.skipped, ouviu: 25, duration: curta), 0);
    expect(sinal(TrackExit.skipped, ouviu: 45, duration: curta), 1);
  });

  test('ninguém estava julgando a música: nada', () {
    expect(sinal(TrackExit.interrupted, ouviu: 5), 0, reason: 'fila trocada, parada, erro');
    expect(sinal(TrackExit.interrupted, ouviu: 210), 0);
    expect(sinal(TrackExit.skipped, ouviu: 5, meio: true), 0, reason: 'a fila voltou ao abrir o app, no meio da música');
    expect(sinal(TrackExit.skipped, ouviu: 5, pausa: true), 0, reason: 'ficou pausada meia hora e a pessoa voltou');
  });

  test('sem saber o tamanho, vale só o tempo', () {
    expect(sinal(TrackExit.ended, ouviu: 200, duration: Duration.zero), 1);
    expect(sinal(TrackExit.skipped, ouviu: 5, duration: Duration.zero), -1);
    expect(sinal(TrackExit.skipped, ouviu: 50, duration: Duration.zero), 0);
  });
}
