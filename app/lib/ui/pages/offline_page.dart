import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/offline_store.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';

/// Botão "baixar para ouvir offline" com progresso (álbum ou playlist).
class OfflineButton extends ConsumerStatefulWidget {
  const OfflineButton({
    super.key,
    required this.type,
    required this.id,
    required this.name,
    this.artist,
    this.coverArt,
    required this.songs,
  });
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
    // Coleções grandes (biblioteca inteira): conferir o disco com menos frequência.
    final big = (_collection?.songs.length ?? 0) > 500;
    _poll = Timer.periodic(Duration(seconds: big ? 15 : 2), (_) => _refresh());
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
          await ref
              .read(offlineProvider.notifier)
              .add(
                OfflineCollection(
                  type: widget.type,
                  id: widget.id,
                  name: widget.name,
                  artist: widget.artist,
                  coverArt: widget.coverArt,
                  songs: widget.songs,
                  account: account,
                ),
              );
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
        const _WholeLibraryTile(),
        const Divider(),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(l10n.nothingHere)),
          ),
        for (final c in list)
          ListTile(
            leading: CoverArt(
              coverArtId: c.coverArt,
              size: 48,
              icon: switch (c.type) {
                'album' => Icons.album,
                'library' => Icons.library_music,
                _ => Icons.queue_music,
              },
            ),
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
    // Lista preguiçosa: a "biblioteca inteira" pode ter milhares de músicas.
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: c.songs.length + 1,
      itemBuilder: (context, i) {
        if (i > 0) {
          final s = c.songs[i - 1];
          return SongTile(
            song: s,
            number: s.track ?? i,
            showCover: c.type != 'album',
            onTap: () => player.playFrom(c.songs, i - 1),
          );
        }
        return Padding(
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
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l10n.play),
                          onPressed: () => player.playSongs(c.songs),
                        ),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.shuffle),
                          label: Text(l10n.shuffle),
                          onPressed: () => player.playSongs(c.songs, shuffle: true),
                        ),
                        OfflineButton(
                          type: c.type,
                          id: c.id,
                          name: c.name,
                          artist: c.artist,
                          coverArt: c.coverArt,
                          songs: c.songs,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Baixar todas as músicas do servidor" (e depois "Baixar as novas").
class _WholeLibraryTile extends ConsumerStatefulWidget {
  const _WholeLibraryTile();
  @override
  ConsumerState<_WholeLibraryTile> createState() => _WholeLibraryTileState();
}

class _WholeLibraryTileState extends ConsumerState<_WholeLibraryTile> {
  static const id = 'library:all';
  bool _busy = false;
  int _read = 0;

  Future<void> _run() async {
    final l10n = context.l10n;
    final provider = ref.read(musicProvider);
    setState(() {
      _busy = true;
      _read = 0;
    });
    final all = <Song>[];
    try {
      for (var offset = 0; ; offset += 500) {
        final page = await provider.allSongs(count: 500, offset: offset);
        all.addAll(page);
        if (mounted) setState(() => _read = all.length);
        if (page.length < 500) break;
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
    if (mounted) setState(() => _busy = false);
    if (all.isEmpty || !mounted) return;
    final bytes = all.fold<int>(0, (n, s) => n + (s.size ?? 0));
    final mobile = (await Connectivity().checkConnectivity()).contains(ConnectivityResult.mobile);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.downloadAll),
        content: Text(
          [l10n.downloadAllConfirm(all.length, _size(bytes)), if (mobile) l10n.downloadAllMobileData].join('\n\n'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.download)),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(offlineProvider.notifier)
        .add(
          OfflineCollection(type: 'library', id: id, name: l10n.wholeLibrary, songs: all, account: provider.accountId),
        );
  }

  static String _size(int bytes) {
    if (bytes <= 0) return '?';
    final gb = bytes / (1024 * 1024 * 1024);
    return gb >= 1 ? '${gb.toStringAsFixed(1)} GB' : '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final has = ref.watch(offlineProvider.select((l) => l.any((c) => c.id == id)));
    return ListTile(
      leading: const Icon(Icons.cloud_download_outlined),
      title: Text(has ? l10n.wholeLibrary : l10n.downloadAll),
      subtitle: Text(_busy ? l10n.readingLibrary(_read) : l10n.downloadAllHint),
      trailing: _busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : FilledButton.tonal(onPressed: _run, child: Text(has ? l10n.downloadNew : l10n.download)),
    );
  }
}
