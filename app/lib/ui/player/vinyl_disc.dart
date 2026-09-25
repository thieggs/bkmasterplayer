import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../widgets/cover_art.dart';

/// Para onde o disco está sendo girado agora (null = ninguém girando). A barra
/// de progresso segue isto, para o tempo dela bater com o do disco.
class VinylScrubNotifier extends Notifier<Duration?> {
  @override
  Duration? build() => null;

  void set(Duration? at) => state = at;
}

final vinylScrubProvider = NotifierProvider<VinylScrubNotifier, Duration?>(VinylScrubNotifier.new);

/// Uma volta do disco = a duração dividida por isto, com piso e teto: nem
/// lento demais numa faixa curta nem grosso demais numa longa.
///
/// Com o som ligado a volta vale bem menos música, senão quase todo giro
/// passaria de [vinylMaxSpeed] e ficaria mudo: o tom só quer dizer alguma
/// coisa em giro devagar.
const _turnsPerSong = 6;
const _minSecondsPerTurn = 10.0;
const _maxSecondsPerTurn = 60.0;
const _turnsPerSongAudio = 12;
const _minSecondsPerTurnAudio = 5.0;
const _maxSecondsPerTurnAudio = 24.0;

/// Quanto o volume cai ao pegar o disco (e volta ao soltar): o "freio" do
/// vinil, para quando o som da agulha está desligado.
const _brakeDuration = Duration(milliseconds: 220);

/// Acima disto o motor emudece a agulha (não é mais som de disco, é chiado).
/// Tem que bater com `VINYL_MAX_SPEED` do mixer.
@visibleForTesting
const vinylMaxSpeed = 4.0;

/// Dedo parado por mais do que isto: o disco está sendo segurado, não girado.
const _stillAfter = Duration(milliseconds: 40);

/// Quanto de música anda em uma volta do disco.
@visibleForTesting
double vinylSecondsPerTurn(Duration total, {bool audio = false}) {
  if (total <= Duration.zero) return audio ? 12 : 30;
  final turns = audio ? _turnsPerSongAudio : _turnsPerSong;
  final min = audio ? _minSecondsPerTurnAudio : _minSecondsPerTurn;
  final max = audio ? _maxSecondsPerTurnAudio : _maxSecondsPerTurn;
  return (total.inSeconds / turns).clamp(min, max);
}

/// Onde [turns] voltas a partir de [from] deixam a música, e quantas voltas
/// isso valeu de verdade: nas pontas o disco trava, como o fim do sulco, e
/// girar mais não conta (senão o caminho de volta ficaria torto).
@visibleForTesting
({Duration at, double turns}) vinylSeek({
  required Duration from,
  required Duration total,
  required double turns,
  required double secondsPerTurn,
}) {
  double turnsTo(Duration at) => (at - from).inMilliseconds / (secondsPerTurn * 1000);
  final wanted = from + Duration(milliseconds: (turns * secondsPerTurn * 1000).round());
  if (wanted < Duration.zero) return (at: Duration.zero, turns: turnsTo(Duration.zero));
  if (total > Duration.zero && wanted > total) return (at: total, turns: turnsTo(total));
  return (at: wanted, turns: turns);
}

/// A capa como um disco de vinil, girando enquanto a música toca.
///
/// Com [scratch], o disco também é o controle: gire com o dedo para adiantar e
/// voltar a música. Como num vinil de verdade, ele para debaixo do dedo e volta
/// a tocar de onde a agulha ficou ao soltar.
///
/// Com [audio], a velocidade do dedo vira a velocidade da agulha no motor: o
/// som acompanha o giro, com o tom subindo e descendo, e toca de trás para
/// frente quando se gira ao contrário. Sem ele, a música só emudece enquanto
/// você procura o ponto.
class VinylDisc extends ConsumerStatefulWidget {
  const VinylDisc({super.key, required this.size, required this.song, required this.scratch, this.audio = false});

  final double size;
  final Song? song;
  final bool scratch;
  final bool audio;

  @override
  ConsumerState<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends ConsumerState<VinylDisc> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  /// 1 = volume normal, 0 = mudo (a rampa ao pegar e soltar o disco).
  late final AnimationController _brake = AnimationController(vsync: this, value: 1, duration: _brakeDuration);

