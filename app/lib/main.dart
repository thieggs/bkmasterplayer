import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/settings.dart';
import 'desktop/desktop_integration.dart';
import 'jam/jam_core.dart';
import 'jam/jam_nearby.dart';
import 'mobile/media_session.dart';
import 'player/automix.dart';
import 'src/rust/api/engine.dart' as engine;
import 'src/rust/frb_generated.dart';

const appId = 'player_musica';
const appName = 'BKplayer 🎵';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  await Directory('${cacheDir.path}/ui_covers').create(recursive: true);
  Directory? modelDir;
  try {
    modelDir = await prepareModels();
  } catch (e) {
    debugPrint('modelos de análise indisponíveis: $e');
  }

  // No Android o cache de áudio (com os downloads offline) fica na pasta de
  // dados do app: a pasta de cache o sistema esvazia quando falta espaço.
  final audioCacheDir = Platform.isAndroid ? '${supportDir.path}/audio_cache' : cacheDir.path;

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
  engine.playerSetNotifications(enabled: settings.notifications && isDesktop);

  final container = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs),
    cacheDirProvider.overrideWithValue(cacheDir),
    supportDirProvider.overrideWithValue(supportDir),
  ]);
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
