import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../domain/models.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import 'cover_art.dart';

/// Linha de música usada em álbuns, playlists, buscas e na fila.
class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.number,
    this.showCover = true,
    this.showAlbum = false,
    this.dense = false,
    this.trailing,
  });

  final Song song;
  final VoidCallback onTap;
  final int? number;
  final bool showCover;
  final bool showAlbum;
  final bool dense;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = ref.watch(playerProvider.select((s) => s.current?.song.id)) == song.id;
    final playing = ref.watch(playerProvider.select((s) => s.playing));
    final starred = isSongStarred(ref, song);
    final color = current ? theme.colorScheme.primary : null;
    final subtitle = [song.displayArtist, if (showAlbum && song.album != null) song.album!].join(' • ');

    Widget leading;
    if (number != null && !showCover) {
      leading = SizedBox(
        width: 32,
        child: current
            ? Icon(playing ? Icons.graphic_eq : Icons.pause, size: 18, color: color)
            : Text('$number', textAlign: TextAlign.right, style: theme.textTheme.bodySmall),
      );
    } else {
      leading = CoverArt(coverArtId: song.coverArt, size: dense ? 36 : 44, radius: 4, icon: Icons.music_note);
    }

    return GestureDetector(
      onSecondaryTapUp: (d) => showSongMenu(context, ref, song, position: d.globalPosition),
      onLongPressStart: (d) => showSongMenu(context, ref, song, position: d.globalPosition),
      child: ListTile(
        dense: dense,
        leading: leading,
        title: Text(song.title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: current ? FontWeight.w600 : null)),
        subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
        trailing: trailing ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (starred) Icon(Icons.favorite, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(formatDuration(song.duration), style: theme.textTheme.bodySmall),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    final pos = box?.localToGlobal(box.size.centerRight(Offset.zero));
                    showSongMenu(context, ref, song, position: pos);
                  },
                ),
              ],
            ),
      ),
    );
  }
}