  /// Voltas dadas com o dedo (somadas às do giro automático).
  double _turns = 0;
  double _turnsAtGrab = 0;
  double? _lastAngle;

  bool _dragging = false;
  bool _wasPlaying = false;
  Duration _from = Duration.zero;
  Duration _to = Duration.zero;

  /// A agulha está no motor (o som segue o giro) em vez de a música pausar.
  bool _needle = false;

  /// Velocidade da agulha, suavizada: o dedo treme e o motor estala.
  double _speed = 0;
  final _clock = Stopwatch();
  Duration _movedAt = Duration.zero;
  Duration _measuredAt = Duration.zero;
  Duration _measuredTo = Duration.zero;

  /// Manda a velocidade para o motor de tempos em tempos (e deixa o disco
  /// parar sozinho quando o dedo para, sem esperar o próximo movimento).
  Ticker? _pump;

  @override
  void initState() {
    super.initState();
    _brake.addListener(_applyBrake);
    _brake.addStatusListener(_onBrake);
  }

  /// Som da agulha: só com a opção ligada, tocando e no som daqui (num
  /// aparelho remoto quem toca é o outro).
  bool get _audible => widget.audio && _wasPlaying && !ref.read(playerProvider.notifier).isRemote;

  @override
  void dispose() {
    _brake.removeListener(_applyBrake);
    // Saiu da tela com o disco na mão: solta tudo o que ficou preso nele.
    if (_dragging) {
      final p = ref.read(playerProvider.notifier);
      if (_needle) p.vinyl(null);
      p.fadeVolume(1);
      ref.read(vinylScrubProvider.notifier).set(null);
    }
    _pump?.dispose();
    _spin.dispose();
    _brake.dispose();
    super.dispose();
  }

  /// A cada quadro: manda a velocidade atual para a agulha. Sem movimento novo,
  /// o disco vai parando na mão, como um de verdade.
  void _pumpNeedle(Duration _) {
    if (!_needle) return;
    if (_clock.elapsed - _movedAt > _stillAfter) _speed *= 0.5;
    ref.read(playerProvider.notifier).vinyl(_speed.clamp(-vinylMaxSpeed, vinylMaxSpeed));
  }

  void _applyBrake() => ref.read(playerProvider.notifier).fadeVolume(_brake.value);

  void _onBrake(AnimationStatus s) {
    // Chegou no mudo com o dedo ainda no disco: pausa de verdade.
    if (s == AnimationStatus.dismissed && _dragging && _wasPlaying) {
      ref.read(playerProvider.notifier).pause();
    }
  }

  double _angleAt(Offset local) {
    final c = widget.size / 2;
    return math.atan2(local.dy - c, local.dx - c);
  }

  void _onStart(DragStartDetails d) {
    final p = ref.read(playerProvider);
    if (p.current == null) return;
    _dragging = true;
    _wasPlaying = p.playing;
    _from = p.position;
    _to = p.position;
    _turnsAtGrab = _turns;
    _lastAngle = _angleAt(d.localPosition);
    _spin.stop();
    ref.read(vinylScrubProvider.notifier).set(_to);
    _needle = _audible;
    if (_needle) {
      // O motor assume o disco: a agulha começa parada (o dedo ainda não
      // girou), e essa descida de 1 para 0 já é o freio do vinil.
      _speed = 0;
      _clock
        ..reset()
        ..start();
      _movedAt = Duration.zero;
      _measuredAt = Duration.zero;
      _measuredTo = _to;
      ref.read(playerProvider.notifier).vinyl(0);
      (_pump ??= createTicker(_pumpNeedle)).start();
    } else if (_wasPlaying) {
      _brake.reverse();
    }
    setState(() {});
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final a = _angleAt(d.localPosition);
    final last = _lastAngle;
    _lastAngle = a;
    if (last == null) return;
    var step = a - last;
    // Menor caminho: passar pelo topo do disco não pode valer uma volta.
    if (step > math.pi) step -= 2 * math.pi;
    if (step < -math.pi) step += 2 * math.pi;

    final total = ref.read(playerProvider).duration;
    final turned = vinylSeek(
      from: _from,
      total: total,
      turns: _turns + step / (2 * math.pi) - _turnsAtGrab,
      secondsPerTurn: vinylSecondsPerTurn(total, audio: _needle),
    );
    _to = turned.at;
    _turns = _turnsAtGrab + turned.turns;
    ref.read(vinylScrubProvider.notifier).set(_to);
    if (_needle) _measure();
    setState(() {});
  }

