import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/offline_store.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';

/// Botão "baixar para ouvir offline" com progresso (álbum ou playlist).
class OfflineButton extends ConsumerStatefulWidget {
  const OfflineButton({super.key, required this.type, required this.id, required this.name, this.artist, this.coverArt, required this.songs});
  final String type;
  final String id;
  final String name;
  final String? artist;
  final String? coverArt;
  final List<Song> songs;

  @override
  ConsumerState<OfflineButton> createState() => _OfflineButtonState();
}

class _OfflineButtonState extends ConsumerState<OfflineButton> {
  Timer? _poll;
  int _done = 0;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  OfflineCollection? get _collection => ref.read(offlineProvider).where((c) => c.id == widget.id).firstOrNull;

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _refresh();
  }

  Future<void> _refresh() async {
    final c = _collection;
    if (c == null) return;
    final n = await ref.read(offlineProvider.notifier).downloadedCount(c);
    if (mounted) setState(() => _done = n);
    if (n >= c.songs.length) _poll?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Músicas do aparelho já estão offline.
    if (ref.watch(sessionProvider).value?.isLocal ?? false) return const SizedBox.shrink();
    final pinned = ref.watch(offlineProvider).any((c) => c.id == widget.id);
    final total = widget.songs.length;
    if (!pinned) {
      return IconButton.outlined(
        tooltip: l10n.downloadOffline,
        icon: const Icon(Icons.download_outlined),
        onPressed: () async {
          final account = ref.read(musicProvider).accountId;
          await ref.read(offlineProvider.notifier).add(OfflineCollection(
                type: widget.type,
                id: widget.id,
                name: widget.name,
                artist: widget.artist,
                coverArt: widget.coverArt,
                songs: widget.songs,
                account: account,
              ));
          _done = 0;
          _startPolling();
        },
      );
    }
    final complete = _done >= total;
    return Tooltip(
      message: complete ? l10n.availableOffline : l10n.downloadingCount(_done, total),
      child: IconButton.filledTonal(
        icon: complete
            ? const Icon(Icons.download_done)
            : SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, value: total == 0 ? null : _done / total),
              ),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.removeOfflineQuestion),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.delete)),
              ],
            ),
          );
          if (ok == true) await ref.read(offlineProvider.notifier).remove(widget.id);
        },
      ),
    );
  }
}

/// Lista das coleções baixadas (funciona sem servidor).
class OfflinePage extends ConsumerWidget {
  const OfflinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final list = ref.watch(offlineProvider);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(l10n.downloads, style: Theme.of(context).textTheme.headlineMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(l10n.downloadsHint, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(l10n.nothingHere))),
        for (final c in list)
          ListTile(
            leading: CoverArt(coverArtId: c.coverArt, size: 48, icon: c.type == 'album' ? Icons.album : Icons.queue_music),
            title: Text(c.name),
            subtitle: Text([if (c.artist != null) c.artist!, l10n.songCount(c.songs.length)].join(' • ')),
            trailing: IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => ref.read(playerProvider.notifier).playSongs(c.songs),
            ),
            onTap: () => context.push('/offline/${Uri.encodeComponent(c.id)}'),
          ),
      ],
    );
  }
}

class OfflineCollectionPage extends ConsumerWidget {
  const OfflineCollectionPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = ref.watch(offlineProvider).where((x) => x.id == id).firstOrNull;
    if (c == null) return Center(child: Text(l10n.nothingHere));
    final player = ref.read(playerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CoverArt(coverArtId: c.coverArt, size: 140),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
                    if (c.artist != null) Text(c.artist!),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: [
                      FilledButton.icon(icon: const Icon(Icons.play_arrow), label: Text(l10n.play), onPressed: () => player.playSongs(c.songs)),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.shuffle),
                        label: Text(l10n.shuffle),
                        onPressed: () => player.playSongs(c.songs, shuffle: true),
                      ),
                      OfflineButton(type: c.type, id: c.id, name: c.name, artist: c.artist, coverArt: c.coverArt, songs: c.songs),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < c.songs.length; i++)
          SongTile(song: c.songs[i], number: c.songs[i].track ?? i + 1, showCover: c.type != 'album', onTap: () => player.playFrom(c.songs, i)),
      ],
    );
  }
}
