import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/data/network.dart';
import 'package:player_musica/data/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Metered extends MeteredNotifier {
  _Metered(this.on);
  final bool on;
  @override
  bool build() => on;
}

void main() {
  test('dados móveis: só quando não há Wi-Fi nem cabo', () {
    expect(isMetered([ConnectivityResult.mobile]), isTrue);
    expect(isMetered([ConnectivityResult.mobile, ConnectivityResult.wifi]), isFalse);
    expect(isMetered([ConnectivityResult.ethernet]), isFalse);
    expect(isMetered([ConnectivityResult.none]), isFalse);
  });

  test('qualidade nos dados móveis nunca sobe a do Wi-Fi', () {
    const s = AppSettings(maxBitRate: 320, mobileMaxBitRate: 128);
    expect(streamBitRate(s, metered: false), 320);
    expect(streamBitRate(s, metered: true), 128);
    expect(streamBitRate(const AppSettings(mobileMaxBitRate: 128), metered: true), 128, reason: 'original no Wi-Fi, 128 nos dados');
    expect(streamBitRate(const AppSettings(maxBitRate: 192, mobileMaxBitRate: 0), metered: true), 192, reason: '"a mesma do Wi-Fi"');
    expect(streamBitRate(const AppSettings(), metered: true), 320, reason: 'biblioteca em FLAC: nos dados, MP3 320 de fábrica');
    expect(streamBitRate(const AppSettings(maxBitRate: 128, mobileMaxBitRate: 256), metered: true), 128);
  });

  test('qualidade Opus salva por versões antigas vira MP3 (o motor não toca Opus)', () {
    final s = AppSettings.fromJson({'transcodeFormat': 'opus', 'maxBitRate': 192});
    expect(s.transcodeFormat, 'mp3');
    expect(s.maxBitRate, 192);
    expect(AppSettings.fromJson({}).transcodeFormat, isNull);
    final back = AppSettings.fromJson(const AppSettings(mobileMaxBitRate: 96, downloadWifiOnly: true).toJson());
    expect((back.mobileMaxBitRate, back.downloadWifiOnly), (96, true));
  });

  test('ajuste antigo com "a mesma do Wi-Fi" passa uma vez para 320 nos dados móveis', () {
    expect(AppSettings.fromJson({'mobileMaxBitRate': 0}).mobileMaxBitRate, 320);
    expect(AppSettings.fromJson({'mobileMaxBitRate': 128}).mobileMaxBitRate, 128, reason: 'escolha da pessoa fica');
    // Salvo pela versão nova: "a mesma do Wi-Fi" foi escolhido de propósito.
    final novo = AppSettings.fromJson(const AppSettings(mobileMaxBitRate: 0).toJson());
    expect(novo.mobileMaxBitRate, 0);
  });

  test('qualidade dos downloads é salva (0 = original)', () {
    expect(const AppSettings().downloadMaxBitRate, 0);
    expect(AppSettings.fromJson(const AppSettings(downloadMaxBitRate: 320).toJson()).downloadMaxBitRate, 320);
  });

  test('downloads esperam o Wi-Fi só com a opção ligada e nos dados móveis', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer make(bool metered) =>
        ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs), meteredProvider.overrideWith(() => _Metered(metered))]);
    final c = make(true);
    addTearDown(c.dispose);
    expect(c.read(offlineGateProvider).paused, isFalse, reason: 'opção desligada');
    c.read(settingsProvider.notifier).update((s) => s.copyWith(downloadWifiOnly: true));
    expect(c.read(offlineGateProvider).waitingWifi, isTrue);
    c.read(offlineGateProvider.notifier).setUserPaused(true);
    expect(c.read(offlineGateProvider).userPaused, isTrue);
    final wifi = make(false);
    addTearDown(wifi.dispose);
    expect(wifi.read(offlineGateProvider).paused, isFalse, reason: 'no Wi-Fi, baixa');
  });
}
