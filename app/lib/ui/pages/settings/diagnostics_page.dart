import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/diagnostics.dart';
import '../../../core/providers.dart';
import '../../../l10n/l10n.dart';
import '../../actions.dart';
import 'common.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  final p = await PackageInfo.fromPlatform();
  return p.buildNumber.isEmpty ? p.version : '${p.version} (${p.buildNumber})';
});

/// Diagnóstico (Ajustes → Sobre): erros registrados e o relatório para mandar
/// junto com um problema. O relatório não leva senha, token, endereço do
/// servidor nem usuário.
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  Map<String, String> _info(BuildContext context) {
    final s = ref.read(settingsProvider);
    final session = ref.read(sessionProvider).value;
    final server = session?.info;
    final mq = MediaQuery.of(context);
    return {
      'Versão': ref.read(appVersionProvider).value ?? '?',
      'Sistema': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'Dart': Platform.version.split(' ').first,
      'Idioma': Localizations.localeOf(context).toString(),
      'Tela': '${mq.size.width.round()}×${mq.size.height.round()} dp, densidade ${mq.devicePixelRatio.toStringAsFixed(2)}',
      'Conta': session == null
          ? 'nenhuma'
          : session.isLocal
              ? 'músicas do aparelho'
              : '${server?.type ?? 'servidor'} ${server?.version ?? ''}'.trim(),
      if (session != null && !session.isLocal) 'Connect': session.provider.connectKey == null ? 'precisa ativar' : 'protegido',
      'AutoMix': s.automixEnabled ? 'ligado (modelo ${s.analysisModel.name})' : 'desligado',
      'Servidor de análise': s.analysisServer == null ? 'não' : 'configurado',
      'Crossfade': '${s.crossfadeSeconds} s',
      'ReplayGain': s.replayGainMode.name,
      'Equalizador': s.eqEnabled ? 'ligado' : 'desligado',
      'Qualidade': s.maxBitRate == 0 ? 'original' : '${s.maxBitRate} kbps ${s.transcodeFormat ?? ''}'.trim(),
      'Downloads': '${s.downloadParallel} ao mesmo tempo',
      'Cache': '${s.cacheLimitMb} MB',
    };
  }

  String _fileName() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'bkmasterplayer-diagnostico-${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}.txt';
  }

  Future<void> _copy() async {
    final l10n = context.l10n;
    await Clipboard.setData(ClipboardData(text: diagnosticReport(info: _info(context))));
    if (mounted) showSnack(context, l10n.diagnosticsCopied);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final text = diagnosticReport(info: _info(context));
    try {
      final uri = await FilePicker.saveFile(
        fileName: _fileName(),
        bytes: Uint8List.fromList(utf8.encode(text)),
        mimeType: 'text/plain',
      );
      if (uri != null && mounted) showSnack(context, l10n.fileSaved);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _clear() async {
    await AppLog.instance.clear();
    if (!mounted) return;
    setState(() {});
    showSnack(context, context.l10n.diagnosticsCleared);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // Mais novo primeiro, cada registro inteiro (a pilha continua embaixo da
    // mensagem); a sessão anterior vem depois, com o rótulo em cima dela.
    final all = AppLog.instance.lines;
    final cut = all.indexOf('— sessão atual —');
    final previous = cut < 0 ? const <String>[] : all.sublist(1, cut);
    final current = cut < 0 ? all : all.sublist(cut + 1);
    List<String> newestFirst(List<String> l) => [for (final e in logEntries(l).reversed) ...e];
    final log = [
      ...newestFirst(current),
      if (previous.isNotEmpty) ...['— sessão anterior —', ...newestFirst(previous)],
    ].take(200).toList();
    return SettingsScaffold(
      title: l10n.diagnostics,
      back: '/settings/about',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(l10n.diagnosticsHint, style: theme.textTheme.bodyMedium),
        ),
        ListTile(
          leading: Icon(Icons.bug_report_outlined, color: AppLog.instance.errors > 0 ? theme.colorScheme.error : null),
          title: Text(l10n.diagnosticsErrors(AppLog.instance.errors)),
          subtitle: Text(ref.watch(appVersionProvider).value ?? ''),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(onPressed: _copy, icon: const Icon(Icons.copy_all_outlined), label: Text(l10n.diagnosticsCopy)),
              FilledButton.tonalIcon(onPressed: _save, icon: const Icon(Icons.save_alt), label: Text(l10n.diagnosticsSave)),
              TextButton.icon(onPressed: _clear, icon: const Icon(Icons.delete_sweep_outlined), label: Text(l10n.diagnosticsClear)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: log.isEmpty
              ? Text(l10n.diagnosticsEmpty, style: theme.textTheme.bodySmall)
              : SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in log)
                        Text(
                          l,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: l.contains('[erro]') ? theme.colorScheme.error : null,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
