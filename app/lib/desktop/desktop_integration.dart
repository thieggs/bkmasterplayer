import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/providers.dart';
import '../player/player_controller.dart';
import '../src/rust/api/engine.dart' as engine;

/// Mini player: janela pequena, sempre no topo.
class MiniMode extends Notifier<bool> {
  Rect? _saved;

  @override
  bool build() => false;

  Future<void> enter() async {
    if (state) return;
    _saved = await windowManager.getBounds();
    state = true;
    await windowManager.setMinimumSize(const Size(300, 96));
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setSize(const Size(400, 112));
    await windowManager.setAlwaysOnTop(true);
  }

  Future<void> exit() async {
    if (!state) return;
    state = false;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(const Size(420, 560));
    final b = _saved;
    if (b != null) {
      await windowManager.setBounds(b);
    } else {
      await windowManager.setSize(const Size(1280, 800));
    }
  }

  Future<void> toggle() => state ? exit() : enter();
}

final miniModeProvider = NotifierProvider<MiniMode, bool>(MiniMode.new);

/// Bandeja do sistema + comportamento de fechar a janela.
class DesktopIntegration with TrayListener, WindowListener {
  DesktopIntegration(this.container);

  final ProviderContainer container;
  bool _trayReady = false;
  Timer? _menuTimer;
  String? _lastMenuKey;

  static bool get supported => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  Future<void> init() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    await _setupTray();
    container.listen(playerProvider.select((s) => (s.current?.uid, s.playing)), (_, _) => _scheduleMenu());
    container.listen(settingsProvider.select((s) => s.trayIcon), (_, on) => on ? _setupTray() : _removeTray());
  }

  Future<void> _setupTray() async {
    if (_trayReady || !container.read(settingsProvider).trayIcon) return;
    try {
      trayManager.addListener(this);
      await trayManager.setIcon(Platform.isWindows ? 'assets/icon/tray.ico' : 'assets/icon/tray.png');
      _trayReady = true;
      await _updateMenu();
    } catch (e) {
      debugPrint('bandeja indisponível: $e');
    }
  }

  Future<void> _removeTray() async {
    if (!_trayReady) return;
    _trayReady = false;
    trayManager.removeListener(this);
    await trayManager.destroy();
  }

  void _scheduleMenu() {
    _menuTimer?.cancel();
    _menuTimer = Timer(const Duration(milliseconds: 300), _updateMenu);
  }

  Future<void> _updateMenu() async {
    if (!_trayReady) return;
    final s = container.read(playerProvider);
    final song = s.current?.song;
    final pt = Platform.localeName.startsWith('pt');
    final key = '${song?.id}|${s.playing}';
    if (key == _lastMenuKey) return;
    _lastMenuKey = key;
    final title = song == null ? (pt ? 'Nada tocando' : 'Nothing playing') : '${song.title} — ${song.displayArtist}';
    if (!Platform.isLinux) {
      // No Linux (AppIndicator) não existe tooltip; o título vai no menu.
      try {
        await trayManager.setToolTip(title);
      } catch (_) {}
    }
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'now', label: title.length > 60 ? '${title.substring(0, 57)}…' : title, disabled: true),
      MenuItem.separator(),
      MenuItem(key: 'toggle', label: s.playing ? (pt ? 'Pausar' : 'Pause') : (pt ? 'Tocar' : 'Play')),
      MenuItem(key: 'previous', label: pt ? 'Anterior' : 'Previous'),
      MenuItem(key: 'next', label: pt ? 'Próxima' : 'Next'),
      MenuItem.separator(),
      MenuItem(key: 'show', label: pt ? 'Mostrar janela' : 'Show window'),
      MenuItem(key: 'mini', label: pt ? 'Mini player' : 'Mini player'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: pt ? 'Sair' : 'Quit'),
    ]));
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    engine.playerStop();
    await _removeTray();
    exit(0);
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final p = container.read(playerProvider.notifier);
    switch (menuItem.key) {
      case 'toggle':
        p.toggle();
      case 'previous':
        p.previous();
      case 'next':
        p.next();
      case 'show':
        showWindow();
      case 'mini':
        showWindow();
        container.read(miniModeProvider.notifier).enter();
      case 'quit':
        quit();
    }
  }

  @override
  void onWindowClose() {
    final s = container.read(settingsProvider);
    if (s.closeToTray && _trayReady) {
      windowManager.hide();
    } else {
      quit();
    }
  }
}
