import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/network.dart';
import '../../l10n/l10n.dart';
import '../../src/rust/api/engine.dart' as engine;

/// Tamanho legível (KB, MB, GB) com o separador decimal do idioma.
String formatBytes(BuildContext context, int bytes) {
  final f = NumberFormat('#,##0.0', Localizations.localeOf(context).toString());
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) return '${f.format(bytes / (1024 * 1024))} MB';
  return '${f.format(bytes / (1024 * 1024 * 1024))} GB';
}

String _eta(int secs) {
  if (secs < 60) return '$secs s';
  if (secs < 3600) return '${(secs / 60).round()} min';
  final h = secs ~/ 3600, m = (secs % 3600) ~/ 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Seletor "ao mesmo tempo" (1 a 8), ligado às configurações.
class DownloadParallelStepper extends ConsumerWidget {
  const DownloadParallelStepper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(settingsProvider.select((s) => s.downloadParallel));
    final set = ref.read(settingsProvider.notifier).update;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            // Área de toque de 48 dp (acessibilidade), mesmo com o ícone pequeno.
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: context.l10n.dlFewer,
            icon: const Icon(Icons.remove, size: 18),
            onPressed: n > 1 ? () => set((s) => s.copyWith(downloadParallel: n - 1)) : null,
          ),
          SizedBox(width: 20, child: Text('$n', textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
          IconButton(
            // Área de toque de 48 dp (acessibilidade), mesmo com o ícone pequeno.
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: context.l10n.dlMore,
            icon: const Icon(Icons.add, size: 18),
            onPressed: n < 8 ? () => set((s) => s.copyWith(downloadParallel: n + 1)) : null,
          ),
        ],
      ),
    );
  }
}

/// Gerenciador de downloads offline: progresso total e por música, pausar,
/// quantas ao mesmo tempo, tentar de novo as que falharam.
class DownloadManagerCard extends ConsumerStatefulWidget {
  const DownloadManagerCard({super.key});

  @override
  ConsumerState<DownloadManagerCard> createState() => _DownloadManagerCardState();
}

class _DownloadManagerCardState extends ConsumerState<DownloadManagerCard> {
  Timer? _timer;
  engine.OfflineStatus? _st;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _poll() {
    try {
      final st = engine.playerOfflineStatus();
      if (mounted) setState(() => _st = st);
    } catch (_) {
      // Motor ainda não iniciou.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    _poll();
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    if (st == null || st.total == 0) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finished = st.queued + st.active == 0;
    final gate = ref.watch(offlineGateProvider);
    final bytesTotal = st.bytesTotal;
    final fraction = bytesTotal > 0 ? st.bytesDone / bytesTotal : st.done / st.total;
    final info = <String>[
      if (bytesTotal > 0) l10n.dlBytes(formatBytes(context, st.bytesDone), formatBytes(context, bytesTotal)),
      if (st.active > 0 && st.speed > 0) '${formatBytes(context, st.speed)}/s',
      if (st.active > 0 && st.speed > 0 && bytesTotal > st.bytesDone) l10n.dlEta(_eta((bytesTotal - st.bytesDone) ~/ st.speed)),
      if (st.failed > 0) l10n.dlFailedCount(st.failed),
    ];
    final shownQueued = st.items.where((i) => i.state == engine.OfflineItemState.queued).length;

    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  finished
                      ? Icons.download_done
                      : gate.waitingWifi && !gate.userPaused
                          ? Icons.wifi_off
                          : (st.paused ? Icons.pause_circle_outline : Icons.downloading),
                  color: st.paused ? scheme.onSurfaceVariant : scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        finished
                            ? l10n.dlAllDone(st.done)
                            : gate.waitingWifi && !gate.userPaused
                                ? l10n.dlWaitingWifi
                                : (st.paused ? l10n.dlPaused : l10n.dlManagerTitle),
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(l10n.dlProgress(st.done, st.total), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (!finished)
                  FilledButton.tonalIcon(
                    icon: Icon(gate.userPaused ? Icons.play_arrow : Icons.pause, size: 18),
                    label: Text(gate.userPaused ? l10n.dlResume : l10n.dlPause),
                    onPressed: () => _run(() async => ref.read(offlineGateProvider.notifier).setUserPaused(!gate.userPaused)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: fraction.clamp(0.0, 1.0), borderRadius: BorderRadius.circular(4), minHeight: 6),
            if (info.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(info.join(' · '), style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.dlParallel, style: theme.textTheme.bodyMedium),
                const DownloadParallelStepper(),
                if (st.failed > 0)
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l10n.dlRetryFailed(st.failed)),
                    onPressed: () => _run(engine.playerOfflineRetryFailed),
                  ),
                if (st.done + st.failed > 0)
                  TextButton(onPressed: () => _run(engine.playerOfflineClearFinished), child: Text(l10n.dlClear)),
              ],
            ),
            if (st.items.isNotEmpty) const Divider(height: 16),
            for (final item in st.items.take(80)) _ItemRow(item: item),
            if (st.queued > shownQueued)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text(l10n.dlMoreQueued(st.queued - shownQueued), style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final engine.OfflineItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = item.state == engine.OfflineItemState.active;
    final failed = item.state == engine.OfflineItemState.failed;
    final fraction = item.total > 0 ? (item.bytes / item.total).clamp(0.0, 1.0) : null;
    final detail = active
        ? [
            if (fraction != null) '${(fraction * 100).round()}%',
            if (item.total > 0) l10n.dlBytes(formatBytes(context, item.bytes), formatBytes(context, item.total)),
          ].join(' · ')
        : failed
            ? '${l10n.dlFailed}: ${item.error ?? '?'}'
            : l10n.dlQueued;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              active ? Icons.downloading : (failed ? Icons.error_outline : Icons.schedule),
              size: 20,
              color: failed ? scheme.error : (active ? scheme.primary : scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                Text(
                  '${item.artist} · $detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: failed ? scheme.error : scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (active)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(value: fraction, borderRadius: BorderRadius.circular(3), minHeight: 3),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
