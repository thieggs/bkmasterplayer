import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../widgets/album_card.dart';

/// Grade de álbuns com ordenação e carregamento incremental.
class AlbumsPage extends ConsumerStatefulWidget {
  const AlbumsPage({super.key, this.initialSort, this.genre});
  final AlbumListType? initialSort;
  final String? genre;

  @override
  ConsumerState<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends ConsumerState<AlbumsPage> {
  static const _page = 60;
  late AlbumListType _sort = widget.genre != null ? AlbumListType.byGenre : (widget.initialSort ?? AlbumListType.alphabeticalByName);
  final _albums = <Album>[];
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _albums.clear();
      _done = false;
    }
    if (_done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final more = await ref.read(musicProvider).albumList(_sort, size: _page, offset: _albums.length, genre: widget.genre);
      setState(() {
        _albums.addAll(more);
        _done = more.length < _page || _sort == AlbumListType.random;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _label(AlbumListType t) {
    final l10n = context.l10n;
    return switch (t) {
      AlbumListType.alphabeticalByName => l10n.sortByName,
      AlbumListType.alphabeticalByArtist => l10n.sortByArtist,
      AlbumListType.newest => l10n.recentlyAdded,
      AlbumListType.recent => l10n.recentlyPlayed,
      AlbumListType.frequent => l10n.mostPlayed,
      AlbumListType.random => l10n.random,
      AlbumListType.starred => l10n.favorites,
      AlbumListType.highest => l10n.topRated,
      AlbumListType.byYear => l10n.sortByYear,
      AlbumListType.byGenre => widget.genre ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _load();
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.genre ?? l10n.albums, style: Theme.of(context).textTheme.headlineMedium),
                  ),
                  if (widget.genre == null)
                    DropdownButton<AlbumListType>(
                      value: _sort,
                      underline: const SizedBox(),
                      items: [
                        for (final t in AlbumListType.values.where((t) => t != AlbumListType.byGenre))
                          DropdownMenuItem(value: t, child: Text(_label(t))),
                      ],
                      onChanged: (t) {
                        if (t == null) return;
                        setState(() => _sort = t);
                        _load(reset: true);
                      },
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisExtent: 240,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => AlbumCard(album: _albums[i], width: 190),
                childCount: _albums.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : _error != null
                        ? Column(children: [Text(_error!), TextButton(onPressed: _load, child: Text(l10n.retry))])
                        : (_albums.isEmpty ? Text(l10n.nothingHere) : const SizedBox()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
