import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers.dart';
import '../../../data/theme_library.dart';
import '../../../data/ui_prefs.dart';
import '../../../l10n/l10n.dart';
import '../../actions.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/ordered_toggles.dart';
import 'common.dart';
import 'theme_gallery.dart';

/// Personalização gráfica: um painel com as áreas do tema; cada área abre a
/// própria tela. Tudo muda na hora (o app é a prévia).
class LookPage extends ConsumerWidget {
  const LookPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ui = ref.watch(uiPrefsProvider);
    final n = _Names(l10n);

    Widget part(String id, IconData icon, String title, String subtitle) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/look/$id'),
        );

    return SettingsScaffold(
      title: l10n.settingsLook,
      children: [
        const ThemeGallery(),
        SettingsSection(l10n.customize),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(l10n.lookEditHint, style: Theme.of(context).textTheme.bodySmall),
        ),
        part('colors', Icons.palette_outlined, l10n.lookColors,
            '${n.mode(ui.themeMode)} • ${ui.colorSource == 'cover' ? l10n.dynamicColor : l10n.colorFixed} • ${n.variant(ui.variant)}'),
        part('fonts', Icons.font_download_outlined, l10n.lookFonts,
            '${l10n.fontTitles}: ${n.font(ui.titleFont)} • ${l10n.fontBody}: ${n.font(ui.bodyFont)}'),
        part('shapes', Icons.rounded_corner, l10n.lookShapes,
            '${l10n.cornerRadius}: ${ui.radius.round()} • ${n.shape(ui.coverShape)} • ${(ui.uiScale * 100).round()}%'),
        part('background', Icons.wallpaper_outlined, l10n.lookBackground, n.background(ui.background)),
        part('nowplaying', Icons.album_outlined, l10n.nowPlaying,
            n.layout(ui.nowPlayingLayout) +
                (ui.nowPlayingLayout == 'vinyl' ? ' • ${ui.vinylScratch ? l10n.vinylScratch : l10n.off}' : '')),
        part('structure', Icons.dashboard_customize_outlined, l10n.lookStructure,
            '${l10n.mobileTabs}: ${ui.mobileTabs.length + 1} • ${l10n.playerStyle}: ${n.player(ui.playerStyle)}'),
        part('motion', Icons.animation_outlined, l10n.lookMotion, '${n.transition(ui.transitions)} • ${n.speed(ui.animations)}'),
        const SizedBox(height: 8),
        const ThemeBackupSection(),
      ],
    );
  }
}

/// Tela de uma área da personalização (`/settings/look/<id>`).
Widget lookPartPage(String id) => switch (id) {
      'colors' => const _ColorsPage(),
      'fonts' => const _FontsPage(),
      'shapes' => const _ShapesPage(),
      'background' => const _BackgroundPage(),
      'nowplaying' => const _NowPlayingPage(),
      'structure' => const _StructurePage(),
      'backups' => const AutoBackupsPage(),
      _ => const _MotionPage(),
    };

/// Nomes das opções (compartilhados entre as telas e os resumos).
class _Names {
  _Names(this.l);
  final AppLocalizations l;

