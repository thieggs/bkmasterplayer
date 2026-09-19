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

  static final _keys = StreamController<int>.broadcast();

  /// Avisos de "o volume mudou", de 0 a 1.
  static Stream<double> get changes => _changes.stream;

  /// Botão de volume apertado: +1 subiu, -1 desceu. Só chega quando o app
  /// pediu para ficar com eles ([grabKeys]).
  static Stream<int> get keys => _keys.stream;

  /// Chamado pelo tratador do canal (que é único por canal, e mora no app).
  static void onNative(MethodCall call) {
    if (call.method == 'mediaVolume' && call.arguments is num) {
      _changes.add((call.arguments as num).toDouble().clamp(0.0, 1.0));
    } else if (call.method == 'volumeKey') {
      _keys.add(call.arguments == 'up' ? 1 : -1);
    }
  }

  /// Pede (ou devolve) os botões físicos de volume.
  static Future<void> grabKeys(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('grabVolumeKeys', on);
    } catch (e) {
      debugPrint('volume: não deu para pegar os botões: $e');
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

/// Estado dos comandos.
class CommandsState {
  const CommandsState({this.volumeRule = false, this.volumeKeys = false, this.nudge});

  /// A regra "volume no mínimo pausa" está de pé.
  final bool volumeRule;

  /// Os botões de volume estão indo para o aparelho controlado.
  final bool volumeKeys;

  /// Última mexida no volume pelos botões, para a tela avisar por um
  /// instante. O contador faz o mesmo valor repetido ainda contar como
  /// mexida nova (apertar no máximo várias vezes, por exemplo).
  final ({double volume, String device, int seq})? nudge;

  CommandsState copyWith({bool? volumeRule, bool? volumeKeys, ({double volume, String device, int seq})? nudge}) =>
      CommandsState(volumeRule: volumeRule ?? this.volumeRule, volumeKeys: volumeKeys ?? this.volumeKeys, nudge: nudge ?? this.nudge);
}

/// Quanto cada toque no botão mexe: um passo dos quinze que o Android usa no
/// volume de mídia, para o toque parecer o de sempre.
const volumeStep = 1 / 15;

/// Comandos automáticos: "quando acontecer isto, faça aquilo".
///
/// Só pausa e volta a tocar o que ele mesmo pausou. Se a pessoa pausou à mão
/// e depois mexeu no volume, o app não sai tocando sozinho — a regra nunca
/// manda tocar algo que não foi ela que parou.
class CommandsNotifier extends Notifier<CommandsState> {
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<int>? _keysSub;
  int _seq = 0;
  ProviderSubscription<double>? _appVolumeSub;

  /// Foi esta regra que pausou? Só então ela pode voltar a tocar.
  bool _pausedByVolume = false;

  @override
  CommandsState build() {
    final rule = ref.watch(settingsProvider.select((s) => s.pauseOnVolumeZero));
    // Controlando outro aparelho: os botões de volume vão para lá.
    final remote = ref.watch(playerProvider.select((p) => p.remoteDevice));
    ref.onDispose(_stop);
    _stop();
    if (!rule) _pausedByVolume = false;

    if (rule) {
      if (Platform.isAndroid) {
        unawaited(DeviceVolume.watch(true));
        _volumeSub = DeviceVolume.changes.listen(_onVolume);
      } else {
        // No PC a regra segue o volume do próprio app.
        _appVolumeSub = ref.listen<double>(settingsProvider.select((s) => s.volume), (_, v) => _onVolume(v));
      }
    }
    if (remote != null) {
      unawaited(DeviceVolume.grabKeys(true));
      _keysSub = DeviceVolume.keys.listen((dir) => _onVolumeKey(dir, remote));
    }
    return CommandsState(volumeRule: rule, volumeKeys: remote != null);
  }

  /// Botão de volume do celular enquanto se controla outro aparelho: mexe no
  /// volume de lá. O [setVolume] do player já sabe encaminhar.
  void _onVolumeKey(int dir, String device) {
    final player = ref.read(playerProvider.notifier);
    final v = (ref.read(playerProvider).volume + dir * volumeStep).clamp(0.0, 1.0);
    player.setVolume(v);
    state = state.copyWith(nudge: (volume: v, device: device, seq: ++_seq));
  }

  void _stop() {
    _volumeSub?.cancel();
    _volumeSub = null;
    _keysSub?.cancel();
    _keysSub = null;
    _appVolumeSub?.close();
    _appVolumeSub = null;
    unawaited(DeviceVolume.watch(false));
    unawaited(DeviceVolume.grabKeys(false));
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

final commandsProvider = NotifierProvider<CommandsNotifier, CommandsState>(CommandsNotifier.new);
