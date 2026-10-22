import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/providers.dart';
import '../data/app_update.dart';
import '../l10n/l10n.dart';

/// Aviso de versão nova. Acompanha o download dentro dele mesmo: quem tocou
/// em "Atualizar" vê a barra andar e a instalação começar sozinha no fim.
Future<void> showUpdateDialog(BuildContext context) =>
    showDialog(context: context, barrierDismissible: false, builder: (_) => const _UpdateDialog());

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog();

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  /// A pessoa já disse "Atualizar": instala assim que o download terminar.
  bool _go = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final u = ref.watch(updateProvider);
    final notifier = ref.read(updateProvider.notifier);
    final rel = u.release;
    ref.listen(updateProvider.select((s) => s.status), (_, s) {
      if (s != UpdateStatus.ready || !_go) return;
      // Uma vez só: no Android, depois de abrir o instalador, volta a "pronto".
      _go = false;
      notifier.install();
    });
    if (rel == null) return const SizedBox.shrink();

    void close() => Navigator.of(context).pop();
    final busy = u.status == UpdateStatus.downloading || u.status == UpdateStatus.installing;
    final hint = !notifier.canInstall
        ? l10n.updateManualHint
        : Platform.isAndroid
        ? l10n.updateAndroidHint
        : l10n.updateRestartHint;

    return AlertDialog(
      title: Text(u.status == UpdateStatus.ready ? l10n.updateReady(rel.version) : l10n.updateAvailable(rel.version)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rel.notes.trim().isNotEmpty)
              Flexible(
                child: SingleChildScrollView(child: Text(plainNotes(rel.notes), style: theme.textTheme.bodyMedium)),
              ),
            const SizedBox(height: 12),
            Text(hint, style: theme.textTheme.bodySmall),
            if (u.status == UpdateStatus.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: u.progress > 0 ? u.progress : null),
              const SizedBox(height: 4),
              Text(l10n.updateDownloading((u.progress * 100).round()), style: theme.textTheme.bodySmall),
            ],
            if (u.status == UpdateStatus.installing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(l10n.updateInstalling, style: theme.textTheme.bodySmall),
            ],
            if (u.status == UpdateStatus.failed && u.error != null) ...[
              const SizedBox(height: 12),
              Text(l10n.updateFailed(u.error!), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        if (!busy)
          TextButton(
            onPressed: () {
              notifier.skip();
              close();
            },
            child: Text(l10n.updateSkip),
          ),
        // Fechar durante o download não cancela: ele termina e avisa de novo.
        TextButton(onPressed: u.status == UpdateStatus.installing && !Platform.isAndroid ? null : close, child: Text(l10n.updateLater)),
        if (!notifier.canInstall)
          FilledButton(
            onPressed: () {
              launchUrl(Uri.parse(rel.page), mode: LaunchMode.externalApplication);
              close();
            },
            child: Text(l10n.updateOpenPage),
          )
        else if (u.status == UpdateStatus.ready)
          FilledButton(onPressed: notifier.install, child: Text(l10n.updateInstall))
        else
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    setState(() => _go = true);
                    notifier.download();
                  },
            child: Text(l10n.updateNow),
          ),
      ],
    );
  }
}

/// As novidades do release vêm em Markdown; no aviso, texto simples basta.
String plainNotes(String md) => md
    .replaceAll('\r', '')
    .split('\n')
    .map(
      (l) => l
          .replaceFirst(RegExp(r'^#+\s*'), '')
          .replaceFirstMapped(RegExp(r'^(\s*)[-*]\s+'), (m) => '${m[1]}• ')
          .replaceAll('**', '')
          .replaceAll('`', ''),
    )
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// Bloco de Ajustes → Sobre: as opções e o "procurar agora".
class UpdateSettingsTiles extends ConsumerWidget {
  const UpdateSettingsTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final u = ref.watch(updateProvider);
    final notifier = ref.read(updateProvider.notifier);
    final v = u.release?.version ?? '';

    final status = switch (u.status) {
      UpdateStatus.idle => null,
      UpdateStatus.checking => l10n.updateChecking,
      UpdateStatus.upToDate => l10n.updateUpToDate,
      UpdateStatus.available => l10n.updateAvailable(v),
      UpdateStatus.downloading => l10n.updateDownloading((u.progress * 100).round()),
      UpdateStatus.ready => l10n.updateReady(v),
      UpdateStatus.installing => l10n.updateInstalling,
      UpdateStatus.failed => l10n.updateFailed(u.error ?? ''),
    };
    final hasNew = u.status == UpdateStatus.available || u.status == UpdateStatus.ready;

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.system_update_outlined),
          title: Text(l10n.updateCheckOnOpen),
          subtitle: Text(l10n.updateCheckOnOpenHint),
          value: s.updateCheck,
          onChanged: (v) => set((x) => x.copyWith(updateCheck: v)),
        ),
        if (notifier.kind != InstallKind.none)
          SwitchListTile(
            secondary: const Icon(Icons.download_outlined),
            title: Text(l10n.updateAutoDownload),
            subtitle: Text(l10n.updateAutoDownloadHint),
            value: s.updateAutoDownload,
            onChanged: s.updateCheck ? (v) => set((x) => x.copyWith(updateAutoDownload: v)) : null,
          ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: Text(hasNew ? l10n.updateNow : l10n.updateCheckNow),
          subtitle: status == null ? null : Text(status),
          trailing: u.status == UpdateStatus.checking
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          // Com versão nova, abre o aviso (novidades e o botão de instalar).
          onTap: hasNew ? () => showUpdateDialog(context) : notifier.check,
        ),
      ],
    );
  }
}