  String mode(String m) => switch (m) { 'system' => l.themeSystem, 'light' => l.themeLight, _ => l.themeDark };
  String variant(String v) => switch (v) {
        'fidelity' => l.variantFidelity,
        'monochrome' => l.variantMonochrome,
        'neutral' => l.variantNeutral,
        'vibrant' => l.variantVibrant,
        'expressive' => l.variantExpressive,
        'content' => l.variantContent,
        'rainbow' => l.variantRainbow,
        'fruitSalad' => l.variantFruitSalad,
        _ => l.variantTonalSpot,
      };
  String font(String f) => f == 'system' ? l.fontSystem : UiPrefs.fontFamily(f)!;
  String shape(String s) => switch (s) { 'square' => l.shapeSquare, 'circle' => l.shapeCircle, _ => l.shapeRounded };
  String background(String b) => switch (b) { 'gradient' => l.bgGradient, 'cover' => l.bgCover, 'image' => l.bgImage, _ => l.bgSolid };
  String layout(String s) => switch (s) { 'lyrics' => l.layoutLyrics, 'minimal' => l.layoutMinimal, 'vinyl' => l.layoutVinyl, _ => l.layoutSide };
  String player(String s) => s == 'floating' ? l.playerFloating : l.playerDocked;
  String transition(String t) => switch (t) { 'fade' => l.transFade, 'slide' => l.transSlide, 'none' => l.transNone, _ => l.transDefault };
  String speed(String s) => switch (s) { 'fast' => l.animFast, 'off' => l.animOff, _ => l.animNormal };
  String tab(String t) => switch (t) {
        'home' => l.home,
        'search' => l.search,
        'library' => l.library,
        'albums' => l.albums,
        'songs' => l.songs,
        'artists' => l.artists,
        'playlists' => l.playlists,
        'genres' => l.genres,
        'generate' => l.generatePlaylist,
        'favorites' => l.favorites,
        _ => l.downloads,
      };
}

const tabIcons = <String, IconData>{
  'home': Icons.home_outlined,
  'search': Icons.search,
  'library': Icons.library_music_outlined,
  'albums': Icons.album_outlined,
  'songs': Icons.music_note_outlined,
  'artists': Icons.person_outline,
  'playlists': Icons.queue_music_outlined,
  'genres': Icons.sell_outlined,
  'generate': Icons.playlist_add_circle_outlined,
  'favorites': Icons.favorite_border,
  'downloads': Icons.download_outlined,
};

/// Base das telas de área: título, seta para o painel e as preferências.
class _Part extends ConsumerWidget {
  const _Part({required this.title, required this.children});
  final String title;
  final List<Widget> Function(BuildContext context, UiPrefs ui, void Function(UiPrefs Function(UiPrefs)) set, _Names n) children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiPrefsProvider);
    void set(UiPrefs Function(UiPrefs) f) => ref.read(uiPrefsProvider.notifier).update(f);
    return SettingsScaffold(title: title, back: '/settings/look', children: children(context, ui, set, _Names(context.l10n)));
  }
}

// ---- Cores ----

