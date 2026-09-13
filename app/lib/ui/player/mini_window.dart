import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../desktop/desktop_integration.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../widgets/cover_art.dart';

/// Conteúdo da janela no modo mini player (arraste para mover).
class MiniWindow extends ConsumerWidget {
  const MiniWindow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final (item, playing, pos, dur) = ref.watch(playerProvider.select((s) => (s.current, s.playing, s.position, s.duration)));
    final p = ref.read(playerProvider.notifier);
    final progress = dur.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
    return DragToMoveArea(
      child: Container(
        color: theme.colorScheme.surfaceContainer,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  CoverArt(coverArtId: item?.song.coverArt, size: 76),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item?.song.title ?? l10n.nothingPlaying,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                        Text(item?.song.displayArtist ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                        Row(
                          children: [
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.skip_previous), onPressed: p.previous),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                              onPressed: p.toggle,
                            ),
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.skip_next), onPressed: p.next),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.expand,
                    icon: const Icon(Icons.open_in_full),
                    onPressed: () => ref.read(miniModeProvider.notifier).exit(),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 3),
          ],
        ),
      ),
    );
  }
}
