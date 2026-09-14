import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers.dart';
import '../../../data/theme_library.dart';
import '../../../data/ui_prefs.dart';
import '../../../l10n/l10n.dart';
import '../../actions.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// Nome do tema na tela (os prontos são traduzidos).
String themeName(AppLocalizations l10n, BkTheme t) => switch (t.id) {
      'builtin:original' => l10n.themeOriginal,
      'builtin:vinyl' => l10n.themeVinyl,
      'builtin:paper' => l10n.themePaper,
      'builtin:contrast' => l10n.themeContrast,
      'builtin:auto' => l10n.themeAuto,
      _ => t.name,
    };

/// Galeria: os temas prontos e os seus, em miniaturas desenhadas com cada
/// tema. Tocar aplica; segurar (ou ⋮) abre as opções.
class ThemeGallery extends ConsumerWidget {
  const ThemeGallery({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final themes = ref.watch(themesProvider).value ?? builtInThemes;
    final ui = ref.watch(uiPrefsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(l10n.themes),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(l10n.themesHint, style: Theme.of(context).textTheme.bodySmall),
        ),
        SizedBox(
          height: 212,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final t in themes)
                _ThemeCard(
                  theme: t,
                  name: themeName(l10n, t),
                  active: ui.sameTheme(t.theme),
                  modified: ui.themeId == t.id && !ui.sameTheme(t.theme),
                ),
              _SaveCard(),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends ConsumerWidget {
  const _ThemeCard({required this.theme, required this.name, required this.active, required this.modified});
  final BkTheme theme;
  final String name;
  final bool active;
  final bool modified;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 124,
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => ref.read(themesProvider.notifier).apply(theme),
              onLongPress: () => _themeActions(context, ref, theme, name, modified),
              child: Container(
                height: 164,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: active || modified ? current.primary : current.outlineVariant, width: active || modified ? 2.5 : 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Positioned.fill(child: ThemePreview(prefs: theme.prefs)),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                          icon: const Icon(Icons.more_vert),
                          color: Colors.white,
                          style: IconButton.styleFrom(backgroundColor: Colors.black38),
                          onPressed: () => _themeActions(context, ref, theme, name, modified),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (active) ...[Icon(Icons.check_circle, size: 16, color: current.primary), const SizedBox(width: 4)],
                Flexible(
                  child: Text(
                    modified ? '$name ✱' : name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: active || modified ? current.primary : null),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura de um tema: fundo, capa no formato do tema, título na fonte dele,
/// botão e barra do player (grudada ou flutuante), com as cores dele.
class ThemePreview extends ConsumerWidget {
  const ThemePreview({super.key, required this.prefs});
  final UiPrefs prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = MediaQuery.platformBrightnessOf(context);
    final brightness = switch (prefs.themeMode) { 'light' => Brightness.light, 'dark' => Brightness.dark, _ => platform };
    final s = AppTheme.seeded(prefs, brightness);
    final title = UiPrefs.fontFamily(prefs.titleFont);
    final body = UiPrefs.fontFamily(prefs.bodyFont);
    final r = prefs.radius;
    final coverR = switch (prefs.coverShape) { 'square' => 0.0, 'circle' => 22.0, _ => (r * 0.6).clamp(0.0, 22.0) };
    final floating = prefs.playerStyle == 'floating';
    final image = prefs.background == 'image' && prefs.backgroundImage != null
        ? File(p.join(themeImagesDir(ref.watch(supportDirProvider).path), prefs.backgroundImage!))
        : null;

    final background = switch (prefs.background) {
      'gradient' => BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [s.primaryContainer, s.surface, s.tertiaryContainer])),
      'cover' => BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(s.surface, s.primary, 0.35)!, s.surface])),
      _ => BoxDecoration(color: s.surface),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: background),
        if (image != null) ...[
          Image.file(image, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
          ColoredBox(color: s.surface.withValues(alpha: prefs.backgroundDim)),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aa', style: TextStyle(fontFamily: title, fontSize: 24, fontWeight: FontWeight.w600, color: s.onSurface, height: 1.1)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(coverR),
                      gradient: LinearGradient(colors: [s.primary, s.tertiary]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BK', maxLines: 1, style: TextStyle(fontFamily: body, fontSize: 11, color: s.onSurface)),
                        const SizedBox(height: 4),
                        Container(height: 5, width: 40, decoration: BoxDecoration(color: s.onSurfaceVariant.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: switch (prefs.buttonStyle) { 'tonal' => s.secondaryContainer, 'outlined' => Colors.transparent, _ => s.primary },
                  border: prefs.buttonStyle == 'outlined' ? Border.all(color: s.primary, width: 1.5) : null,
                  borderRadius: BorderRadius.circular(r >= 18 ? 20 : r),
                ),
                child: Icon(Icons.play_arrow, size: 16, color: switch (prefs.buttonStyle) { 'tonal' => s.onSecondaryContainer, 'outlined' => s.primary, _ => s.onPrimary }),
              ),
            ],
          ),
        ),
        Positioned(
          left: floating ? 6 : 0,
          right: floating ? 6 : 0,
          bottom: floating ? 6 : 0,
          child: Container(
            height: 22,
            decoration: BoxDecoration(
              color: s.surfaceContainerHigh,
              borderRadius: floating ? BorderRadius.circular(r / 2 + 4) : null,
              boxShadow: floating ? const [BoxShadow(blurRadius: 4, color: Colors.black26)] : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 6),
                Container(width: 12, height: 12, decoration: BoxDecoration(color: s.primary, borderRadius: BorderRadius.circular(coverR / 4))),
                const Spacer(),
                Icon(Icons.play_arrow, size: 14, color: s.onSurface),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SaveCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 124,
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => saveCurrentAsTheme(context, ref),
              child: Container(
                height: 164,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Center(child: Icon(Icons.add, size: 36, color: scheme.primary)),
              ),
            ),
            const SizedBox(height: 6),
            Text(l10n.saveAsTheme, maxLines: 2, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

Future<void> saveCurrentAsTheme(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final name = await askText(context, title: l10n.themeName, initial: l10n.myTheme);
  if (name == null || name.trim().isEmpty) return;
  final t = await ref.read(themesProvider.notifier).saveCurrent(name);
  if (context.mounted) showSnack(context, l10n.themeSaved(t.name));
}

Future<void> _themeActions(BuildContext context, WidgetRef ref, BkTheme t, String name, bool modified) async {
  final l10n = context.l10n;
  final themes = ref.read(themesProvider.notifier);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(name, style: Theme.of(sheet).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.check),
            title: Text(l10n.applyTheme),
            onTap: () {
              Navigator.pop(sheet);
              themes.apply(t);
            },
          ),
          if (!t.builtIn && modified)
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: Text(l10n.saveChangesHere),
              onTap: () {
                Navigator.pop(sheet);
                themes.overwriteWithCurrent(t.id);
              },
            ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l10n.duplicate),
            onTap: () {
              Navigator.pop(sheet);
              themes.duplicate(t, l10n.copyOf(name));
            },
          ),
          if (!t.builtIn)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.rename),
              onTap: () async {
                Navigator.pop(sheet);
                final n = await askText(context, title: l10n.themeName, initial: t.name);
                if (n != null && n.trim().isNotEmpty) await themes.rename(t.id, n);
              },
            ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: Text(l10n.exportThemeFile),
            onTap: () async {
              Navigator.pop(sheet);
              final text = await themes.lib.exportTheme(BkTheme(id: t.id, name: name, theme: t.theme));
              if (context.mounted) await _saveText(context, '${_fileSafe(name)}.bktheme.json', text);
            },
          ),
          if (!t.builtIn)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.delete),
              onTap: () async {
                Navigator.pop(sheet);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    content: Text(l10n.deleteThemeConfirm(name)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: Text(l10n.cancel)),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(l10n.delete)),
                    ],
                  ),
                );
                if (ok == true) await themes.delete(t.id);
              },
            ),
        ],
      ),
    ),
  );
}

