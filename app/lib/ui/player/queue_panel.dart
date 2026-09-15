import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/cover_art.dart';
import '../widgets/follow_playing.dart';

class QueuePanel extends ConsumerStatefulWidget {
  const QueuePanel({super.key});

  @override
  ConsumerState<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends ConsumerState<QueuePanel> {
  /// A fila acompanha a música que está tocando (e já abre mostrando ela).
  final _follow = PlayingFollower();

  @override
  void dispose() {
    _follow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(playerProvider.select((s) => (s.queue, s.index, s.radio, s.dj)));
    final (queue, index, radio, dj) = s;
    final p = ref.read(playerProvider.notifier);
    _follow.update(
      queue.isEmpty || index < 0 ? null : index,
      showOnOpen: true,
      scroll: (i, {required animate}) => _follow.scrollToFixedRow(i, queue.length, animate: animate),
    );
    final upcoming = queue.length - index - 1;
    final remaining = queue
        .skip(index + 1)
        .fold<Duration>(Duration.zero, (acc, q) => acc + (q.song.duration ?? Duration.zero));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text(l10n.queue, style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: dj ? l10n.djModeOn : l10n.djModeOff,
                isSelected: dj,
                icon: const Icon(Icons.auto_awesome_motion),
                onPressed: () => p.setDj(!dj),
              ),
              IconButton(
                tooltip: radio ? l10n.radioOn : l10n.radioOff,
                isSelected: radio,
                icon: const Icon(Icons.all_inclusive),
                onPressed: p.toggleRadio,
              ),
              if (upcoming > 0)
                TextButton(onPressed: p.clearUpcoming, child: Text(l10n.clear)),
            ],
          ),
        ),
        if (upcoming > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.queueSummary(upcoming, formatLongDuration(remaining)),
                style: theme.textTheme.bodySmall),
          ),
        const Divider(),
        Expanded(
          child: queue.isEmpty
              ? Center(child: Text(l10n.queueEmpty, style: theme.textTheme.bodyMedium))
              : NotificationListener<ScrollNotification>(
                  onNotification: _follow.onNotification,
                  child: ReorderableListView.builder(
                    scrollController: _follow.controller,
                    padding: EdgeInsets.zero,
                    buildDefaultDragHandles: false,
                    // Linhas todas da mesma altura: a posição da atual sai da conta.
                    prototypeItem: _row(context, queue.first, 0, current: false, past: false, key: const ValueKey('__prototype__')),
                    itemCount: queue.length,
                    onReorder: (from, to) => p.move(from, to > from ? to - 1 : to),
                    itemBuilder: (context, i) => _row(context, queue[i], i, current: i == index, past: i < index),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, QueueItem item, int i, {required bool current, required bool past, Key? key}) {
    final theme = Theme.of(context);
    final p = ref.read(playerProvider.notifier);
    return Opacity(
      key: key ?? ValueKey(item.uid),
      opacity: past ? 0.5 : 1,
      child: GestureDetector(
        onSecondaryTapUp: (d) => showSongMenu(context, ref, item.song, position: d.globalPosition),
        child: ListTile(
          dense: true,
          selected: current,
          leading: CoverArt(coverArtId: item.song.coverArt, size: 36, icon: Icons.music_note),
          title: Text(item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(item.song.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => p.jumpTo(i),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatDuration(item.song.duration), style: theme.textTheme.bodySmall),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => p.removeAt(i),
              ),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_handle, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
