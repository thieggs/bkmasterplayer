import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/online_meta.dart';
import 'package:player_musica/domain/models.dart';

/// Usa a internet (LRCLIB, MusicBrainz/Cover Art Archive, Deezer): só roda com NETWORK_TESTS=1.
void main() {
  final skip = Platform.environment['NETWORK_TESTS'] != '1';
  // O ambiente de teste do Flutter troca o HttpClient por um falso: aqui queremos a rede de verdade.
  setUpAll(() => HttpOverrides.global = null);

  test('letra sincronizada do LRCLIB e cache no disco', () async {
    final dir = await Directory.systemTemp.createTemp('bk-lyrics');
    final fetcher = OnlineLyrics(cacheDir: dir.path);
    const song = Song(id: 'x', title: 'Get Lucky', artist: 'Daft Punk', album: 'Random Access Memories', duration: Duration(seconds: 248));
    final l = await fetcher.fetch(song);
    expect(l, isNotNull);
    expect(l!.synced, isTrue);
    expect(l.lines.length, greaterThan(20));
    expect(l.source, 'LRCLIB');
    // Segunda vez vem do cache (sem rede), com a fonte.
    final again = await fetcher.fetch(song);
    expect(again!.lines.length, l.lines.length);
    expect(again.source, 'LRCLIB');
    await dir.delete(recursive: true);
  }, skip: skip);

  test('capa de álbum pelo Cover Art Archive/Deezer', () async {
    final dir = await Directory.systemTemp.createTemp('bk-covers');
    final path = await fetchAlbumCover(artist: 'Daft Punk', album: 'Discovery', dir: dir.path, id: 'teste');
    expect(path, isNotNull);
    expect(await File(path!).length(), greaterThan(10000));
    await dir.delete(recursive: true);
  }, skip: skip);
}
