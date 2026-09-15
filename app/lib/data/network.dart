import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../src/rust/api/engine.dart' as engine;
import 'settings.dart';

/// Conexão cobrada por uso: dados móveis sem Wi-Fi nem cabo.
bool isMetered(List<ConnectivityResult> r) =>
    r.contains(ConnectivityResult.mobile) && !r.contains(ConnectivityResult.wifi) && !r.contains(ConnectivityResult.ethernet);

/// Está nos dados móveis agora? (sem informação da rede: não)
class MeteredNotifier extends Notifier<bool> {
  @override
  bool build() {
    final c = Connectivity();
    final sub = c.onConnectivityChanged.listen((r) => state = isMetered(r), onError: (_) {});
    ref.onDispose(sub.cancel);
    c.checkConnectivity().then((r) => state = isMetered(r), onError: (_) {});
    return false;
  }
}

final meteredProvider = NotifierProvider<MeteredNotifier, bool>(MeteredNotifier.new);

/// Qualidade do streaming agora (kbps; 0 = original): a dos dados móveis,
/// se escolhida e se está neles; senão a do Wi-Fi.
int streamBitRate(AppSettings s, {required bool metered}) =>
    metered && s.mobileMaxBitRate > 0 && (s.maxBitRate == 0 || s.mobileMaxBitRate < s.maxBitRate) ? s.mobileMaxBitRate : s.maxBitRate;

/// Pausa da fila de downloads: a da pessoa (botão) ou "esperando o Wi-Fi".
class OfflineGateState {
  const OfflineGateState({this.userPaused = false, this.waitingWifi = false});
  final bool userPaused;
  final bool waitingWifi;
  bool get paused => userPaused || waitingWifi;
}

class OfflineGateNotifier extends Notifier<OfflineGateState> {
  @override
  OfflineGateState build() {
    final wifiOnly = ref.watch(settingsProvider.select((s) => s.downloadWifiOnly));
    final metered = ref.watch(meteredProvider);
    final prev = stateOrNull;
    final next = OfflineGateState(userPaused: prev?.userPaused ?? false, waitingWifi: wifiOnly && metered);
    _apply(next);
    return next;
  }

  void setUserPaused(bool paused) {
    state = OfflineGateState(userPaused: paused, waitingWifi: state.waitingWifi);
    _apply(state);
  }

  void _apply(OfflineGateState s) {
    try {
      unawaited(engine.playerOfflineSetPaused(paused: s.paused));
    } catch (_) {
      // Motor ainda não iniciou (testes).
    }
  }
}

final offlineGateProvider = NotifierProvider<OfflineGateNotifier, OfflineGateState>(OfflineGateNotifier.new);
