import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/async_view.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import 'offline_page.dart';

class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final playlists = ref.watch(playlistsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Expanded(child: Text(l10n.playlists, style: Theme.of(context).textTheme.headlineMedium)),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: Text(l10n.newPlaylist),
                onPressed: () async {
                  final name = await LibraryActions.promptText(context, l10n.newPlaylist, l10n.playlistName);
                  if (name == null || name.trim().isEmpty) return;
                  await ref.read(musicProvider).createPlaylist(name.trim());
                  ref.invalidate(playlistsProvider);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView(
            value: playlists,
            onRetry: () => ref.invalidate(playlistsProvider),
            builder: (list) => list.isEmpty
                ? Center(child: Text(l10n.nothingHere))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return ListTile(
                        leading: CoverArt(coverArtId: p.coverArt, size: 48, icon: Icons.queue_music),
                        title: Text(p.name),
                        subtitle: Text([l10n.songCount(p.songCount), formatLongDuration(p.duration)].join(' • ')),
                        onTap: () => context.push('/playlist/${p.id}'),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class PlaylistPage extends ConsumerWidget {
  const PlaylistPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final playlist = ref.watch(playlistProvider(id));
    final player = ref.read(playerProvider.notifier);
    return AsyncView(
      value: playlist,
      onRetry: () => ref.invalidate(playlistProvider(id)),
      builder: (p) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CoverArt(coverArtId: p.coverArt, size: 160, icon: Icons.queue_music),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.playlist, style: theme.textTheme.labelMedium),
                      Text(p.name, style: theme.textTheme.headlineMedium),
                      if (p.comment != null) Text(p.comment!, style: theme.textTheme.bodyMedium),
                      Text([l10n.songCount(p.songs.length), formatLongDuration(p.duration)].join(' • '),
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            icon: const Icon(Icons.play_arrow),
                            label: Text(l10n.play),
                            onPressed: p.songs.isEmpty ? null : () => player.playSongs(p.songs),
                          ),
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.shuffle),
                            label: Text(l10n.shuffle),
                            onPressed: p.songs.isEmpty ? null : () => player.playSongs(p.songs, shuffle: true),
                          ),
                          OfflineButton(type: 'playlist', id: p.id, name: p.name, coverArt: p.coverArt, songs: p.songs),
                          IconButton.outlined(
                            tooltip: l10n.rename,
                            icon: const Icon(Icons.edit),
                            onPressed: () async {
                              final name = await LibraryActions.promptText(context, l10n.rename, l10n.playlistName, initial: p.name);
                              if (name == null || name.trim().isEmpty) return;
                              await ref.read(musicProvider).renamePlaylist(p.id, name.trim());
                              ref.invalidate(playlistProvider(id));
                              ref.invalidate(playlistsProvider);
                            },
                          ),
                          IconButton.outlined(
                            tooltip: l10n.delete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(l10n.deletePlaylistQuestion(p.name)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
                                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.delete)),
                                  ],
                                ),
                              );
                              if (ok != true) return;
                              await ref.read(musicProvider).deletePlaylist(p.id);
                              ref.invalidate(playlistsProvider);
                              if (context.mounted) context.pop();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < p.songs.length; i++)
            SongTile(
              song: p.songs[i],
              showAlbum: true,
              onTap: () => player.playFrom(p.songs, i),
              trailing: IconButton(
                tooltip: l10n.removeFromPlaylist,
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () async {
                  await ref.read(musicProvider).removeFromPlaylist(p.id, [i]);
                  ref.invalidate(playlistProvider(id));
                },
              ),
            ),
        ],
      ),
    );
  }
}
