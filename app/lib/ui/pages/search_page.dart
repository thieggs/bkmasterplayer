import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';
import '../widgets/cover_art.dart';
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
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: _query.trim().isEmpty
              ? Center(child: Text(l10n.searchEmptyHint))
              : AsyncView(
                  value: results,
                  builder: (r) {
                    if (r.isEmpty) return Center(child: Text(l10n.noResults));
                    return ListView(
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
                                        CoverArt(coverArtId: a.coverArt, size: 90, radius: 45, icon: Icons.person),
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
                            SongTile(song: r.songs[i], showAlbum: true, onTap: () => player.playSongs(r.songs, start: i)),
                        ],
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
