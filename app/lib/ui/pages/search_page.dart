import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/recent_searches.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';
import '../widgets/artist_photo.dart';
import '../widgets/song_tile.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initial = ''});
  final String initial;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final _controller = TextEditingController(text: widget.initial);
  late String _query = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A busca vale a pena guardar: Enter ou mexeu nos resultados.
  void _remember() => ref.read(recentSearchesProvider.notifier).add(_query);

  void _use(String q) {
    _controller.text = q;
    setState(() => _query = q);
  }

  Widget _recent(BuildContext context) {
    final l10n = context.l10n;
    final recent = ref.watch(recentSearchesProvider);
    if (recent.isEmpty) return Center(child: Text(l10n.searchEmptyHint));
    final list = ref.read(recentSearchesProvider.notifier);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            Expanded(child: SectionHeader(l10n.recentSearches)),
            TextButton(onPressed: list.clear, child: Text(l10n.clearRecentSearches)),
            const SizedBox(width: 8),
          ],
        ),
        for (final q in recent)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: l10n.removeRecentSearch,
              icon: const Icon(Icons.close),
              onPressed: () => list.remove(q),
            ),
            onTap: () => _use(q),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = ref.watch(searchProvider(_query));
    final player = ref.read(playerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.searchHint,
              border: const OutlineInputBorder(),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: (_) => _remember(),
          ),
        ),
        Expanded(
          child: _query.trim().isEmpty
              ? _recent(context)
              : AsyncView(
                  value: results,
                  builder: (r) {
                    if (r.isEmpty) return Center(child: Text(l10n.noResults));
                    // Tocou num resultado (ou rolou a lista): a busca entra nas recentes.
                    return Listener(
                      onPointerUp: (_) => _remember(),
                      child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        if (r.artists.isNotEmpty) ...[
                          SectionHeader(l10n.artists),
                          SizedBox(
                            height: 140,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              children: [
                                for (final a in r.artists)
                                  InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => context.push('/artist/${a.id}'),
                                    child: SizedBox(
                                      width: 110,
                                      child: Column(children: [
                                        ArtistPhoto(name: a.name, coverArt: a.coverArt, size: 90, radius: 45),
                                        const SizedBox(height: 6),
                                        Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ]),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (r.albums.isNotEmpty) ...[
                          SectionHeader(l10n.albums),
                          SizedBox(
                            height: 236,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              children: [for (final a in r.albums) AlbumCard(album: a)],
                            ),
                          ),
                        ],
                        if (r.songs.isNotEmpty) ...[
                          SectionHeader(l10n.songs),
                          for (var i = 0; i < r.songs.length; i++)
                            SongTile(song: r.songs[i], showAlbum: true, onTap: () => player.playFrom(r.songs, i)),
                        ],
                      ],
                    ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
