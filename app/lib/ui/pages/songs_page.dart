import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../widgets/song_tile.dart';

/// Todas as músicas da biblioteca, carregadas em páginas conforme rola.
class SongsPage extends ConsumerStatefulWidget {
  const SongsPage({super.key});

  @override
  ConsumerState<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends ConsumerState<SongsPage> {
  static const _page = 200;
  final _songs = <Song>[];
  final _scroll = ScrollController();
  final _filter = TextEditingController();
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 1500) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(musicProvider).allSongs(count: _page, offset: _songs.length);
      if (!mounted) return;
      setState(() {
        _songs.addAll(page);
        _done = page.length < _page;
        _loading = false;
      });
      // Tela grande: se ainda não dá para rolar, busca a próxima página.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && _scroll.position.maxScrollExtent == 0) _loadMore();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  /// Carrega o resto da biblioteca (para tocar/embaralhar tudo).
  Future<List<Song>> _loadAll() async {
    while (!_done && _error == null) {
      await _loadMore();
    }
    return _songs;
  }

  List<Song> get _visible {
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty) return _songs;
    return _songs
        .where((s) => s.title.toLowerCase().contains(q) || s.displayArtist.toLowerCase().contains(q) || (s.album ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final player = ref.read(playerProvider.notifier);
    final list = _visible;
    return ListView.builder(
      controller: _scroll,
      itemCount: list.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l10n.songs, style: Theme.of(context).textTheme.headlineMedium)),
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l10n.play),
                      onPressed: _songs.isEmpty ? null : () async => player.playSongs(_filter.text.isEmpty ? await _loadAll() : list),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.shuffle),
                      label: Text(l10n.shuffle),
                      onPressed: _songs.isEmpty ? null : () async => player.playSongs(_filter.text.isEmpty ? await _loadAll() : list, shuffle: true),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.filter_list),
                    hintText: l10n.filterSongs,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _done ? l10n.songCount(_songs.length) : '${l10n.songCount(_songs.length)}…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        }
        if (i == list.length + 1) {
          if (_error != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [Text(_error!), TextButton(onPressed: _loadMore, child: Text(l10n.retry))]),
            );
          }
          if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
          if (list.isEmpty && _done) return Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(l10n.nothingHere)));
          return const SizedBox(height: 24);
        }
        final idx = i - 1;
        return SongTile(song: list[idx], showAlbum: true, onTap: () => player.playFrom(list, idx));
      },
    );
  }
}
