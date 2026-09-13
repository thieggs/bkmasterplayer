import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/cover_art.dart';

class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(playerProvider.select((s) => (s.queue, s.index, s.radio)));
    final (queue, index, radio) = s;
    final p = ref.read(playerProvider.notifier);
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
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: queue.length,
                  onReorder: (from, to) => p.move(from, to > from ? to - 1 : to),
                  itemBuilder: (context, i) {
                    final item = queue[i];
                    final current = i == index;
                    final past = i < index;
                    return Opacity(
                      key: ValueKey(item.uid),
                      opacity: past ? 0.5 : 1,
                      child: GestureDetector(
                        onSecondaryTapUp: (d) => showSongMenu(context, ref, item.song, position: d.globalPosition),
                        child: ListTile(
                          dense: true,
                          selected: current,
                          leading: CoverArt(coverArtId: item.song.coverArt, size: 36, radius: 4, icon: Icons.music_note),
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
                  },
                ),
        ),
      ],
    );
  }
}
