import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/async_view.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import 'offline_page.dart';

class AlbumPage extends ConsumerWidget {
  const AlbumPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(albumProvider(id));
    return AsyncView(
      value: album,
      onRetry: () => ref.invalidate(albumProvider(id)),
      builder: (a) => _AlbumView(album: a),
    );
  }
}

class _AlbumView extends ConsumerWidget {
  const _AlbumView({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final player = ref.read(playerProvider.notifier);
    final songs = album.songs;
    final multiDisc = songs.map((s) => s.disc ?? 1).toSet().length > 1;
    final narrow = MediaQuery.sizeOf(context).width < 700;

    final meta = [
      if (album.year != null && album.year! > 0) '${album.year}',
      if (album.genres.isNotEmpty) album.genres.join(', ') else if (album.genre != null) album.genre!,
      l10n.songCount(songs.length),
      formatLongDuration(album.duration),
    ].join(' • ');

    final header = Padding(
      padding: const EdgeInsets.all(20),
      child: Flex(
        direction: narrow ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: narrow ? CrossAxisAlignment.center : CrossAxisAlignment.end,
        children: [
          Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: CoverArt(coverArtId: album.coverArt, size: narrow ? 220 : 200),
          ),
          const SizedBox(width: 24, height: 16),
          Flexible(
            child: Column(
              crossAxisAlignment: narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text(album.isCompilation ? l10n.compilation : l10n.album, style: theme.textTheme.labelMedium),
                Text(album.name, style: theme.textTheme.headlineMedium, textAlign: narrow ? TextAlign.center : null),
                const SizedBox(height: 4),
                InkWell(
                  onTap: album.artistId == null ? null : () => context.push('/artist/${album.artistId}'),
                  child: Text(album.displayArtist, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                ),
                const SizedBox(height: 4),
                Text(meta, style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l10n.play),
                      onPressed: () => player.playSongs(songs),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.shuffle),
                      label: Text(l10n.shuffle),
                      onPressed: () => player.playSongs(songs, shuffle: true),
                    ),
                    IconButton.outlined(
                      tooltip: l10n.playNext,
                      icon: const Icon(Icons.playlist_play),
                      onPressed: () => player.playNext(songs),
                    ),
                    IconButton.outlined(
                      tooltip: l10n.addToQueue,
                      icon: const Icon(Icons.queue_music),
                      onPressed: () => player.enqueue(songs),
                    ),
                    IconButton.outlined(
                      tooltip: l10n.addToPlaylist,
                      icon: const Icon(Icons.playlist_add),
                      onPressed: () => LibraryActions.addToPlaylist(context, ref, songs),
                    ),
                    OfflineButton(
                      type: 'album',
                      id: album.id,
                      name: album.name,
                      artist: album.displayArtist,
                      coverArt: album.coverArt,
                      songs: songs,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final rows = <Widget>[];
    int? lastDisc;
    for (var i = 0; i < songs.length; i++) {
      final s = songs[i];
      if (multiDisc && s.disc != lastDisc) {
        lastDisc = s.disc;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(l10n.disc(s.disc ?? 1), style: theme.textTheme.titleSmall),
        ));
      }
      rows.add(SongTile(
        song: s,
        number: s.track ?? i + 1,
        showCover: false,
        onTap: () => player.playFrom(songs, i),
      ));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [header, ...rows],
    );
  }
}