class _ColorsPage extends StatelessWidget {
  const _ColorsPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Part(
      title: l10n.lookColors,
      children: (context, ui, set, n) {
        final scheme = Theme.of(context).colorScheme;
        return [
          const _PaletteStrip(),
          ChoiceTile<String>(
            title: l10n.theme,
            icon: Icons.brightness_6_outlined,
            value: ui.themeMode,
            options: {'system': l10n.themeSystem, 'light': l10n.themeLight, 'dark': '${l10n.themeDark} (${l10n.original})'},
            onChanged: (v) => set((p) => p.copyWith(themeMode: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: Text(l10n.amoled),
            subtitle: Text(l10n.amoledHint),
            value: ui.amoled,
            onChanged: ui.themeMode == 'light' ? null : (v) => set((p) => p.copyWith(amoled: v)),
          ),
          ChoiceTile<String>(
            title: l10n.colorSource,
            icon: Icons.palette_outlined,
            value: ui.colorSource,
            options: {'cover': l10n.colorFromCover, 'accent': l10n.colorFixed},
            onChanged: (v) => set((p) => p.copyWith(colorSource: v)),
          ),
          ListTile(
            leading: const Icon(Icons.color_lens_outlined),
            title: Text(l10n.baseColor),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ui.colorSource == 'cover') Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l10n.baseColorHint)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final c in {...colorSwatches, ui.seed})
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => set((p) => p.copyWith(seed: c)),
                          child: CircleAvatar(
                            radius: 15,
                            backgroundColor: Color(c),
                            child: ui.seed == c
                                ? Icon(Icons.check, size: 16, color: ThemeData.estimateBrightnessForColor(Color(c)) == Brightness.dark ? Colors.white : Colors.black)
                                : null,
                          ),
                        ),
                      TextButton.icon(
                        icon: const Icon(Icons.colorize, size: 18),
                        label: Text(l10n.pickColor),
                        onPressed: () async {
                          final c = await showColorPicker(context, initial: Color(ui.seed), title: l10n.baseColor);
                          if (c != null) set((p) => p.copyWith(seed: c.toARGB32()));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ChoiceTile<String>(
            title: l10n.paletteStyle,
            icon: Icons.style_outlined,
            value: ui.variant,
            options: {for (final v in UiPrefs.variants) v: n.variant(v)},
            onChanged: (v) => set((p) => p.copyWith(variant: v)),
          ),
          ListTile(
            leading: const Icon(Icons.contrast),
            title: Row(children: [
              Expanded(child: Text(l10n.contrast)),
              Text(ui.contrast == 0 ? '${l10n.contrastStandard} (${l10n.original})' : ui.contrast.toStringAsFixed(1)),
            ]),
            subtitle: Column(
              children: [
                Slider(value: ui.contrast, min: -1, max: 1, divisions: 8, onChanged: (v) => set((p) => p.copyWith(contrast: v))),
                Row(children: [
                  Text(l10n.contrastSoft, style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  Text(l10n.contrastMax, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ],
            ),
          ),
          SettingsSection(l10n.manualColors),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.manualColorsHint, style: Theme.of(context).textTheme.bodySmall),
          ),
          for (final (key, name, current) in [
            ('primary', l10n.colorPrimary, scheme.primary),
            ('secondary', l10n.colorSecondary, scheme.secondary),
            ('tertiary', l10n.colorTertiary, scheme.tertiary),
            ('background', l10n.colorBackground, scheme.surface),
            ('text', l10n.colorText, scheme.onSurface),
          ])
            ListTile(
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: current,
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.outlineVariant)),
                ),
              ),
              title: Text(name),
              subtitle: Text(ui.colors[key] == null ? l10n.automatic : '#${(ui.colors[key]! & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}'),
              trailing: ui.colors[key] == null
                  ? const Icon(Icons.edit_outlined)
                  : IconButton(
                      tooltip: l10n.automatic,
                      icon: const Icon(Icons.close),
                      onPressed: () => set((p) => p.copyWith(colors: {...p.colors}..remove(key))),
                    ),
              onTap: () async {
                final c = await showColorPicker(context, initial: current, title: name);
                if (c != null) set((p) => p.copyWith(colors: {...p.colors, key: c.toARGB32()}));
              },
            ),
        ];
      },
    );
  }
}

/// As cores do tema atual, lado a lado (para ver o efeito na hora).
class _PaletteStrip extends StatelessWidget {
  const _PaletteStrip();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final colors = [s.primary, s.primaryContainer, s.secondary, s.secondaryContainer, s.tertiary, s.tertiaryContainer, s.surfaceContainerHigh, s.surface];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 36,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final c in colors) Expanded(child: ColoredBox(color: c))],
          ),
        ),
      ),
    );
  }
}

// ---- Fontes ----

class _FontsPage extends StatelessWidget {
  const _FontsPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Part(
      title: l10n.lookFonts,
      children: (context, ui, set, n) {
        final theme = Theme.of(context);
        Widget option(String font, bool selected, VoidCallback onTap, {bool title = false}) {
          final family = UiPrefs.fontFamily(font);
          return ListTile(
            selected: selected,
            title: Text(n.font(font), style: TextStyle(fontFamily: family, fontSize: title ? 22 : 16, fontWeight: title ? FontWeight.w600 : null)),
            subtitle: Text(l10n.fontSample, style: TextStyle(fontFamily: family)),
            trailing: selected ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
            onTap: onTap,
          );
        }

        return [
          SettingsSection(l10n.fontTitles),
          for (final f in UiPrefs.titleFonts) option(f, ui.titleFont == f, () => set((p) => p.copyWith(titleFont: f)), title: true),
          SettingsSection(l10n.fontBody),
          for (final f in UiPrefs.bodyFonts) option(f, ui.bodyFont == f, () => set((p) => p.copyWith(bodyFont: f))),
        ];
      },
    );
  }
}

