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

  await engine.playerInit(
    config: engine.PlayerConfig(
      cacheDir: cacheDir.path,
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
  runApp(UncontrolledProviderScope(container: container, child: const PlayerApp()));
}
