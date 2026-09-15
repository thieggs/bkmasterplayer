import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../pages/automix_settings.dart' show deviceProfileProvider;

/// Painel do AutoMix (toque no ícone): liga/desliga, a próxima transição
/// (sincronizada ou simples, e por quê) e a análise da música atual e da
/// próxima — BPM, tom e se a batida é confiável, com os números da grade.
Future<void> showAutomixStatus(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _AutomixStatusSheet(),
    );

class _AutomixStatusSheet extends ConsumerWidget {
  const _AutomixStatusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = ref.watch(settingsProvider.select((s) => s.automixEnabled));
    final s = ref.watch(playerProvider);
    final current = s.current;
    final next = s.index + 1 < s.queue.length ? s.queue[s.index + 1] : null;
    final model = ref.watch(deviceProfileProvider).value?.activeModel;

    Widget status() {
      if (!enabled) return _Line(icon: Icons.auto_awesome_outlined, text: l10n.automixOffStatus);
      if (s.mix != null) {
        return _Line(icon: Icons.auto_awesome, color: scheme.primary, text: '${l10n.mixing}: ${s.mix!.summary}');
      }
      if (s.plannedMix != null) {
        return _Line(
          icon: s.plannedSynced ? Icons.auto_awesome : Icons.swap_horiz,
          color: s.plannedSynced ? scheme.primary : null,
          text: '${l10n.nextMix} (${s.plannedSynced ? l10n.mixSynced : l10n.mixSimple}): ${s.plannedMix}',
        );
      }
      return _Line(icon: Icons.hourglass_empty, text: next == null ? l10n.mixNoNext : l10n.automixWaitingAnalysis);
    }

    Widget track(String label, QueueItem? item) {
      if (item == null) return const SizedBox.shrink();
      final insight = s.insights[item.uid];
      final facts = insight == null
          ? l10n.mixAnalyzing
          : [
              if (insight.bpm != null) '${insight.bpm!.toStringAsFixed(insight.bpm! % 1 == 0 ? 0 : 1)} BPM',
              if (insight.camelot != null) '${insight.camelot}${insight.key != null ? ' (${insight.key})' : ''}',
              insight.reliable ? '${l10n.beatReliable} ✓' : '${l10n.beatUnreliable} ✗',
            ].join(' · ');
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary)),
            Text('${item.song.title} — ${item.song.displayArtist}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(facts,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: insight != null && !insight.reliable ? scheme.error : null)),
            if (insight?.detail != null && insight!.detail!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(insight.detail!,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
          ],
        ),
      );
    }

    final anyUnreliable = [current, next].any((i) => i != null && s.insights[i.uid] != null && !s.insights[i.uid]!.reliable);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              secondary: Icon(enabled ? Icons.auto_awesome : Icons.auto_awesome_outlined, color: enabled ? scheme.primary : null),
              title: Text('AutoMix', style: theme.textTheme.titleMedium),
              value: enabled,
              onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(automixEnabled: v)),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: status()),
            if (enabled) ...[
              track(l10n.mixNowPlaying, current),
              track(l10n.mixUpNext, next),
              if (anyUnreliable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(l10n.automixUnreliableHelp, style: theme.textTheme.bodySmall),
                ),
            ],
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(l10n.automixSettingsLink),
              subtitle: model == null ? null : Text('${l10n.analysisModel}: ${model == 'full' ? l10n.modelFull : l10n.modelSmall}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                context.push('/settings/automix');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