String _fileSafe(String name) => name.replaceAll(RegExp(r'[^\w\- ]+'), '').trim().replaceAll(' ', '-').toLowerCase();

/// Salva um arquivo onde a pessoa escolher (no Android, pelo seletor do sistema).
Future<void> _saveText(BuildContext context, String fileName, String text) async {
  final l10n = context.l10n;
  try {
    final uri = await FilePicker.saveFile(
      fileName: fileName.isEmpty ? 'tema.bktheme.json' : fileName,
      bytes: Uint8List.fromList(utf8.encode(text)),
      mimeType: 'application/json',
    );
    if (uri != null && context.mounted) showSnack(context, l10n.fileSaved);
  } catch (e) {
    if (context.mounted) showSnack(context, '$e');
  }
}

/// Abre um arquivo de tema/backup escolhido pela pessoa (texto).
Future<String?> _pickText() async {
  final f = (await FilePicker.pickFiles(type: FileType.any)).firstOrNull;
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  if (bytes.length > maxThemeFileBytes) throw const FormatException('arquivo grande demais');
  return utf8.decode(bytes);
}

/// Backup e arquivos: salvar como tema, importar/exportar, backup completo,
/// backups automáticos, perfis em texto e voltar ao original.
class ThemeBackupSection extends ConsumerWidget {
  const ThemeBackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final themes = ref.read(themesProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(l10n.backupFiles),
        ListTile(
          leading: const Icon(Icons.bookmark_add_outlined),
          title: Text(l10n.saveAsTheme),
          onTap: () => saveCurrentAsTheme(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: Text(l10n.importTheme),
          onTap: () async {
            try {
              final text = await _pickText();
              if (text == null) return;
              final t = await themes.importAndApply(text);
              if (context.mounted) showSnack(context, l10n.themeImported(t.name));
            } catch (_) {
              if (context.mounted) showSnack(context, l10n.invalidThemeFile);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.save_alt),
          title: Text(l10n.exportBackup),
          subtitle: Text(l10n.exportBackupHint),
          onTap: () async {
            final text = await themes.lib.exportBackup(ref.read(uiPrefsProvider));
            final d = DateTime.now();
            final stamp = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            if (context.mounted) await _saveText(context, 'bkplayer-temas-$stamp.bkbackup.json', text);
          },
        ),
        ListTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(l10n.restoreBackup),
          onTap: () async {
            try {
              final text = await _pickText();
              if (text == null || !context.mounted) return;
              if (await _confirmRestore(context)) {
                await themes.restore(text);
                if (context.mounted) showSnack(context, l10n.backupRestored);
              }
            } catch (_) {
              if (context.mounted) showSnack(context, l10n.invalidThemeFile);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(l10n.autoBackups),
          subtitle: Text(l10n.autoBackupsHint),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/look/backups'),
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: Text(l10n.backToOriginal),
          subtitle: Text(l10n.backToOriginalHint),
          onTap: () => themes.apply(builtInThemes.first),
        ),
        ExpansionTile(
          leading: const Icon(Icons.content_paste),
          title: Text(l10n.textProfiles),
          children: [
            ListTile(
              title: Text(l10n.exportProfile),
              subtitle: Text(l10n.exportProfileHint),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: ref.read(uiPrefsProvider.notifier).exportProfile()));
                if (context.mounted) showSnack(context, l10n.profileCopied);
              },
            ),
            ListTile(
              title: Text(l10n.importProfile),
              subtitle: Text(l10n.importProfileHint),
              onTap: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                try {
                  await themes.backupIfUnsaved();
                  ref.read(uiPrefsProvider.notifier).importProfile(data?.text ?? '');
                  if (context.mounted) showSnack(context, l10n.profileImported);
                } catch (_) {
                  if (context.mounted) showSnack(context, l10n.profileInvalid);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

Future<bool> _confirmRestore(BuildContext context) async {
  final l10n = context.l10n;
  return await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          content: Text(l10n.restoreBackupConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(l10n.cancel)),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(l10n.restore)),
          ],
        ),
      ) ??
      false;
}

/// Backups automáticos (`/settings/look/backups`).
class AutoBackupsPage extends ConsumerStatefulWidget {
  const AutoBackupsPage({super.key});

  @override
  ConsumerState<AutoBackupsPage> createState() => _AutoBackupsPageState();
}

class _AutoBackupsPageState extends ConsumerState<AutoBackupsPage> {
  Future<List<AutoBackup>>? _list;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lib = ref.watch(themesProvider).hasValue ? ref.read(themesProvider.notifier).lib : null;
    _list ??= lib?.autoBackups();
    final loc = MaterialLocalizations.of(context);
    return FutureBuilder<List<AutoBackup>>(
      future: _list,
      builder: (context, snap) {
        final items = snap.data ?? const <AutoBackup>[];
        return SettingsScaffold(
          title: l10n.autoBackups,
          back: '/settings/look',
          children: [
            if (snap.connectionState == ConnectionState.done && items.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text(l10n.noAutoBackups)),
            for (final b in items)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text('${loc.formatMediumDate(b.date)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(b.date))}'),
                trailing: TextButton(
                  child: Text(l10n.restore),
                  onPressed: () async {
                    if (!await _confirmRestore(context)) return;
                    await ref.read(themesProvider.notifier).restore(await File(b.path).readAsString());
                    if (!context.mounted) return;
                    showSnack(context, l10n.backupRestored);
                    setState(() => _list = ref.read(themesProvider.notifier).lib.autoBackups());
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
