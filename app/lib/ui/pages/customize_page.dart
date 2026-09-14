import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/ui_prefs.dart';
import '../../l10n/l10n.dart';
import '../actions.dart';

/// Personalização completa: tema, capas, "tocando agora", layout, barra do
/// player, Início, comportamento e perfis (exportar/importar).
class CustomizePage extends ConsumerWidget {
  const CustomizePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final ui = ref.watch(uiPrefsProvider);
    final setUi = ref.read(uiPrefsProvider.notifier).update;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    Widget choice<T>(String title, T value, Map<T, String> options, ValueChanged<T> onChanged, {IconData? icon}) => ListTile(
          leading: Icon(icon ?? Icons.tune),
          title: Text(title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in options.entries)
                  ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => onChanged(e.key)),
              ],
            ),
          ),
        );

    final buttonNames = {
      'shuffle': l10n.shuffle,
      'repeat': l10n.repeat,
      'favorite': l10n.favorite,
      'mix': 'AutoMix',
      'eq': l10n.equalizer,
      'lyrics': l10n.lyrics,
      'queue': l10n.queue,
      'devices': l10n.devices,
      'mini': l10n.miniPlayer,
      'volume': l10n.volume,
    };
    final sectionNames = {
      'newest': l10n.recentlyAdded,
      'recent': l10n.recentlyPlayed,
      'frequent': l10n.mostPlayed,
      'random': l10n.discover,
      'starred': l10n.favorites,
      'highest': l10n.topRated,
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Text(l10n.customize, style: theme.textTheme.headlineMedium),
        ),

        // ---- Tema ----
        section(l10n.theme),
        choice<String>(l10n.theme, ui.themeMode, {
          'system': l10n.themeSystem,
          'light': l10n.themeLight,
          'dark': l10n.themeDark,
        }, (v) => setUi((x) => x.copyWith(themeMode: v)), icon: Icons.brightness_6_outlined),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: Text(l10n.amoled),
          subtitle: Text(l10n.amoledHint),
          value: ui.amoled,
          onChanged: (v) => setUi((p) => p.copyWith(amoled: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.palette_outlined),
          title: Text(l10n.dynamicColor),
          subtitle: Text(l10n.dynamicColorHint),
          value: ui.colorSource == 'cover',
          onChanged: (v) => setUi((x) => x.copyWith(colorSource: v ? 'cover' : 'accent')),
        ),
        ListTile(
          leading: const Icon(Icons.color_lens_outlined),
          title: Text(l10n.accentColor),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _HueSlider(
                value: HSVColor.fromColor(Color(ui.seed)).hue,
                onChanged: (h) => setUi((p) => p.copyWith(seed: HSVColor.fromAHSV(1, h, 0.7, 0.9).toColor().toARGB32())),
              ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.rounded_corner),
          title: Row(children: [Expanded(child: Text(l10n.cornerRadius)), Text('${ui.radius.round()}')]),
          subtitle: Slider(value: ui.radius, min: 0, max: 28, divisions: 14, onChanged: (v) => setUi((p) => p.copyWith(radius: v))),
        ),
        choice<String>(l10n.density, ui.density, {
          'auto': l10n.modelAuto,
          'compact': l10n.densityCompact,
          'standard': l10n.densityStandard,
          'comfortable': l10n.densityComfortable,
        }, (v) => setUi((p) => p.copyWith(density: v)), icon: Icons.density_medium),
        ListTile(
          leading: const Icon(Icons.zoom_in),
          title: Row(children: [Expanded(child: Text(l10n.uiScale)), Text('${(ui.uiScale * 100).round()}%')]),
          subtitle: Slider(value: ui.uiScale, min: 0.8, max: 1.5, divisions: 14, onChanged: (v) => setUi((x) => x.copyWith(uiScale: v))),
        ),

        // ---- Capas e "tocando agora" ----
        section(l10n.nowPlaying),
        choice<String>(l10n.coverShape, ui.coverShape, {
          'square': l10n.shapeSquare,
          'rounded': l10n.shapeRounded,
          'circle': l10n.shapeCircle,
        }, (v) => setUi((p) => p.copyWith(coverShape: v)), icon: Icons.crop_square),
        choice<String>(l10n.nowPlayingLayout, ui.nowPlayingLayout, {
          'side': l10n.layoutSide,
          'lyrics': l10n.layoutLyrics,
          'minimal': l10n.layoutMinimal,
          'vinyl': l10n.layoutVinyl,
        }, (v) => setUi((p) => p.copyWith(nowPlayingLayout: v)), icon: Icons.album),
        ListTile(
          leading: const Icon(Icons.blur_on),
          title: Row(children: [Expanded(child: Text(l10n.backgroundBlur)), Text('${(ui.nowPlayingBlur * 100).round()}%')]),
          subtitle: Slider(value: ui.nowPlayingBlur, onChanged: (v) => setUi((p) => p.copyWith(nowPlayingBlur: v))),
        ),

        // ---- Layout ----
        section(l10n.layout),
        choice<String>(l10n.sidebar, ui.sidebar, {
          'auto': l10n.modelAuto,
          'expanded': l10n.sidebarExpanded,
          'rail': l10n.sidebarRail,
        }, (v) => setUi((p) => p.copyWith(sidebar: v)), icon: Icons.view_sidebar_outlined),
        choice<String>(l10n.cardSize, ui.cardSize, {
          'small': l10n.sizeSmall,
          'medium': l10n.sizeMedium,
          'large': l10n.sizeLarge,
        }, (v) => setUi((p) => p.copyWith(cardSize: v)), icon: Icons.grid_view),
        choice<String>(l10n.startPage, ui.startPage, {
          '/': l10n.home,
          '/albums': l10n.albums,
          '/artists': l10n.artists,
          '/playlists': l10n.playlists,
          '/search': l10n.search,
        }, (v) => setUi((p) => p.copyWith(startPage: v)), icon: Icons.home_outlined),
        SwitchListTile(
          secondary: const Icon(Icons.queue_music),
          title: Text(l10n.showQueueOnStart),
          value: ui.showQueue,
          onChanged: (v) => setUi((p) => p.copyWith(showQueue: v)),
        ),

        // ---- Barra do player ----
        section(l10n.playerBarButtons),
        _OrderedToggles(
          all: UiPrefs.allPlayerButtons,
          enabled: ui.playerButtons,
          names: buttonNames,
          onChanged: (list) => setUi((p) => p.copyWith(playerButtons: list)),
        ),

        // ---- Início ----
        section(l10n.homeSections),
        _OrderedToggles(
          all: UiPrefs.allHomeSections,
          enabled: ui.homeSections,
          names: sectionNames,
          onChanged: (list) => setUi((p) => p.copyWith(homeSections: list)),
        ),

        // ---- Comportamento ----
        section(l10n.behavior),
        choice<String>(l10n.songTap, ui.songTap, {
          'playFromHere': l10n.tapPlayFromHere,
          'playOne': l10n.tapPlayOne,
          'enqueue': l10n.addToQueue,
        }, (v) => setUi((p) => p.copyWith(songTap: v)), icon: Icons.touch_app_outlined),
        ListTile(
          leading: const Icon(Icons.keyboard_outlined),
          title: Text(l10n.shortcuts),
          subtitle: Text(l10n.shortcutsList),
        ),

        // ---- Perfis ----
        section(l10n.profiles),
        ListTile(
          leading: const Icon(Icons.upload_outlined),
          title: Text(l10n.exportProfile),
          subtitle: Text(l10n.exportProfileHint),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: ref.read(uiPrefsProvider.notifier).exportProfile()));
            if (context.mounted) showSnack(context, l10n.profileCopied);
          },
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(l10n.importProfile),
          subtitle: Text(l10n.importProfileHint),
          onTap: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            try {
              ref.read(uiPrefsProvider.notifier).importProfile(data?.text ?? '');
              if (context.mounted) showSnack(context, l10n.profileImported);
            } catch (_) {
              if (context.mounted) showSnack(context, l10n.profileInvalid);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: Text(l10n.resetAppearance),
          onTap: () => setUi((_) => const UiPrefs()),
        ),
      ],
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: LinearGradient(colors: [
                for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble(), 0.7, 0.9).toColor(),
              ]),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: HSVColor.fromAHSV(1, value, 0.7, 0.9).toColor(),
            ),
            child: Slider(value: value.clamp(0, 360), max: 360, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

/// Lista reordenável com liga/desliga (botões da barra, seções do Início).
class _OrderedToggles extends StatelessWidget {
  const _OrderedToggles({required this.all, required this.enabled, required this.names, required this.onChanged});
  final List<String> all;
  final List<String> enabled;
  final Map<String, String> names;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    // Ativos primeiro (na ordem escolhida), depois os desligados.
    final items = [...enabled, ...all.where((k) => !enabled.contains(k))];
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: (from, to) {
        final list = List.of(items);
        final item = list.removeAt(from);
        list.insert(to > from ? to - 1 : to, item);
        onChanged(list.where(enabled.contains).toList());
      },
      children: [
        for (var i = 0; i < items.length; i++)
          CheckboxListTile(
            key: ValueKey(items[i]),
            value: enabled.contains(items[i]),
            title: Text(names[items[i]] ?? items[i]),
            secondary: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) {
              final next = v == true ? [...enabled, items[i]] : enabled.where((k) => k != items[i]).toList();
              // Mantém a ordem da lista visível.
              onChanged(items.where(next.contains).toList());
            },
          ),
      ],
    );
  }
}
