import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';

import '../domain/models.dart';
import '../domain/music_provider.dart';

/// Navegação no carro (Android Auto hoje; a mesma árvore serve ao CarPlay).
///
/// IDs: abas `tab:*`; pastas `album:<id>`, `playlist:<id>`, `list:starred`,
/// `list:search`; música `<pasta>|<índice>` (toca a pasta a partir dela);
/// ações `do:*` (o handler de mídia decide o que fazer).
class AutoBrowser {
  AutoBrowser({required this.provider, required this.artDir, required this.pt, this.artAuthority = defaultArtAuthority});

  static const defaultArtAuthority = 'io.github.playermusica.player_musica.art';

  // Dicas de layout do Android Auto (lista = 1, grade = 2).
  static const contentStyleSupported = 'android.media.browse.CONTENT_STYLE_SUPPORTED';
  static const browsableHint = 'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
  static const playableHint = 'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
  static const searchSupported = 'android.media.browse.SEARCH_SUPPORTED';

  /// Extras da raiz para o [AudioServiceConfig].
  static const rootExtras = <String, dynamic>{
    contentStyleSupported: true,
    browsableHint: 1,
    playableHint: 1,
    searchSupported: true,
  };

  /// Conta atual (null = sem login).
  final MusicProvider? Function() provider;

  /// Onde ficam as fontes das capas que o [BkArtProvider] do Android serve.
  final String artDir;
  final bool pt;
  final String artAuthority;

  /// Músicas de cada pasta aberta, para tocar a partir de uma delas.
  final _lists = <String, List<Song>>{};

  String _t(String pt, String en) => this.pt ? pt : en;

  List<MediaItem> root() => [
        _folder('tab:home', _t('Início', 'Home')),
        _folder('tab:recent', _t('Recentes', 'Recent'), grid: true),
        _folder('tab:albums', _t('Álbuns', 'Albums'), grid: true),
        _folder('tab:playlists', 'Playlists'),
      ];

  /// Filhos de uma pasta. [current] é a música tocando (para as ações dela).
  Future<List<MediaItem>> children(String parent, {Song? current}) async {
    if (parent == AudioService.browsableRootId) return root();
    final p = provider();
    if (p == null) return const [];
    switch (parent) {
      case 'tab:home':
        return [
          _action('do:shuffle', _t('Tocar aleatórias', 'Shuffle all')),
          if (current != null) _action('do:dj', _t('Modo DJ a partir desta', 'DJ mode from this song'), subtitle: current.title),
          if (current != null) _action('do:mix', _t('Mix da música atual', 'Mix from this song'), subtitle: current.title),
          _folder('list:starred', _t('Favoritas', 'Favorites')),
          _folder('tab:frequent', _t('Mais tocados', 'Most played'), grid: true),
          _folder('tab:random', _t('Álbuns aleatórios', 'Random albums'), grid: true),
        ];
      case 'tab:recent':
        return _albums(await p.albumList(AlbumListType.recent, size: 40));
      case 'tab:albums':
        return _albums(await p.albumList(AlbumListType.newest, size: 60));
      case 'tab:frequent':
        return _albums(await p.albumList(AlbumListType.frequent, size: 40));
      case 'tab:random':
        return _albums(await p.albumList(AlbumListType.random, size: 40));
      case 'tab:playlists':
        return [
          for (final pl in await p.playlists())
            _folder('playlist:${pl.id}', pl.name,
                subtitle: _t('${pl.songCount} músicas', '${pl.songCount} songs'), art: art(pl.coverArt)),
        ];
    }
    final songs = await _load(parent);
    return songs == null ? const [] : _songs(parent, songs);
  }

  /// Busca pela tela do carro: músicas (tocáveis) e álbuns (pastas).
  Future<List<MediaItem>> search(String query) async {
    final p = provider();
    if (p == null || query.trim().isEmpty) return const [];
    final r = await p.search(query, artistCount: 0, albumCount: 10, songCount: 30);
    _lists['list:search'] = r.songs;
    return [..._songs('list:search', r.songs), ..._albums(r.albums)];
  }

