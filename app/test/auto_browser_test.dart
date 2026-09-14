import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/domain/music_provider.dart';
import 'package:player_musica/mobile/auto_browser.dart';

/// Só o que a navegação do carro usa; o resto não é chamado.
class _FakeProvider implements MusicProvider {
  final searches = <String>[];

  static const _songs = [
    Song(id: 's1', title: 'Um', artist: 'Banda', coverArt: 'al-1'),
    Song(id: 's2', title: 'Dois', artist: 'Banda', coverArt: 'al-1'),
  ];

  @override
  String get accountId => 'conta';

  @override
  Uri? coverUri(String? coverArtId, {int? size}) =>
      coverArtId == null ? null : Uri.parse('http://srv/rest/getCoverArt?id=$coverArtId&size=$size&t=segredo');

  @override
  Future<Album> album(String id) async => Album(id: id, name: 'Disco', coverArt: 'al-1', songs: _songs);

  @override
  Future<List<Album>> albumList(AlbumListType type,
          {int size = 50, int offset = 0, String? genre, int? fromYear, int? toYear}) async =>
      [const Album(id: 'a1', name: 'Disco', artist: 'Banda', coverArt: 'al-1')];

  @override
  Future<List<Song>> topSongs(String artistName, {int count = 10}) async => [Song(id: 'top', title: 'Sucesso de $artistName')];

  @override
  Future<SearchResult> search(String query, {int artistCount = 10, int albumCount = 20, int songCount = 50}) async {
    searches.add(query);
    return SearchResult(songs: query == 'um' ? [_songs.first] : const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late _FakeProvider fake;
  late AutoBrowser auto;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bk-auto');
    fake = _FakeProvider();
    auto = AutoBrowser(provider: () => fake, artDir: dir.path, pt: true);
  });
  tearDown(() => dir.delete(recursive: true));

  test('raiz com 4 abas e álbuns em grade', () async {
    final root = await auto.children('root');
    expect(root.map((m) => m.id), ['tab:home', 'tab:recent', 'tab:albums', 'tab:playlists']);
    expect(root[1].extras![AutoBrowser.browsableHint], 2);
    final albums = await auto.children('tab:albums');
    expect(albums.single.id, 'album:a1');
    expect(albums.single.playable, isFalse);
  });

  test('músicas do álbum tocam a partir da escolhida', () async {
    final songs = await auto.children('album:a1');
    expect(songs.map((m) => m.id), ['album:a1|0', 'album:a1|1']);
    final (list, start) = (await auto.resolve('album:a1|1'))!;
    expect(list.map((s) => s.id), ['s1', 's2']);
    expect(start, 1);
  });

  test('capa por content:// sem o token na URI; a fonte fica no arquivo privado', () async {
    final songs = await auto.children('album:a1');
    final art = songs.first.artUri!;
    expect(art.scheme, 'content');
    expect(art.toString(), isNot(contains('segredo')));
    final src = File('${dir.path}/${art.pathSegments.last}.src').readAsStringSync();
    expect(src, contains('getCoverArt?id=al-1'));
  });

  test('voz: foco no artista toca as mais tocadas dele; texto solto busca música', () async {
    final byArtist = await auto.voice('banda', {'android.intent.extra.focus': 'vnd.android.cursor.item/artist', 'android.intent.extra.artist': 'Banda'});
    expect(byArtist.single.title, 'Sucesso de Banda');
    final bySong = await auto.voice('um', null);
    expect(bySong.single.id, 's1');
  });

  test('sem login não quebra', () async {
    final none = AutoBrowser(provider: () => null, artDir: dir.path, pt: false);
    expect(await none.children('tab:albums'), isEmpty);
    expect(await none.resolve('album:a1|0'), isNull);
  });
}