// ---- Formas e tamanhos ----

class _ShapesPage extends StatelessWidget {
  const _ShapesPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Part(
      title: l10n.lookShapes,
      children: (context, ui, set, n) => [
        ListTile(
          leading: const Icon(Icons.rounded_corner),
          title: Row(children: [Expanded(child: Text(l10n.cornerRadius)), Text('${ui.radius.round()}${ui.radius == 12 ? ' (${l10n.original})' : ''}')]),
          subtitle: Slider(value: ui.radius, min: 0, max: 28, divisions: 14, onChanged: (v) => set((p) => p.copyWith(radius: v))),
        ),
        ChoiceTile<String>(
          title: l10n.coverShape,
          icon: Icons.crop_square,
          value: ui.coverShape,
          options: {'square': l10n.shapeSquare, 'rounded': '${l10n.shapeRounded} (${l10n.original})', 'circle': l10n.shapeCircle},
          onChanged: (v) => set((p) => p.copyWith(coverShape: v)),
        ),
        ChoiceTile<String>(
          title: l10n.buttons,
          icon: Icons.smart_button_outlined,
          value: ui.buttonStyle,
          options: {'filled': l10n.buttonFilled, 'tonal': l10n.buttonTonal, 'outlined': l10n.buttonOutlined},
          onChanged: (v) => set((p) => p.copyWith(buttonStyle: v)),
        ),
        ChoiceTile<String>(
          title: l10n.cards,
          icon: Icons.web_stories_outlined,
          value: ui.cardStyle,
          options: {'flat': l10n.cardFlat, 'elevated': l10n.cardElevated, 'outlined': l10n.cardOutlined},
          onChanged: (v) => set((p) => p.copyWith(cardStyle: v)),
        ),
        // Prévia do que as escolhas acima fazem.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l10n.preview, style: Theme.of(context).textTheme.titleSmall),
                  FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.play_arrow), label: Text(l10n.play)),
                  OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.shuffle), label: Text(l10n.shuffle)),
                ],
              ),
            ),
          ),
        ),
        ChoiceTile<String>(
          title: l10n.density,
          icon: Icons.density_medium,
          value: ui.density,
          options: {
            'auto': '${l10n.modelAuto} (${l10n.original})',
            'compact': l10n.densityCompact,
            'standard': l10n.densityStandard,
            'comfortable': l10n.densityComfortable,
          },
          onChanged: (v) => set((p) => p.copyWith(density: v)),
        ),
        ListTile(
          leading: const Icon(Icons.zoom_in),
          title: Row(children: [Expanded(child: Text(l10n.uiScale)), Text('${(ui.uiScale * 100).round()}%')]),
          subtitle: Slider(value: ui.uiScale, min: 0.8, max: 1.5, divisions: 14, onChanged: (v) => set((p) => p.copyWith(uiScale: v))),
        ),
        ChoiceTile<String>(
          title: l10n.cardSize,
          icon: Icons.grid_view,
          value: ui.cardSize,
          options: {'small': l10n.sizeSmall, 'medium': '${l10n.sizeMedium} (${l10n.original})', 'large': l10n.sizeLarge},
          onChanged: (v) => set((p) => p.copyWith(cardSize: v)),
        ),
      ],
    );
  }
}

// ---- Fundo ----

