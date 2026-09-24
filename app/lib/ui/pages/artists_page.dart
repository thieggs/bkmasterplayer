import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/album_card.dart';
import '../widgets/async_view.dart';
import '../widgets/artist_photo.dart';
import '../widgets/song_tile.dart';

class ArtistsPage extends ConsumerStatefulWidget {
  const ArtistsPage({super.key});

  @override
  ConsumerState<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistsPageState extends ConsumerState<ArtistsPage> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final artists = ref.watch(artistsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Expanded(child: Text(l10n.artists, style: Theme.of(context).textTheme.headlineMedium)),
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.filter_list),
                    hintText: l10n.filter,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _filter = v.toLowerCase()),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView(
            value: artists,
            onRetry: () => ref.invalidate(artistsProvider),
            builder: (list) {
              final shown = _filter.isEmpty ? list : list.where((a) => a.name.toLowerCase().contains(_filter)).toList();
              return ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) => _ArtistTile(artist: shown[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({required this.artist});
  final Artist artist;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ArtistPhoto(name: artist.name, coverArt: artist.coverArt, size: 44, radius: 22),
      title: Text(artist.name),
      subtitle: artist.albumCount != null ? Text(context.l10n.albumCount(artist.albumCount!)) : null,
      onTap: () => context.push('/artist/${artist.id}'),
    );
  }
}

class ArtistPage extends ConsumerWidget {
  const ArtistPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artist = ref.watch(artistProvider(id));
    return AsyncView(
      value: artist,
      onRetry: () => ref.invalidate(artistProvider(id)),
      builder: (a) => _ArtistView(artist: a),
    );
  }
}

class _ArtistView extends ConsumerWidget {
  const _ArtistView({required this.artist});
  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final info = ref.watch(artistInfoProvider(artist.id)).value;
    final top = ref.watch(topSongsProvider(artist.name)).value ?? const [];
    final player = ref.read(playerProvider.notifier);
    final albums = [...artist.albums]..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    final bio = info?.biography?.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              ArtistPhoto(name: artist.name, coverArt: artist.coverArt, size: 140, radius: 70),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.artist, style: theme.textTheme.labelMedium),
                    Text(artist.name, style: theme.textTheme.headlineMedium),
                    Text(l10n.albumCount(artist.albums.length), style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l10n.play),
                          onPressed: () async {
                            final songs = <Song>[];
                            for (final a in albums.reversed) {
                              songs.addAll((await ref.read(albumProvider(a.id).future)).songs);
                            }
                            player.playSongs(songs);
                          },
                        ),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.shuffle),
                          label: Text(l10n.shuffle),
                          onPressed: () async {
                            final songs = <Song>[];
                            for (final a in albums) {
                              songs.addAll((await ref.read(albumProvider(a.id).future)).songs);
                            }
                            player.playSongs(songs, shuffle: true);
                          },
                        ),
                        if (top.isNotEmpty)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.auto_awesome),
                            label: Text(l10n.artistRadio),
                            onPressed: () => LibraryActions.instantMix(context, ref, top.first),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (bio != null && bio.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(bio, maxLines: 4, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
          ),
        // Biografia/parecidos do Last.fm (direto ou pelo servidor): o crédito com
        // link para a página do artista é exigido pelos termos da API.
        if (info?.lastFmUrl != null && (bio?.isNotEmpty == true || info!.similarArtists.isNotEmpty))
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('${l10n.lastFmCredit} · ${l10n.openOnLastFm}'),
                onPressed: () => launchUrl(Uri.parse(info!.lastFmUrl!), mode: LaunchMode.externalApplication),
              ),
            ),
          ),
        if (top.isNotEmpty) ...[
          SectionHeader(l10n.topSongs),
          for (var i = 0; i < top.length && i < 10; i++)
            SongTile(song: top[i], showAlbum: true, onTap: () => player.playFrom(top, i)),
        ],
        SectionHeader(l10n.albums),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Wrap(children: [for (final a in albums) AlbumCard(album: a)]),
        ),
        if (info != null && info.similarArtists.isNotEmpty) ...[
          SectionHeader(l10n.similarArtists),
          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in info.similarArtists)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/artist/${s.id}'),
                    child: SizedBox(
                      width: 120,
                      child: Column(
                        children: [
                          ArtistPhoto(name: s.name, coverArt: s.coverArt, size: 100, radius: 50),
                          const SizedBox(height: 6),
                          Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
