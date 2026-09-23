import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../data/recommend.dart';
import '../data/similar.dart';
import '../data/subsonic/subsonic_client.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../player/player_controller.dart';

/// Favoritos alterados nesta sessão (atualiza a UI na hora, sem recarregar listas).
class StarOverrides extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  void set(String id, bool starred) => state = {...state, id: starred};
}

final starOverridesProvider = NotifierProvider<StarOverrides, Map<String, bool>>(StarOverrides.new);

bool isSongStarred(WidgetRef ref, Song s) => ref.watch(starOverridesProvider)[s.id] ?? s.isStarred;

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, width: 420));
}

class LibraryActions {
  static PlayerController _player(WidgetRef ref) => ref.read(playerProvider.notifier);

  static Future<void> playAlbum(WidgetRef ref, String albumId, {bool shuffle = false, int start = 0}) async {
    final album = await ref.read(albumProvider(albumId).future);
    _player(ref).playSongs(album.songs, start: start, shuffle: shuffle);
  }

  static Future<void> enqueueAlbum(WidgetRef ref, String albumId, {bool next = false}) async {
    final album = await ref.read(albumProvider(albumId).future);
    next ? _player(ref).playNext(album.songs) : _player(ref).enqueue(album.songs);
  }

  static Future<void> toggleStar(BuildContext context, WidgetRef ref, Song song) async {
    final starred = !(ref.read(starOverridesProvider)[song.id] ?? song.isStarred);
    ref.read(starOverridesProvider.notifier).set(song.id, starred);
    try {
      await ref.read(musicProvider).setStarred(songId: song.id, starred: starred);
      ref.invalidate(starredSongsProvider);
    } on SubsonicException catch (e) {
      ref.read(starOverridesProvider.notifier).set(song.id, !starred);
      if (context.mounted) showSnack(context, e.message);
    }
  }

  /// Mix instantâneo (getSimilarSongs2 — no Navidrome+AudioMuse vem da análise sônica).
  static Future<void> instantMix(BuildContext context, WidgetRef ref, Song song) async {
    final l10n = context.l10n;
    showSnack(context, l10n.buildingMix);
    try {
      final s = ref.read(settingsProvider);
      final similar = await findSimilar(ref.read(musicProvider), song,
          count: 60, lastFm: s.lastFmForRadio ? ref.read(lastFmProvider) : null, local: ref.read(recommendProvider.notifier));
      if (similar.isEmpty) {
        if (context.mounted) showSnack(context, l10n.noSimilarSongs);
        return;
      }
      _player(ref).playSongs([song, ...similar.where((s) => s.id != song.id)]);
      _player(ref).setRadio(true);
    } on SubsonicException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  /// Rádio sônica: getSonicSimilarTracks (extensão sonicSimilarity / AudioMuse).
  static Future<void> sonicRadio(BuildContext context, WidgetRef ref, Song song) async {
    final l10n = context.l10n;
    try {
      final matches = await ref.read(musicProvider).sonicSimilar(song.id, count: 60);
      if (matches.isEmpty) {
        if (context.mounted) showSnack(context, l10n.noSimilarSongs);
        return;
      }
      _player(ref).playSongs([song, ...matches.map((m) => m.song).where((s) => s.id != song.id)]);
      _player(ref).setRadio(true);
    } on SubsonicException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  /// Caminho sônico entre duas músicas (findSonicPath).
  static Future<void> sonicPath(BuildContext context, WidgetRef ref, Song from) async {
    final to = await pickSong(context, ref, title: context.l10n.sonicPathPickTarget);
    if (to == null || !context.mounted) return;
    try {
      final path = await ref.read(musicProvider).sonicPath(from.id, to.id, count: 25);
      if (path.isEmpty) {
        if (context.mounted) showSnack(context, context.l10n.noSimilarSongs);
        return;
      }
      _player(ref).playSongs(path.map((m) => m.song).toList());
    } on SubsonicException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  /// Cria um link público no servidor (Navidrome: compartilhamento ligado) e
  /// copia para a área de transferência.
  static Future<void> share(BuildContext context, WidgetRef ref, List<String> ids, {String? description}) async {
    final l10n = context.l10n;
    final p = ref.read(musicProvider);
    try {
      final link = await p.createShare(ids, description: description);
      await Clipboard.setData(ClipboardData(text: link.toString()));
      if (context.mounted) showSnack(context, l10n.shareLinkCopied(link.toString()));
    } catch (e) {
      if (context.mounted) showSnack(context, l10n.shareUnavailable);
    }
  }

  static Future<void> addToPlaylist(BuildContext context, WidgetRef ref, List<Song> songs) async {
    final l10n = context.l10n;
    final playlists = await ref.read(playlistsProvider.future);
    if (!context.mounted) return;
    final choice = await showDialog<Object>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.addToPlaylist),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'new'),
            child: ListTile(leading: const Icon(Icons.add), title: Text(l10n.newPlaylist)),
          ),
          for (final p in playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: ListTile(leading: const Icon(Icons.queue_music), title: Text(p.name)),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final provider = ref.read(musicProvider);
    try {
      if (choice == 'new') {
        final name = await promptText(context, l10n.newPlaylist, l10n.playlistName);
        if (name == null || name.trim().isEmpty) return;
        await provider.createPlaylist(name.trim(), songIds: songs.map((s) => s.id).toList());
      } else if (choice is Playlist) {
        await provider.addToPlaylist(choice.id, songs.map((s) => s.id).toList());
        ref.invalidate(playlistProvider(choice.id));
      }
      ref.invalidate(playlistsProvider);
      if (context.mounted) showSnack(context, l10n.addedToPlaylist);
    } on SubsonicException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  static Future<String?> promptText(BuildContext context, String title, String label, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(context.l10n.ok)),
        ],
      ),
    );
  }

  /// Diálogo de busca para escolher uma música.
  static Future<Song?> pickSong(BuildContext context, WidgetRef ref, {required String title}) {
    return showDialog<Song>(context: context, builder: (ctx) => _SongPicker(title: title));
  }
}

