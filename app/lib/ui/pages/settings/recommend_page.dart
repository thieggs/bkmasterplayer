import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/recommend.dart';
import '../../../l10n/l10n.dart';
import '../../recommend_style_ui.dart';
import 'common.dart';

/// Tela "Recomendações" (`/settings/recommend`).
///
/// Não é o AutoMix: o AutoMix costura uma música na outra, isto aqui decide
/// **qual** música vem. Quem usa isso é o rádio da tela do player, o mix
/// instantâneo e a fila infinita.
class RecommendSettingsPage extends StatelessWidget {
  const RecommendSettingsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      SettingsScaffold(title: context.l10n.recommend, children: const [RecommendSection()]);
}

/// Como o app escolhe as "parecidas", e guardar a análise do AudioMuse no
/// aparelho para isso funcionar sem internet.
class RecommendSection extends ConsumerWidget {
  const RecommendSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final escolhido = RecommendStyle.parse(s.recommendStyle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(l10n.recommendHint, style: theme.textTheme.bodyMedium),
        ),
        RadioGroup<RecommendStyle>(
          groupValue: escolhido,
          onChanged: (v) => set((x) => x.copyWith(recommendStyle: (v ?? RecommendStyle.sound).id)),
          child: Column(
            children: [
              for (final e in RecommendStyle.values)
                RadioListTile<RecommendStyle>(
                  value: e,
                  secondary: Icon(e.icon),
                  title: Text(e.label(l10n)),
                  subtitle: Text(e.hint(l10n), style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
        const Divider(height: 24),
        const RecommendOfflineTile(),
      ],
    );
  }
}

/// Guardar os vetores do AudioMuse no aparelho, com o andamento da baixa.
class RecommendOfflineTile extends ConsumerWidget {
  const RecommendOfflineTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final rec = ref.watch(recommendProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.download_for_offline_outlined),
          title: Text(l10n.recommendOffline),
          subtitle: Text(l10n.recommendOfflineHint, style: theme.textTheme.bodySmall),
          value: s.recommendOffline,
          onChanged: s.analysisServer == null ? null : (v) => set((x) => x.copyWith(recommendOffline: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.analysisServer == null)
                Text(l10n.recommendNoServer, style: theme.textTheme.bodySmall)
              else if (rec.downloading) ...[
                Text(l10n.recommendDownloading, style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: rec.progress >= 0 ? rec.progress : null),
              ] else if (rec.error != null)
                Text(rec.error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))
              else if (rec.ready) ...[
                Text(l10n.recommendReady(rec.songs),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                TextButton(
                  onPressed: () => ref.read(recommendProvider.notifier).sync(force: true),
                  child: Text(l10n.recommendUpdate),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