  /// Velocidade da agulha = quanta música andou por segundo de relógio. É a
  /// derivada do que o dedo fez, suavizada: sem isso cada tranco do dedo vira
  /// um salto de tom.
  void _measure() {
    final now = _clock.elapsed;
    final dt = (now - _measuredAt).inMicroseconds / 1e6;
    if (dt <= 0) return;
    final moved = (_to - _measuredTo).inMicroseconds / 1e6;
    _speed = _speed * 0.55 + (moved / dt) * 0.45;
    _measuredAt = now;
    _measuredTo = _to;
    _movedAt = now;
  }

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    _lastAngle = null;
    final p = ref.read(playerProvider.notifier);
    // O seek já devolve o disco ao motor (troca o deck); soltar depois é só
    // garantia, para o caso de a faixa ter acabado no meio do giro.
    p.seek(_to);
    if (_needle) {
      _pump?.stop();
      _clock.stop();
      p.vinyl(null);
      _needle = false;
    }
    if (_wasPlaying) p.play();
    _brake.forward();
    ref.read(vinylScrubProvider.notifier).set(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final playing = ref.watch(playerProvider.select((s) => s.playing));
    // Gira só enquanto toca e ninguém está segurando.
    if (playing && !_dragging && !_spin.isAnimating) {
      _spin.repeat();
    } else if ((!playing || _dragging) && _spin.isAnimating) {
      _spin.stop();
    }

    final disc = AnimatedBuilder(
      animation: _spin,
      builder: (context, child) => Transform.rotate(angle: (_spin.value + _turns) * 2 * math.pi, child: child),
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.06),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(blurRadius: 24, color: Colors.black54)],
          gradient: RadialGradient(
            colors: [Colors.grey.shade900, Colors.black, Colors.grey.shade900, Colors.black],
            stops: const [0.3, 0.55, 0.8, 1],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: CustomPaint(painter: const _Grooves())),
            CoverArt(coverArtId: widget.song?.coverArt, size: size * 0.88, radius: size),
            Container(
              width: size * 0.05,
              height: size * 0.05,
              decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );

    final hero = Hero(tag: 'now-cover', child: disc);
    if (!widget.scratch) return hero;

    return Semantics(
      label: context.l10n.vinylScratch,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RawGestureDetector(
            gestures: {
              _DiscPan: GestureRecognizerFactoryWithHandlers<_DiscPan>(
                _DiscPan.new,
                (r) => r
                  ..onStart = _onStart
                  ..onUpdate = _onUpdate
                  ..onEnd = _onEnd,
              ),
            },
            child: hero,
          ),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(alignment: const Alignment(0, 0.62), child: _ScrubLabel(from: _from, to: _to)),
              ),
            ),
        ],
      ),
    );
  }
}

/// O tempo para onde o disco está sendo girado, e o quanto andou.
class _ScrubLabel extends StatelessWidget {
  const _ScrubLabel({required this.from, required this.to});

  final Duration from;
  final Duration to;

  @override
  Widget build(BuildContext context) {
    final delta = to - from;
    final sign = delta.isNegative ? '−' : '+';
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${formatDuration(to)}   $sign${formatDuration(delta.abs())}',
        style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// Os sulcos do disco: círculos finos e um risco de brilho, para o giro
/// aparecer mesmo quando a capa é escura.
class _Grooves extends CustomPainter {
  const _Grooves();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.05);
    for (var i = 0; i < 18; i++) {
      canvas.drawCircle(c, r * (0.50 + i * 0.028), ring);
    }
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.02
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.96), -0.25, 0.5, false, shine);
  }

  @override
  bool shouldRepaint(_Grooves oldDelegate) => false;
}

/// Ganha a disputa do PageView e da rolagem: arrasto em cima do disco é do
/// disco. Declara vitória antes deles (metade da folga de toque).
class _DiscPan extends PanGestureRecognizer {
  Offset? _down;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _down = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _down;
    if (event is PointerMoveEvent && down != null && (event.position - down).distance > kTouchSlop / 2) {
      resolve(GestureDisposition.accepted);
    }
    super.handleEvent(event);
  }
}