class _SongPicker extends ConsumerStatefulWidget {
  const _SongPicker({required this.title});
  final String title;

  @override
  ConsumerState<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends ConsumerState<_SongPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchProvider(_query));
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.l10n.searchHint),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: results.when(
                data: (r) => ListView(
                  children: [
                    for (final s in r.songs)
                      ListTile(
                        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(s.displayArtist, maxLines: 1),
                        onTap: () => Navigator.pop(context, s),
                      ),
                  ],
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.cancel))],
    );
  }
}

/// Menu de contexto de uma música (clique direito / toque longo / botão ⋮).
Future<void> showSongMenu(BuildContext context, WidgetRef ref, Song song, {Offset? position, Widget? header}) async {
  final l10n = context.l10n;
  final info = ref.read(serverInfoProvider);
  final player = ref.read(playerProvider.notifier);
  final starred = ref.read(starOverridesProvider)[song.id] ?? song.isStarred;
  final items = <(IconData, String, VoidCallback)>[
    (Icons.play_arrow, l10n.playNow, () => player.playSongs([song])),
    (Icons.playlist_play, l10n.playNext, () => player.playNext([song])),
    (Icons.queue_music, l10n.addToQueue, () => player.enqueue([song])),
    (Icons.auto_awesome, l10n.instantMix, () => LibraryActions.instantMix(context, ref, song)),
    (Icons.auto_awesome_motion, l10n.djModeFrom, () => ref.read(playerProvider.notifier).startDj(song)),
    if (info?.sonicSimilarity ?? false) ...[
      (Icons.graphic_eq, l10n.sonicRadio, () => LibraryActions.sonicRadio(context, ref, song)),
      (Icons.route, l10n.sonicPath, () => LibraryActions.sonicPath(context, ref, song)),
    ],
    (starred ? Icons.favorite : Icons.favorite_border, starred ? l10n.unfavorite : l10n.favorite,
        () => LibraryActions.toggleStar(context, ref, song)),
    (Icons.playlist_add, l10n.addToPlaylist, () => LibraryActions.addToPlaylist(context, ref, [song])),
    if (!(ref.read(sessionProvider).value?.isLocal ?? true))
      (Icons.share_outlined, l10n.shareLink, () => LibraryActions.share(context, ref, [song.id], description: song.title)),
    if (song.albumId != null) (Icons.album, l10n.goToAlbum, () => context.push('/album/${song.albumId}')),
    if (song.artistId != null) (Icons.person, l10n.goToArtist, () => context.push('/artist/${song.artistId}')),
  ];

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final pos = position ?? overlay.size.center(Offset.zero);
  final selected = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(pos & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      for (var i = 0; i < items.length; i++)
        PopupMenuItem(
          value: i,
          height: 40,
          child: Row(children: [Icon(items[i].$1, size: 20), const SizedBox(width: 12), Text(items[i].$2)]),
        ),
    ],
  );
  if (selected != null) items[selected].$3();
}
