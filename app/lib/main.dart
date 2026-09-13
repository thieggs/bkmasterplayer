import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/settings.dart';
import 'src/rust/api/engine.dart' as engine;
import 'src/rust/frb_generated.dart';

const appId = 'player_musica';
const appName = 'Player de Música';

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
  await Directory('${cacheDir.path}/ui_covers').create(recursive: true);

  await engine.playerInit(
    config: engine.PlayerConfig(
      cacheDir: cacheDir.path,
      cacheLimitMb: settings.cacheLimitMb,
      deviceId: settings.outputDeviceId,
      appId: appId,
      appName: appName,
      mediaControls: isDesktop,
    ),
  );
  engine.playerSetNotifications(enabled: settings.notifications && isDesktop);

  runApp(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      cacheDirProvider.overrideWithValue(cacheDir),
    ],
    child: const PlayerApp(),
  ));
}
