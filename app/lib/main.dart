import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/diagnostics.dart';
import 'core/providers.dart';
import 'data/network.dart';
import 'data/settings.dart';
import 'desktop/desktop_integration.dart';
import 'jam/jam_core.dart';
import 'jam/jam_nearby.dart';
import 'mobile/media_session.dart';
import 'player/automix.dart';
import 'src/rust/api/engine.dart' as engine;
import 'src/rust/frb_generated.dart';
import 'ui/startup_error.dart';

const appId = 'player_musica';
const appName = 'BKmasterplayer 🎵';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Registro para o relatório de diagnóstico (Ajustes → Sobre), desde já.
  AppLog.instance.installHandlers();
  // Licenças das fontes dos temas (aparecem em Ajustes → Sobre → Licenças).
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Nunito', 'nunito'),
      ('Space Grotesk', 'spacegrotesk'),
      ('JetBrains Mono', 'jetbrainsmono'),
      ('Playfair Display', 'playfairdisplay'),
      ('Bebas Neue', 'bebasneue'),
    ]) {
      yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString('assets/fonts/OFL-$file.txt'));
    }
    // Pacotes do motor em Rust e bibliotecas do Android (os pacotes Dart o Flutter já lista).
    for (final asset in const ['assets/licenses/rust.json', 'assets/licenses/android.json']) {
      for (final e in jsonDecode(await rootBundle.loadString(asset)) as List) {
        yield LicenseEntryWithLineBreaks(List<String>.from(e['packages'] as List), e['text'] as String);
      }
    }
  });
  final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(420, 560),
      center: true,
      title: appName,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await RustLib.init();
  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings.load(prefs);
  final cacheDir = await getApplicationCacheDirectory();
  final supportDir = await getApplicationSupportDirectory();
  await AppLog.instance.init(supportDir);
  AppLog.instance.add('info', 'início: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  await Directory('${cacheDir.path}/ui_covers').create(recursive: true);
  // Músicas recebidas numa Festa que já acabou (o app foi fechado): apaga.
  unawaited(clearJamFiles(cacheDir.path));
  Directory? modelDir;
  try {
    modelDir = await prepareModels();
  } catch (e) {
    debugPrint('modelos de análise indisponíveis: $e');
  }

  // No Android o cache de áudio (com os downloads offline) fica na pasta de
  // dados do app: a pasta de cache o sistema esvazia quando falta espaço.
  final audioCacheDir = Platform.isAndroid ? '${supportDir.path}/audio_cache' : cacheDir.path;

  try {
    await engine.playerInit(
      config: engine.PlayerConfig(
        cacheDir: audioCacheDir,
        cacheLimitMb: settings.cacheLimitMb,
        deviceId: settings.outputDeviceId,
        appId: appId,
        appName: appName,
        mediaControls: isDesktop,
        modelDir: modelDir?.path,
        analysisModel: 'small',
      ),
    );
    await applyAutomix(settings);
    applyEq(settings);
    await engine.playerOfflineSetParallel(parallel: settings.downloadParallel);
    engine.playerSetNotifications(enabled: settings.notifications && isDesktop);
  } catch (e, st) {
    // Sem motor não há o que tocar: mostra o motivo (e o relatório) em vez de
    // deixar a abertura parada para sempre.
    AppLog.instance.add('erro', 'motor de áudio não iniciou: $e\n${shortStack(st)}');
    runApp(StartupErrorApp(error: e));
    return;
  }

  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs),
    cacheDirProvider.overrideWithValue(cacheDir),
    supportDirProvider.overrideWithValue(supportDir),
  ]);
  // Downloads: pausa da pessoa e "só no Wi-Fi" valem desde a abertura.
  container.read(offlineGateProvider);
  if (isDesktop) {
    // Bandeja e fechar janela (fechar encerra na hora ou esconde na bandeja;
    // o desligamento padrão do Flutter no Linux às vezes aborta no OpenGL).
    await DesktopIntegration(container).init();
  }
  if (Platform.isAndroid) {
    try {
      await initMobileMedia(container);
    } catch (e) {
      debugPrint('serviço de mídia indisponível: $e');
    }
    // Jam por Bluetooth/Wi-Fi Direct e o aviso de Jam por perto.
    final nearby = await NearbyJam.create();
    if (nearby != null) {
      jamNearby = nearby;
      jamShowRequest = NearbyJam.showRequest;
      jamHideRequest = NearbyJam.hideRequest;
      if (settings.jamNearbyAlerts) NearbyJam.setBeaconScan(true);
    }
  }
  runApp(UncontrolledProviderScope(container: container, child: const PlayerApp()));
}
