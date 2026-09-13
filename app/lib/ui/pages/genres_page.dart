import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../widgets/async_view.dart';
import '../widgets/song_tile.dart';

class GenresPage extends ConsumerWidget {
  const GenresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final genres = ref.watch(genresProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(l10n.genres, style: Theme.of(context).textTheme.headlineMedium),
        ),
        Expanded(
          child: AsyncView(
            value: genres,
            onRetry: () => ref.invalidate(genresProvider),
            builder: (list) => ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final g = list[i];
                return ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: Text(g.name),
                  subtitle: Text('${l10n.albumCount(g.albumCount)} • ${l10n.songCount(g.songCount)}'),
                  onTap: () => context.push('/genre/${Uri.encodeComponent(g.name)}'),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class GenreSongsPage extends ConsumerWidget {
  const GenreSongsPage({super.key, required this.genre});
  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final songs = ref.watch(genreSongsProvider(genre));
    final player = ref.read(playerProvider.notifier);
    return AsyncView(
      value: songs,
      onRetry: () => ref.invalidate(genreSongsProvider(genre)),
      builder: (list) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Row(
              children: [
                Expanded(child: Text(genre, style: Theme.of(context).textTheme.headlineMedium)),
                OutlinedButton(onPressed: () => context.push('/albums?genre=${Uri.encodeComponent(genre)}'), child: Text(l10n.albums)),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.shuffle),
                  label: Text(l10n.shuffle),
                  onPressed: list.isEmpty ? null : () => player.playSongs(list, shuffle: true),
                ),
              ],
            ),
          ),
          for (var i = 0; i < list.length; i++)
            SongTile(song: list[i], showAlbum: true, onTap: () => player.playFrom(list, i)),
        ],
      ),
    );
  }
}

class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final songs = ref.watch(starredSongsProvider);
    final player = ref.read(playerProvider.notifier);
    return AsyncView(
      value: songs,
      onRetry: () => ref.invalidate(starredSongsProvider),
      builder: (list) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Row(
              children: [
                Expanded(child: Text(l10n.favorites, style: Theme.of(context).textTheme.headlineMedium)),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.play),
                  onPressed: list.isEmpty ? null : () => player.playSongs(list),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.shuffle),
                  label: Text(l10n.shuffle),
                  onPressed: list.isEmpty ? null : () => player.playSongs(list, shuffle: true),
                ),
              ],
            ),
          ),
          if (list.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(l10n.nothingHere))),
          for (var i = 0; i < list.length; i++)
            SongTile(song: list[i], showAlbum: true, onTap: () => player.playFrom(list, i)),
        ],
      ),
    );
  }
}
