import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/player/sleep_timer.dart';

class _FakePlayer implements SleepTarget {
  @override
  bool playing = true;
  @override
  String? currentUid = 'a';
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(seconds: 200);
  final fades = <double>[];
  int pauses = 0, rewinds = 0;
  @override
  void fade(double factor) => fades.add(factor);
  @override
  void pause() {
    pauses++;
    playing = false;
  }

  @override
  void rewind() => rewinds++;
}

void main() {
  late _FakePlayer player;
  late ProviderContainer c;
  late SleepTimerNotifier timer;
  final t0 = DateTime(2026, 9, 15, 23);

  setUp(() {
    player = _FakePlayer();
    c = ProviderContainer(overrides: [sleepTargetProvider.overrideWithValue(player)]);
    timer = c.read(sleepTimerProvider.notifier);
  });
  tearDown(() => c.dispose());

  test('depois de N minutos: abaixa o volume nos últimos 20 s e pausa', () {
    timer.start(const Duration(minutes: 10), now: t0);
    timer.tick(now: t0.add(const Duration(minutes: 5)));
    expect(player.fades, isEmpty, reason: 'longe do fim, volume normal');
    timer.tick(now: t0.add(const Duration(minutes: 9, seconds: 50)));
    expect(player.fades.last, closeTo(0.5, 0.01));
    expect(player.pauses, 0);
    timer.tick(now: t0.add(const Duration(minutes: 10)));
    expect(player.pauses, 1);
    expect(player.fades.last, 1.0, reason: 'o volume volta ao normal para a próxima vez');
    expect(c.read(sleepTimerProvider).active, isFalse);
    expect(c.read(sleepTimerProvider).finished, 1);
  });

  test('no fim da música: pausa antes da próxima começar', () {
    timer.startEndOfTrack();
    player.position = const Duration(seconds: 150);
    timer.tick();
    expect(player.fades, isEmpty);
    player.position = const Duration(seconds: 196);
    timer.tick();
    expect(player.fades.last, closeTo(0.5, 0.01));
    player.position = const Duration(milliseconds: 199800);
    timer.tick();
    expect(player.pauses, 1);
    expect(player.rewinds, 0);
  });

  test('se a transição já trocou de música, pausa e deixa a nova no começo', () {
    timer.startEndOfTrack();
    player.position = const Duration(seconds: 197);
    timer.tick();
    player.currentUid = 'b';
    player.position = const Duration(seconds: 2);
    timer.tick();
    expect(player.rewinds, 1);
    expect(player.pauses, 1);
    expect(c.read(sleepTimerProvider).active, isFalse);
  });

  test('desligar no meio da descida devolve o volume; mais 10 min soma', () {
    timer.start(const Duration(minutes: 1), now: t0);
    timer.tick(now: t0.add(const Duration(seconds: 50)));
    expect(player.fades.last, lessThan(1));
    timer.cancel();
    expect(player.fades.last, 1.0);
    expect(c.read(sleepTimerProvider).active, isFalse);

    timer.start(const Duration(minutes: 5), now: t0);
    timer.extend(const Duration(minutes: 10), now: t0);
    expect(timer.remaining(now: t0), const Duration(minutes: 15));
  });

  test('com a música já pausada, o timer só se desliga', () {
    player.playing = false;
    timer.start(const Duration(minutes: 1), now: t0);
    timer.tick(now: t0.add(const Duration(minutes: 1)));
    expect(player.pauses, 0);
    expect(player.fades, isEmpty);
    expect(c.read(sleepTimerProvider).active, isFalse);
  });
}
