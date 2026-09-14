import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers.dart';
import '../../l10n/l10n.dart';
import 'local_provider.dart';

/// Pasta de músicas sugerida no primeiro uso.
String defaultMusicFolder() {
  if (Platform.isAndroid) return '/storage/emulated/0/Music';
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  for (final name in ['Música', 'Músicas', 'Music']) {
    final d = Directory('$home${Platform.pathSeparator}$name');
    if (d.existsSync()) return d.path;
  }
  return home;
}

/// Permissão de ler as músicas do aparelho (Android). true = pode ler.
Future<bool> ensureMusicPermission() async {
  if (!Platform.isAndroid) return true;
  // Android 13+: "Músicas e áudio"; até o 12: armazenamento.
  final r = await [Permission.audio, Permission.storage].request();
  return r.values.any((s) => s.isGranted || s.isLimited);
}

Future<String?> pickFolder(String title) async {
  try {
    return await FilePicker.getDirectoryPath(dialogTitle: title);
  } catch (_) {
    return null;
  }
}

/// Pergunta a pasta das músicas (a sugerida ou outra). null = cancelou.
Future<String?> chooseMusicFolder(BuildContext context) async {
  final l10n = context.l10n;
  var folder = defaultMusicFolder();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l10n.musicFolder),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.musicFolderHint),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.folder_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(folder, style: Theme.of(context).textTheme.bodyLarge)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final picked = await pickFolder(l10n.musicFolder);
              if (picked != null) setState(() => folder = picked);
            },
            child: Text(l10n.chooseOtherFolder),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, folder), child: Text(l10n.useThisFolder)),
        ],
      ),
    ),
  );
}

/// Roda [task] (uma varredura) mostrando quantos arquivos já foram lidos.
Future<T> runWithScanProgress<T>(BuildContext context, Future<T> Function() task) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final dialog = showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _ScanDialog());
  try {
    return await task();
  } finally {
    nav.pop();
    await dialog;
  }
}

class _ScanDialog extends StatefulWidget {
  const _ScanDialog();
  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  late final Timer _timer;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => setState(() => _n = LocalProvider.scanProgress()));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(context.l10n.scanningMusic(_n))),
            ],
          ),
        ),
      );
}

/// Recarrega as telas da biblioteca depois de uma varredura.
void refreshLibrary(WidgetRef ref) {
  ref.invalidate(albumListProvider);
  ref.invalidate(albumProvider);
  ref.invalidate(artistsProvider);
  ref.invalidate(artistProvider);
  ref.invalidate(genresProvider);
  ref.invalidate(genreSongsProvider);
  ref.invalidate(starredSongsProvider);
  ref.invalidate(playlistsProvider);
  ref.invalidate(searchProvider);
  ref.invalidate(topSongsProvider);
}
