import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/settings.dart';

import 'package:player_musica/player/commands.dart';

/// Roda a regra de verdade (a mesma que o app usa), guardando o estado de
/// "fui eu que pausei" como o app guarda.
class _Regra {
  bool pausedByRule = false;
  final List<String> feito = [];

  void volume(double v, {required bool playing}) {
    switch (volumeAction(volume: v, playing: playing, pausedByRule: pausedByRule)) {
      case VolumeAction.pause:
        pausedByRule = true;
        feito.add('pause');
      case VolumeAction.play:
        pausedByRule = false;
        feito.add('play');
      case VolumeAction.nothing:
        if (v > 0) pausedByRule = false;
    }
  }
}

void main() {
  group('volume no mínimo pausa', () {
    test('zerou pausa, subiu volta', () {
      final r = _Regra();
      r.volume(0, playing: true);
      expect(r.feito, ['pause']);
      r.volume(0.3, playing: false);
      expect(r.feito, ['pause', 'play']);
    });

    test('não volta a tocar o que a pessoa pausou à mão', () {
      final r = _Regra();
      // Pausado pela pessoa: a regra não viu nada.
      r.volume(0.5, playing: false);
      r.volume(0, playing: false);
      r.volume(0.8, playing: false);
      expect(r.feito, isEmpty, reason: 'não pode sair tocando sozinho');
    });

    test('zerar de novo depois de já ter pausado não repete o comando', () {
      final r = _Regra();
      r.volume(0, playing: true);
      r.volume(0, playing: false);
      expect(r.feito, ['pause']);
    });

    test('pessoa despausou à mão com o volume no zero: a regra esquece', () {
      final r = _Regra();
      r.volume(0, playing: true);
      // Ela voltou a tocar sozinha (mudo, mas tocando) e o volume subiu.
      r.volume(0.4, playing: true);
      expect(r.feito, ['pause'], reason: 'já estava tocando, nada a fazer');
      expect(r.pausedByRule, isFalse);
    });
  });

  group('configurações novas', () {
    test('o padrão é o seguro: não fecha sozinho e não pausa sem pedir', () {
      const d = AppSettings();
      expect(d.pauseOnVolumeZero, isFalse, reason: 'regra nova entra desligada');
      expect(d.pauseOnUnplug, isTrue, reason: 'tirar o fone sempre pausou');
      expect(d.keepAliveWhenPaused, isTrue, reason: 'o app não deve morrer pausado');
    });

    test('vão e voltam do disco', () {
      const a = AppSettings(pauseOnVolumeZero: true, pauseOnUnplug: false, keepAliveWhenPaused: false);
      final b = AppSettings.fromJson(a.toJson());
      expect(b.pauseOnVolumeZero, isTrue);
      expect(b.pauseOnUnplug, isFalse);
      expect(b.keepAliveWhenPaused, isFalse);
    });
  });

  group('botões de volume no aparelho controlado', () {
    /// O passo tem que fechar os 15 toques do volume de mídia do Android, e
    /// nem estourar nem faltar nas pontas.
    test('quinze toques vão de zero a cheio, e param nas pontas', () {
      var v = 0.0;
      for (var i = 0; i < 15; i++) {
        v = (v + volumeStep).clamp(0.0, 1.0);
      }
      expect(v, closeTo(1.0, 1e-9));
      expect((v + volumeStep).clamp(0.0, 1.0), 1.0, reason: 'não passa de cheio');
      var z = 0.0;
      expect((z - volumeStep).clamp(0.0, 1.0), 0.0, reason: 'não fica negativo');
      z = volumeStep;
      expect((z - volumeStep).clamp(0.0, 1.0), closeTo(0.0, 1e-9));
    });

    test('o aviso conta cada toque, mesmo parado no máximo', () {
      const a = CommandsState();
      final b = a.copyWith(nudge: (volume: 1.0, device: 'Cozinha', seq: 1));
      final c = b.copyWith(nudge: (volume: 1.0, device: 'Cozinha', seq: 2));
      expect(b.nudge, isNot(c.nudge), reason: 'senão a tela não mostraria de novo');
      expect(c.nudge?.device, 'Cozinha');
    });
  });
}
