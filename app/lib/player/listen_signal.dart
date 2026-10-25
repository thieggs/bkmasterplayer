/// O que o aleatório smart entende de cada música que sai de cena.
///
/// A regra veio do usuário (24/10/2026): ouviu a música inteira, gostou;
/// começou e já pulou, não gostou — inclusive antes de três segundos; ouviu
/// um pedaço e enjoou no meio, não diz nada. A pesquisa da Spotify sobre
/// pulos chega no mesmo: pular depois de ouvir boa parte não é sinal de que a
/// pessoa não gosta. Ver `smart_session.dart`.
library;

/// Como a música saiu de cena.
enum TrackExit {
  /// Acabou sozinha, ou o AutoMix (ou o crossfade) começou a passar para a
  /// próxima — com o AutoMix a música nunca "termina" de verdade.
  ended,

  /// "Próxima" apertado: na tela, na notificação, no fone, no carro ou pelo
  /// Connect.
  skipped,

  /// Tocou noutra música da fila no meio desta.
  jumped,

  /// Fila trocada, parada, erro, voltar para a anterior: ninguém estava
  /// julgando a música.
  interrupted,
}

/// Réguas do aleatório smart.
abstract final class Listen {
  /// Pular antes disto de tempo ouvido é "não gostei". Trinta segundos é a
  /// régua comum do mercado para contar que alguém ouviu uma música.
  static const quick = Duration(seconds: 30);

  /// Música mais curta que isto: a régua de [quick] vira proporção
  /// ([quickShare]), senão quase a música inteira contaria como pulo rápido.
  static const shortSong = Duration(seconds: 75);
  static const quickShare = 0.4;

  /// Pular faltando isto conta como ouvir inteira: o fade-out, o fim falado.
  static const tail = Duration(seconds: 30);

  /// Para valer como "ouviu inteira", pelo menos esta parte tem de ter sido
  /// ouvida de verdade: arrastar até o fim não conta.
  static const heardShare = 0.6;

  /// Pausada por mais que isto, a pessoa saiu e voltou: pular depois disso é
  /// trocar de assunto, não julgar a música.
  static const longPause = Duration(minutes: 30);
}

/// +1 gostou (ouviu inteira), -1 não gostou (pulou rápido), 0 nada a dizer.
///
/// - [heard]: tempo ouvido de verdade, sem contar os pulos dentro da música;
/// - [position]: onde estava quando saiu; [duration]: o tamanho dela;
/// - [fromMiddle]: começou do meio (a fila voltou ao abrir o app, ou veio de
///   outro aparelho), então o começo não foi ouvido aqui;
/// - [pausedLong]: ficou pausada mais que [Listen.longPause].
int listenSignal({
  required TrackExit exit,
  required Duration heard,
  required Duration position,
  required Duration duration,
  bool fromMiddle = false,
  bool pausedLong = false,
}) {
  if (exit == TrackExit.interrupted) return 0;
  final known = duration > Duration.zero;
  final heardEnough = !known || heard.inMilliseconds >= duration.inMilliseconds * Listen.heardShare;
  if (exit == TrackExit.ended) return heardEnough ? 1 : 0;

  // Pulou: na reta final é como ter ouvido inteira.
  if (known && duration - position <= Listen.tail) return heardEnough ? 1 : 0;
  if (fromMiddle || pausedLong) return 0;
  final quick = known && duration < Listen.shortSong
      ? heard.inMilliseconds < duration.inMilliseconds * Listen.quickShare
      : heard < Listen.quick;
  return quick ? -1 : 0;
}
