import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_controller.dart';

/// Timer para dormir: pausa depois de N minutos ou no fim da música atual,
/// abaixando o volume aos poucos antes (sem tranco no silêncio). O volume
/// salvo não muda: quem voltar a tocar ouve no volume de sempre.
class SleepTimerState {
  const SleepTimerState({this.until, this.endOfTrackUid, this.finished = 0});

  /// Hora de pausar (modo minutos).
  final DateTime? until;

  /// Pausa quando esta música (uid da fila) acabar.
  final String? endOfTrackUid;

  /// Quantas vezes o timer já pausou a música (a interface avisa quando sobe).
  final int finished;

  bool get active => until != null || endOfTrackUid != null;
  bool get endOfTrack => endOfTrackUid != null;
}

/// O que o timer controla (o player de verdade, ou um falso nos testes).
abstract class SleepTarget {
  bool get playing;
  String? get currentUid;
  Duration get position;
  Duration get duration;

  /// Volume relativo ao salvo (1 = normal, 0 = mudo), sem gravar.
  void fade(double factor);
  void pause();

  /// A música que começou depois do fim marcado volta para o começo.
  void rewind();
}

class _PlayerTarget implements SleepTarget {
  _PlayerTarget(this.ref);
  final Ref ref;
  PlayerState get _s => ref.read(playerProvider);
  @override
  bool get playing => _s.playing;
  @override
  String? get currentUid => _s.current?.uid;
  @override
  Duration get position => _s.position;
  @override
  Duration get duration => _s.duration;
  @override
  void fade(double factor) => ref.read(playerProvider.notifier).fadeVolume(factor);
  @override
  void pause() => ref.read(playerProvider.notifier).pause();
  @override
  void rewind() => ref.read(playerProvider.notifier).seek(Duration.zero);
}

final sleepTargetProvider = Provider<SleepTarget>((ref) => _PlayerTarget(ref));

/// Últimos segundos em que o volume desce até zero.
const sleepFade = Duration(seconds: 20);
const _endOfTrackFade = Duration(seconds: 8);

class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _timer;
  double _factor = 1;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SleepTimerState();
  }

  SleepTarget get _target => ref.read(sleepTargetProvider);

  void start(Duration d, {DateTime? now}) {
    _begin(SleepTimerState(until: (now ?? DateTime.now()).add(d)));
  }

  void startEndOfTrack() {
    final uid = _target.currentUid;
    if (uid == null) return;
    _begin(SleepTimerState(endOfTrackUid: uid));
  }

  /// Mais tempo (modo minutos; no fim da música vira "daqui a N minutos").
  void extend(Duration d, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final base = state.until != null && state.until!.isAfter(t) ? state.until! : t;
    _begin(SleepTimerState(until: base.add(d)));
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _restore();
    state = SleepTimerState(finished: state.finished);
  }

  /// Quanto falta (null = desligado ou esperando o fim de uma música sem duração).
  Duration? remaining({DateTime? now}) {
    if (state.until != null) {
      final r = state.until!.difference(now ?? DateTime.now());
      return r.isNegative ? Duration.zero : r;
    }
    if (state.endOfTrack) {
      final t = _target;
      if (t.currentUid != state.endOfTrackUid || t.duration <= Duration.zero) return null;
      final r = t.duration - t.position;
      return r.isNegative ? Duration.zero : r;
    }
    return null;
  }

  void _begin(SleepTimerState s) {
    _restore();
    state = SleepTimerState(until: s.until, endOfTrackUid: s.endOfTrackUid, finished: state.finished);
    _timer?.cancel();
    // Quatro vezes por segundo: o fim da música precisa de precisão.
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
  }

  /// Um passo do timer (público para os testes chamarem com o relógio deles).
  void tick({DateTime? now}) {
    if (!state.active) return;
    final t = _target;
    if (state.endOfTrack && t.currentUid != state.endOfTrackUid) {
      // A música marcada acabou (ou uma transição já começou a próxima): o
      // volume já estava no zero; pausa e deixa a próxima no começo.
      if (t.currentUid != null) t.rewind();
      _finish();
      return;
    }
    final left = remaining(now: now);
    if (left == null) return;
    final window = state.endOfTrack ? _endOfTrackFade : sleepFade;
    if (left <= const Duration(milliseconds: 300)) {
      _finish();
      return;
    }
    final f = left >= window ? 1.0 : left.inMilliseconds / window.inMilliseconds;
    if ((f - _factor).abs() > 0.01 || (f == 1.0 && _factor != 1.0)) {
      _factor = f;
      if (t.playing) t.fade(f);
    }
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    final t = _target;
    if (t.playing) t.pause();
    _restore();
    state = SleepTimerState(finished: state.finished + 1);
  }

  void _restore() {
    if (_factor != 1.0) {
      _factor = 1.0;
      _target.fade(1.0);
    }
  }
}

final sleepTimerProvider = NotifierProvider<SleepTimerNotifier, SleepTimerState>(SleepTimerNotifier.new);
