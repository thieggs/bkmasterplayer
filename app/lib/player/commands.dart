import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'player_controller.dart';

/// Volume de mídia do aparelho (os botões do lado do celular).
///
/// O Flutter não enxerga isso sozinho: quem avisa é o lado Android (ver
/// `MainActivity.kt`). No PC não existe equivalente simples, e lá a regra usa
/// o volume do próprio app.
class DeviceVolume {
  DeviceVolume._();

  static const _channel = MethodChannel('bkplayer/system');
  static final _changes = StreamController<double>.broadcast();

  /// Avisos de "o volume mudou", de 0 a 1.
  static Stream<double> get changes => _changes.stream;

  /// Chamado pelo tratador do canal (que é único por canal, e mora no app).
  static void onNative(MethodCall call) {
    if (call.method == 'mediaVolume' && call.arguments is num) {
      _changes.add((call.arguments as num).toDouble().clamp(0.0, 1.0));
    }
  }

  static Future<void> watch(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('watchVolume', on);
    } catch (e) {
      debugPrint('volume: não deu para vigiar: $e');
    }
  }

  static Future<double?> read() async {
    if (!Platform.isAndroid) return null;
    try {
      return (await _channel.invokeMethod<double>('mediaVolume'))?.clamp(0.0, 1.0);
    } catch (e) {
      return null;
    }
  }
}

/// O que a regra do volume manda fazer.
enum VolumeAction { nothing, pause, play }

/// Decide o que fazer quando o volume muda.
///
/// Fica fora da classe de propósito: assim dá para testar a decisão sem
/// motor, sem player e sem Riverpod. [pausedByRule] é o que impede o app de
/// sair tocando o que a pessoa pausou à mão.
VolumeAction volumeAction({required double volume, required bool playing, required bool pausedByRule}) {
  if (volume <= 0) return playing ? VolumeAction.pause : VolumeAction.nothing;
  if (pausedByRule && !playing) return VolumeAction.play;
  return VolumeAction.nothing;
}

/// Comandos automáticos: "quando acontecer isto, faça aquilo".
///
/// Só pausa e volta a tocar o que ele mesmo pausou. Se a pessoa pausou à mão
/// e depois mexeu no volume, o app não sai tocando sozinho — a regra nunca
/// manda tocar algo que não foi ela que parou.
class CommandsNotifier extends Notifier<bool> {
  StreamSubscription<double>? _volumeSub;
  ProviderSubscription<double>? _appVolumeSub;

  /// Foi esta regra que pausou? Só então ela pode voltar a tocar.
  bool _pausedByVolume = false;

  @override
  bool build() {
    final on = ref.watch(settingsProvider.select((s) => s.pauseOnVolumeZero));
    ref.onDispose(_stop);
    if (!on) {
      _stop();
      _pausedByVolume = false;
      return false;
    }
    if (Platform.isAndroid) {
      unawaited(DeviceVolume.watch(true));
      _volumeSub = DeviceVolume.changes.listen(_onVolume);
    } else {
      // No PC a regra segue o volume do próprio app.
      _appVolumeSub = ref.listen<double>(
        settingsProvider.select((s) => s.volume),
        (_, v) => _onVolume(v),
      );
    }
    return true;
  }

  void _stop() {
    _volumeSub?.cancel();
    _volumeSub = null;
    _appVolumeSub?.close();
    _appVolumeSub = null;
    unawaited(DeviceVolume.watch(false));
  }

  void _onVolume(double v) {
    final player = ref.read(playerProvider.notifier);
    final playing = ref.read(playerProvider).playing;
    switch (volumeAction(volume: v, playing: playing, pausedByRule: _pausedByVolume)) {
      case VolumeAction.pause:
        _pausedByVolume = true;
        player.pause();
      case VolumeAction.play:
        _pausedByVolume = false;
        player.play();
      case VolumeAction.nothing:
        // Voltou a tocar por outro caminho: a regra solta o que segurava.
        if (v > 0) _pausedByVolume = false;
    }
  }
}

final commandsProvider = NotifierProvider<CommandsNotifier, bool>(CommandsNotifier.new);