class _BackgroundPage extends ConsumerWidget {
  const _BackgroundPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final support = ref.watch(supportDirProvider).path;
    return _Part(
      title: l10n.lookBackground,
      children: (context, ui, set, n) => [
        ChoiceTile<String>(
          title: l10n.backgroundStyle,
          icon: Icons.wallpaper_outlined,
          value: ui.background,
          options: {'solid': l10n.bgSolid, 'gradient': l10n.bgGradient, 'cover': l10n.bgCover, 'image': l10n.bgImage},
          onChanged: (v) => set((p) => p.copyWith(background: v)),
        ),
        if (ui.background == 'image')
          ListTile(
            leading: ui.backgroundImage == null
                ? const Icon(Icons.image_outlined)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(File(p.join(themeImagesDir(support), ui.backgroundImage!)),
                        width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                  ),
            title: Text(l10n.chooseImage),
            onTap: () async {
              final f = (await FilePicker.pickFiles(type: FileType.image)).firstOrNull;
              if (f == null) return;
              try {
                final bytes = await f.readAsBytes();
                final name = await importThemeImage(support, bytes, ext: p.extension(f.name));
                set((p) => p.copyWith(backgroundImage: name));
              } on FormatException {
                if (context.mounted) showSnack(context, l10n.imageTooBig);
              }
            },
          ),
        if (ui.background != 'solid')
          ListTile(
            leading: const Icon(Icons.opacity),
            title: Row(children: [Expanded(child: Text(l10n.backgroundDim)), Text('${(ui.backgroundDim * 100).round()}%')]),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(value: ui.backgroundDim, onChanged: (v) => set((p) => p.copyWith(backgroundDim: v))),
                Text(l10n.backgroundDimHint, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

// ---- Tocando agora ----

class _NowPlayingPage extends StatelessWidget {
  const _NowPlayingPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Part(
      title: l10n.nowPlaying,
      children: (context, ui, set, n) => [
        ChoiceTile<String>(
          title: l10n.nowPlayingLayout,
          icon: Icons.album,
          value: ui.nowPlayingLayout,
          options: {
            'side': '${l10n.layoutSide} (${l10n.original})',
            'lyrics': l10n.layoutLyrics,
            'minimal': l10n.layoutMinimal,
            'vinyl': l10n.layoutVinyl,
          },
          onChanged: (v) => set((p) => p.copyWith(nowPlayingLayout: v)),
        ),
        if (ui.nowPlayingLayout == 'vinyl')
          SwitchListTile(
            secondary: const Icon(Icons.touch_app_outlined),
            title: Text(l10n.vinylScratch),
            subtitle: Text(l10n.vinylScratchHint),
            value: ui.vinylScratch,
            onChanged: (v) => set((p) => p.copyWith(vinylScratch: v)),
          ),
        if (ui.nowPlayingLayout == 'vinyl')
          SwitchListTile(
            secondary: const Icon(Icons.graphic_eq),
            title: Text(l10n.vinylScratchAudio),
            subtitle: Text(l10n.vinylScratchAudioHint),
            value: ui.vinylScratchAudio,
            onChanged: ui.vinylScratch ? (v) => set((p) => p.copyWith(vinylScratchAudio: v)) : null,
          ),
        ListTile(
          leading: const Icon(Icons.blur_on),
          title: Row(children: [Expanded(child: Text(l10n.backgroundBlur)), Text('${(ui.nowPlayingBlur * 100).round()}%')]),
          subtitle: Slider(value: ui.nowPlayingBlur, onChanged: (v) => set((p) => p.copyWith(nowPlayingBlur: v))),
        ),
      ],
    );
  }
}

// ---- Estrutura das telas ----

class _StructurePage extends StatelessWidget {
  const _StructurePage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Part(
      title: l10n.lookStructure,
      children: (context, ui, set, n) {
        final tabNames = {for (final t in UiPrefs.allTabs) t: n.tab(t)};
        return [
          SettingsSection(l10n.mobileTabs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.mobileTabsHint, style: Theme.of(context).textTheme.bodySmall),
          ),
          OrderedToggles(
            all: UiPrefs.allTabs,
            enabled: ui.mobileTabs,
            names: tabNames,
            icons: tabIcons,
            min: 2,
            max: UiPrefs.maxMobileTabs,
            onLimit: () => showSnack(context, l10n.mobileTabsLimit),
            onChanged: (v) => set((p) => p.copyWith(mobileTabs: v)),
          ),
          SettingsSection(l10n.sidebarTabs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.sidebarTabsHint, style: Theme.of(context).textTheme.bodySmall),
          ),
          ChoiceTile<String>(
            title: l10n.sidebar,
            icon: Icons.view_sidebar_outlined,
            value: ui.sidebar,
            options: {'auto': '${l10n.modelAuto} (${l10n.original})', 'expanded': l10n.sidebarExpanded, 'rail': l10n.sidebarRail},
            onChanged: (v) => set((p) => p.copyWith(sidebar: v)),
          ),
          OrderedToggles(
            all: UiPrefs.allTabs.where((t) => t != 'library').toList(),
            enabled: ui.sidebarTabs,
            names: tabNames,
            icons: tabIcons,
            min: 1,
            onChanged: (v) => set((p) => p.copyWith(sidebarTabs: v)),
          ),
          ChoiceTile<String>(
            title: l10n.navLabels,
            icon: Icons.label_outline,
            value: ui.navLabels,
            options: {'auto': l10n.labelsAuto, 'all': l10n.labelsAll, 'selected': l10n.labelsSelected, 'none': l10n.labelsNone},
            onChanged: (v) => set((p) => p.copyWith(navLabels: v)),
          ),
          ChoiceTile<String>(
            title: l10n.playerStyle,
            icon: Icons.smart_display_outlined,
            value: ui.playerStyle,
            options: {'docked': l10n.playerDocked, 'floating': l10n.playerFloating},
            onChanged: (v) => set((p) => p.copyWith(playerStyle: v)),
          ),
          SettingsSection(l10n.playerBarButtons),
          OrderedToggles(
            all: UiPrefs.allPlayerButtons,
            enabled: ui.playerButtons,
            names: {
              'shuffle': l10n.shuffle,
              'repeat': l10n.repeat,
              'favorite': l10n.favorite,
              'mix': 'AutoMix',
              'eq': l10n.equalizer,
              'lyrics': l10n.lyrics,
              'queue': l10n.queue,
              'sleep': l10n.sleepTimer,
              'devices': l10n.devices,
              'mini': l10n.miniPlayer,
              'volume': l10n.volume,
            },
            onChanged: (v) => set((p) => p.copyWith(playerButtons: v)),
          ),
          SettingsSection(l10n.homeSections),
          OrderedToggles(
            all: UiPrefs.allHomeSections,
            enabled: ui.homeSections,
            names: {
              'newest': l10n.recentlyAdded,
              'recent': l10n.recentlyPlayed,
              'frequent': l10n.mostPlayed,
              'random': l10n.discover,
              'starred': l10n.favorites,
              'highest': l10n.topRated,
            },
            onChanged: (v) => set((p) => p.copyWith(homeSections: v)),
          ),
        ];
      },
    );
  }
}

// ---- Animações ----

class _MotionPage extends StatelessWidget {
  const _MotionPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Part(
      title: l10n.lookMotion,
      children: (context, ui, set, n) => [
        ChoiceTile<String>(
          title: l10n.transitions,
          icon: Icons.swap_horiz,
          value: ui.transitions,
          options: {'default': l10n.transDefault, 'fade': l10n.transFade, 'slide': l10n.transSlide, 'none': l10n.transNone},
          onChanged: (v) => set((p) => p.copyWith(transitions: v)),
        ),
        ChoiceTile<String>(
          title: l10n.animSpeed,
          icon: Icons.speed,
          value: ui.animations,
          options: {'normal': l10n.animNormal, 'fast': l10n.animFast, 'off': l10n.animOff},
          onChanged: (v) => set((p) => p.copyWith(animations: v)),
        ),
      ],
    );
  }
}
