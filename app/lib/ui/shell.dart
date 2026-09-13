import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../desktop/desktop_integration.dart';
import '../l10n/l10n.dart';
import '../player/player_controller.dart';
import 'actions.dart';
import 'player/player_bar.dart';
import 'player/queue_panel.dart';
import 'player/mini_window.dart';

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
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final sidebar = ref.watch(uiPrefsProvider.select((p) => p.sidebar));
    final veryWide = switch (sidebar) {
      'expanded' => true,
      'rail' => false,
      _ => MediaQuery.sizeOf(context).width >= 1100,
    };

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
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () => ref.read(playerProvider.notifier).next(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () => ref.read(playerProvider.notifier).previous(),
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
      final sel = _selected;
      return Scaffold(
        body: SafeArea(child: content),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: sel.clamp(0, 4),
              onDestinationSelected: (i) => context.go(_dests[i].path),
              destinations: [
                for (final d in _dests.take(5))
                  NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label(l10n)),
              ],
            ),
          ],
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
                    _Sidebar(selected: _selected, extended: veryWide),
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
                  Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(l10n.appTitle, style: Theme.of(context).textTheme.titleMedium),
                ],
              )
            : Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary),
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