  /// Músicas a tocar para um ID `<pasta>|<índice>`, e de qual começar.
  Future<(List<Song>, int)?> resolve(String mediaId) async {
    final bar = mediaId.lastIndexOf('|');
    if (bar < 0) return null;
    final folder = mediaId.substring(0, bar);
    final i = int.tryParse(mediaId.substring(bar + 1));
    final songs = _lists[folder] ?? await _load(folder);
    if (i == null || songs == null || songs.isEmpty) return null;
    return (songs, i.clamp(0, songs.length - 1));
  }

  /// Pedido de voz ("tocar X no BKplayer"). O Android manda o foco (música,
  /// álbum, artista) e os campos quando entende; senão, só o texto.
  Future<List<Song>> voice(String query, Map<String, dynamic>? extras) async {
    final p = provider();
    if (p == null) return const [];
    final q = query.trim();
    if (q.isEmpty) return p.randomSongs(size: 100);
    final focus = extras?['android.intent.extra.focus'] as String?;
    final artist = extras?['android.intent.extra.artist'] as String?;
    final album = extras?['android.intent.extra.album'] as String?;
    if (focus == 'vnd.android.cursor.item/artist' && (artist ?? q).isNotEmpty) {
      final top = await p.topSongs(artist ?? q, count: 50);
      if (top.isNotEmpty) return top;
    }
    if (focus == 'vnd.android.cursor.item/album' && (album ?? q).isNotEmpty) {
      final r = await p.search(album ?? q, artistCount: 0, albumCount: 5, songCount: 0);
      if (r.albums.isNotEmpty) return (await p.album(r.albums.first.id)).songs;
    }
    final r = await p.search(q, artistCount: 3, albumCount: 5, songCount: 50);
    if (r.songs.isNotEmpty) return r.songs;
    if (r.albums.isNotEmpty) return (await p.album(r.albums.first.id)).songs;
    if (r.artists.isNotEmpty) return p.topSongs(r.artists.first.name, count: 50);
    return const [];
  }

  Future<List<Song>?> _load(String folder) async {
    final p = provider();
    if (p == null) return null;
    final List<Song> songs;
    if (folder.startsWith('album:')) {
      songs = (await p.album(folder.substring(6))).songs;
    } else if (folder.startsWith('playlist:')) {
      songs = (await p.playlist(folder.substring(9))).songs;
    } else if (folder == 'list:starred') {
      songs = await p.starredSongs();
    } else {
      return null;
    }
    _lists[folder] = songs;
    return songs;
  }

  List<MediaItem> _albums(List<Album> albums) => [
        for (final a in albums)
          _folder('album:${a.id}', a.name, subtitle: a.artist, art: art(a.coverArt)),
      ];

  List<MediaItem> _songs(String folder, List<Song> songs) => [
        for (final (i, s) in songs.indexed)
          MediaItem(
            id: '$folder|$i',
            title: s.title,
            artist: s.displayArtist,
            album: s.album,
            duration: s.duration,
            artUri: art(s.coverArt),
            playable: true,
          ),
      ];

  MediaItem _folder(String id, String title, {bool grid = false, String? subtitle, Uri? art}) => MediaItem(
        id: id,
        title: title,
        displaySubtitle: subtitle,
        artist: subtitle,
        artUri: art,
        playable: false,
        extras: {browsableHint: grid ? 2 : 1, playableHint: 1},
      );

  MediaItem _action(String id, String title, {String? subtitle}) =>
      MediaItem(id: id, title: title, displaySubtitle: subtitle, playable: true);

  /// Capa para o carro: o Android Auto só aceita `content://`, então a fonte
  /// (URL do servidor, com o token, ou arquivo do aparelho) fica num arquivo
  /// privado e o provedor de capas do app serve pela chave.
  Uri? art(String? coverArt) {
    final p = provider();
    if (coverArt == null || coverArt.isEmpty || p == null) return null;
    final src = coverArt.startsWith('/') ? coverArt : p.coverUri(coverArt, size: 300)?.toString();
    if (src == null) return null;
    final key = sha1.convert(utf8.encode('${p.accountId}|$coverArt')).toString().substring(0, 24);
    try {
      final f = File('$artDir/$key.src');
      if (!f.existsSync() || f.readAsStringSync() != src) {
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(src);
      }
    } catch (_) {
      return null;
    }
    return Uri.parse('content://$artAuthority/c/$key');
  }
}
