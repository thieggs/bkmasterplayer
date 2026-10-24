import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/current_version.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/domain/music_provider.dart';

/// Músicas trocadas por um arquivo melhor ganham id novo no Navidrome, e o id
/// velho (guardado na fila, em listas, em downloads) para de tocar. Casos
/// tirados das 5312 trocas da biblioteca de verdade em 23/10/2026.

/// A busca do servidor: só conhece as músicas que estão na biblioteca hoje.
/// O `getSong` ainda responde as que sumiram ([gone]), com as etiquetas.
class _Server implements MusicProvider {
  _Server(this.songs, {this.gone = const []});

  final List<Song> songs;
  final List<Song> gone;
  final queries = <String>[];

  @override
  Future<SearchResult> search(String query, {int artistCount = 10, int albumCount = 20, int songCount = 50}) async {
    queries.add(query);
    // Como o Navidrome: todas as palavras têm de aparecer em algum campo.
    final words = query.toLowerCase().split(' ').where((w) => w.isNotEmpty);
    bool has(Song s) {
      final text = '${s.title} ${s.artist} ${s.album}'.toLowerCase();
      return words.every(text.contains);
    }

    return SearchResult(songs: songs.where(has).take(songCount).toList());
  }

  @override
  Future<List<Song>> songsByIds(List<String> ids) async =>
      [for (final s in [...songs, ...gone]) if (ids.contains(s.id)) s];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Servidor que devolve tudo na busca (para testar só o casamento dos nomes).
class _ServerAll extends _Server {
  _ServerAll(super.songs);

  @override
  Future<SearchResult> search(String query, {int artistCount = 10, int albumCount = 20, int songCount = 50}) async =>
      SearchResult(songs: songs);
}

Song _song(String id, String title,
        {String artist = 'Mandragora',
        String album = 'BIG MODE',
        int track = 1,
        int secs = 250,
        String suffix = 'flac',
        List<String> isrc = const [],
        List<String>? artists}) =>
    Song(
      id: id,
      title: title,
      artist: artist,
      artists: [for (final a in artists ?? const <String>[]) ArtistRef(id: a, name: a)],
      album: album,
      track: track,
      duration: Duration(seconds: secs),
      suffix: suffix,
      isrc: isrc,
    );

void main() {
  final flac = _song('1Nzv4C', 'Big Mode');
  final mp3 = _song('boBA47', 'Big Mode', secs: 251, suffix: 'mp3');

  test('id velho: acha a versão nova', () async {
    final server = _Server([flac, _song('VFJuRy', 'Maxi', track: 3)]);
    expect((await currentVersion(server, mp3))?.id, '1Nzv4C');
    expect(server.queries.first, 'big mode', reason: 'busca pelo núcleo do título');
  });

  test('música que continua na biblioteca é ela mesma', () async {
    // A mesma gravação também num single: o id da fila ainda vale.
    final single = _song('single', 'Big Mode', album: 'Big Mode - Single');
    expect((await currentVersion(_Server([single, flac]), flac))?.id, '1Nzv4C');
  });

  test('o ISRC do id velho (perguntado ao servidor) decide, mesmo com a duração diferente', () async {
    // Fila guardada por uma versão sem ISRC: quem sabe é o getSong do id velho.
    final velha = _song('velha', 'Felino', secs: 200, suffix: 'mp3');
    final comIsrc = _song('velha', 'Felino', secs: 200, suffix: 'mp3', isrc: ['QZES92351802']);
    final remaster = _song('nova', 'Felino', secs: 206, isrc: ['QZES92351802']);
    final outra = _song('outra', 'Felino', secs: 200, suffix: 'mp3', isrc: ['BRXXX0000001']);
    final server = _Server([outra, remaster], gone: [comIsrc]);
    expect((await currentVersion(server, velha))?.id, 'nova');
  });

  test('título novo sem "(Remastered)", " - Ao Vivo", "feat."', () async {
    for (final (velho, novo) in [
      ('The Four Horsemen (Remastered)', 'The Four Horsemen'),
      ('Burguesinha - Ao Vivo', 'Burguesinha'),
      ('Me Too', 'Me Too '),
      ('Mojito (feat. Stefano Mota)', 'Mojito'),
      ('Pirâmide', 'Pirâmide'),
      // Os que a primeira versão da regra perdia no servidor de verdade.
      ('Wait for Sleep (Live in NYC - 1993)', 'Wait for Sleep'),
      ('Eu Tenho Muito Mais Live Version', 'Eu Tenho Muito Mais '),
      ('Groove On : Groove On', 'Groove On'),
      ('Boa Sorte / Good Luck (feat. Ben Harper)', 'Boa Sorte (Good Luck) [feat. Ben Harper]'),
      ('I Don&#039;t Now', "I Don't Now"),
    ]) {
      final nova = _song('nova', novo);
      final r = await currentVersion(_ServerAll([nova]), _song('velha', velho, suffix: 'mp3'));
      expect(r?.id, 'nova', reason: '"$velho" → "$novo"');
    }
  });

  test('artista "A • B" na fila e só "A" no servidor', () async {
    final velha = _song('velha', 'Adhana', artist: 'Vini Vici • Astrix', album: 'Adhana', secs: 380);
    final nova = _song('KKlP4G', 'Adhana', artist: 'Vini Vici', album: 'Adhana', secs: 381, artists: ['Vini Vici']);
    expect((await currentVersion(_Server([nova]), velha))?.id, 'KKlP4G');
  });

  test('nenhum artista em comum: só depois de dar erro, e com a mesma duração', () async {
    final velha = _song('velha', '4EVA', artist: 'Aminé • KAYTRANADA', secs: 170, suffix: 'mp3');
    final nova = _song('nova', '4EVA', artist: 'KAYTRAMINÉ', secs: 171);
    expect((await currentVersion(_Server([nova]), velha))?.id, 'nova');
    expect(await currentVersion(_Server([nova]), velha, strict: true), isNull);
  });

  test('título comum: tenta de novo com o primeiro artista', () async {
    final outras = [for (var i = 0; i < 60; i++) _song('o$i', 'Intro', artist: 'Banda $i')];
    final nova = _song('nova', 'Intro', artist: 'Mandragora', album: 'Aladin');
    final server = _Server([...outras, nova]);
    expect((await currentVersion(server, _song('velha', 'Intro', suffix: 'mp3')))?.id, 'nova');
    expect(server.queries, ['intro', 'intro mandragora']);
  });

  test('outra gravação com o mesmo nome não serve', () async {
    final aoVivo = _song('vivo', 'Big Mode', album: 'Ao Vivo', secs: 320);
    expect(await currentVersion(_Server([aoVivo]), mp3), isNull);
  });

  test('entre cópias da mesma gravação, a sem perda', () async {
    final outroMp3 = _song('mp3', 'Big Mode', album: 'Coletânea', suffix: 'mp3', secs: 251);
    expect((await currentVersion(_Server([outroMp3, flac]), mp3))?.id, '1Nzv4C');
  });

  test('nada parecido: null', () async {
    expect(await currentVersion(_Server([]), mp3), isNull);
  });
}
