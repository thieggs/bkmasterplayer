import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider).value;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(albumListProvider),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.home, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.shuffle),
                  label: Text(l10n.shuffleLibrary),
                  onPressed: () async {
                    final songs = await ref.read(musicProvider).randomSongs(size: 100);
                    ref.read(playerProvider.notifier).playSongs(songs);
                  },
                ),
                if (session?.offlineReason != null)
                  ActionChip(
                    avatar: const Icon(Icons.cloud_off, size: 18),
                    label: Text(l10n.offline),
                    onPressed: () => ref.read(sessionProvider.notifier).retry(),
                  ),
              ],
            ),
          ),
          for (final section in ref.watch(uiPrefsProvider.select((p) => p.homeSections)))
            switch (section) {
              'newest' => _AlbumRow(title: l10n.recentlyAdded, type: AlbumListType.newest),
              'recent' => _AlbumRow(title: l10n.recentlyPlayed, type: AlbumListType.recent),
              'frequent' => _AlbumRow(title: l10n.mostPlayed, type: AlbumListType.frequent),
              'random' => _AlbumRow(title: l10n.discover, type: AlbumListType.random),
              'starred' => _AlbumRow(title: l10n.favorites, type: AlbumListType.starred),
              'highest' => _AlbumRow(title: l10n.topRated, type: AlbumListType.highest),
              _ => const SizedBox.shrink(),
            },
        ],
      ),
    );
  }
}

class _AlbumRow extends ConsumerWidget {
  const _AlbumRow({required this.title, required this.type});
  final String title;
  final AlbumListType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumListProvider((type: type, size: 20, genre: null)));
    final data = albums.value;
    if (data != null && data.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          action: TextButton(
            onPressed: () => context.push('/albums?sort=${type.name}'),
            child: Text(context.l10n.seeAll),
          ),
        ),
        SizedBox(
          height: ref.watch(uiPrefsProvider.select((p) => p.cardWidth)) + 66,
          child: AsyncView(
            value: albums,
            onRetry: () => ref.invalidate(albumListProvider),
            builder: (list) => ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: list.length,
              itemBuilder: (_, i) => AlbumCard(album: list[i]),
            ),
          ),
        ),
      ],
    );
  }
}
