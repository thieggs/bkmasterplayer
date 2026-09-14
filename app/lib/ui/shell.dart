import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../desktop/desktop_integration.dart';
import '../jam/jam_page.dart';
import '../l10n/l10n.dart';
import '../player/player_controller.dart';
import 'actions.dart';
import 'player/player_bar.dart';
import 'player/queue_panel.dart';
import 'player/mini_window.dart';
import 'widgets/bk_logo.dart';

class _Dest {
  const _Dest(this.path, this.icon, this.selectedIcon, this.label);
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String Function(AppLocalizations) label;
}

final _dests = [
  _Dest('/', Icons.home_outlined, Icons.home, (l) => l.home),
  _Dest('/search', Icons.search, Icons.search, (l) => l.search),
  _Dest('/albums', Icons.album_outlined, Icons.album, (l) => l.albums),
  _Dest('/songs', Icons.music_note_outlined, Icons.music_note, (l) => l.songs),
  _Dest('/artists', Icons.person_outline, Icons.person, (l) => l.artists),
  _Dest('/playlists', Icons.queue_music_outlined, Icons.queue_music, (l) => l.playlists),
  _Dest('/genres', Icons.sell_outlined, Icons.sell, (l) => l.genres),
  _Dest('/favorites', Icons.favorite_border, Icons.favorite, (l) => l.favorites),
  _Dest('/offline', Icons.download_outlined, Icons.download_done, (l) => l.downloads),
];

/// Abas do celular (a navegação de baixo só comporta poucas).
final _mobileDests = [
  _Dest('/', Icons.home_outlined, Icons.home, (l) => l.home),
  _Dest('/search', Icons.search, Icons.search, (l) => l.search),
  _Dest('/library', Icons.library_music_outlined, Icons.library_music, (l) => l.library),
  _Dest('/settings', Icons.settings_outlined, Icons.settings, (l) => l.settings),
];

// Prefixos: '/album' cobre a lista (/albums) e o álbum aberto (/album/:id).
const _libraryPaths = ['/library', '/album', '/song', '/artist', '/playlist', '/genre', '/favorites', '/offline'];
const _settingsPaths = ['/settings', '/equalizer', '/customize'];

int _mobileSelected(String loc) {
  if (loc.startsWith('/search')) return 1;
  if (_settingsPaths.any(loc.startsWith)) return 3;
  if (loc != '/' && _libraryPaths.any(loc.startsWith)) return 2;
  return 0;
}

/// Para onde o "voltar" do Android leva numa aba sem histórico (null = sai do app).
String? _backTarget(String loc) {
  if (loc == '/') return null;
  if (loc != '/library' && _libraryPaths.any(loc.startsWith)) return '/library';
  if (loc != '/settings' && _settingsPaths.any(loc.startsWith)) return '/settings';
  return '/';
}

/// Layout principal: barra lateral + conteúdo + fila opcional + player embaixo.
/// Em telas estreitas (celular) vira navegação inferior + mini player.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late bool _queueOpen = ref.read(uiPrefsProvider).showQueue;

  int get _selected {
    final loc = widget.location;
    for (var i = _dests.length - 1; i >= 0; i--) {
      final p = _dests[i].path;
      if (p == '/' ? loc == '/' : loc.startsWith(p)) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = MediaQuery.sizeOf(context);
    final mobile = Platform.isAndroid || Platform.isIOS;
    // Tablet: layout de computador. Celular deitado: barra lateral compacta
    // com as abas do celular e o mini player (não cabe a barra do player).
    final tablet = mobile && size.shortestSide >= 600;
    final phoneLandscape = mobile && !tablet && size.width > size.height;
    final wide = mobile ? tablet : size.width >= 720;
    final sidebar = ref.watch(uiPrefsProvider.select((p) => p.sidebar));
    final veryWide = switch (sidebar) {
      'expanded' => true,
      'rail' => false,
      _ => MediaQuery.sizeOf(context).width >= 1100,
    };

    // Pedidos para entrar na Jam deste aparelho.
    listenJamRequests(ref, context);

    // Mensagens do player (erro ao tocar etc.)
    ref.listen(playerProvider.select((s) => s.message), (_, msg) {
      if (msg != null) {
        showSnack(context, msg);
        ref.read(playerProvider.notifier).consumeMessage();
      }
    });

    final content = ClipRect(child: widget.child);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): () => ref.read(playerProvider.notifier).toggle(),
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () => ref.read(playerProvider.notifier).toggle(),
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () =>
          ref.read(playerProvider.notifier).next(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () =>
          ref.read(playerProvider.notifier).previous(),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
          ref.read(playerProvider.notifier).seekBy(const Duration(seconds: 10)),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
          ref.read(playerProvider.notifier).seekBy(const Duration(seconds: -10)),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => context.go('/search'),
    };

    if (ref.watch(miniModeProvider)) {
      return const Scaffold(body: MiniWindow());
    }

    if (!wide) {
      final loc = widget.location;
      Future<bool> onBack() async {
        final router = GoRouter.of(context);
        // Página aberta por cima (álbum, artista, tocando agora): o go_router volta.
        if (router.canPop()) return false;
        final target = _backTarget(loc);
        if (target == null) return false;
        router.go(target);
        return true;
      }

      if (phoneLandscape) {
        return BackButtonListener(
          onBackButtonPressed: onBack,
          child: Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _mobileSelected(loc),
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: 0,
                    onDestinationSelected: (i) => context.go(_mobileDests[i].path),
                    destinations: [
                      for (final d in _mobileDests)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label(l10n)),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: content),
                        const MiniPlayer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return BackButtonListener(
        onBackButtonPressed: onBack,
        child: Scaffold(
          body: SafeArea(child: content),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MiniPlayer(),
              NavigationBar(
                selectedIndex: _mobileSelected(loc),
                onDestinationSelected: (i) => context.go(_mobileDests[i].path),
                destinations: [
                  for (final d in _mobileDests)
                    NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label(l10n)),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    SafeArea(
                      right: false,
                      child: _Sidebar(selected: _selected, extended: veryWide),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                    if (_queueOpen) ...[
                      const VerticalDivider(width: 1),
                      const SizedBox(width: 360, child: QueuePanel()),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              PlayerBar(queueOpen: _queueOpen, onToggleQueue: () => setState(() => _queueOpen = !_queueOpen)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.extended});
  final int selected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Rola quando as abas não cabem na altura (tablet deitado, janela baixa).
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: IntrinsicHeight(child: _rail(context, l10n)),
        ),
      ),
    );
  }

  Widget _rail(BuildContext context, AppLocalizations l10n) {
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 210,
      selectedIndex: selected < 0 ? null : selected,
      onDestinationSelected: (i) => context.go(_dests[i].path),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: extended
            ? Row(
                children: [
                  const BkLogo(size: 28),
                  const SizedBox(width: 8),
                  Text(l10n.appTitle, style: Theme.of(context).textTheme.titleMedium),
                ],
              )
            : const BkLogo(size: 32),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IconButton(
              tooltip: l10n.settings,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go('/settings'),
            ),
          ),
        ),
      ),
      destinations: [
        for (final d in _dests)
          NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label(l10n))),
      ],
    );
  }
}
