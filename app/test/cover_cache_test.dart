import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/core/format.dart';
import 'package:player_musica/ui/widgets/cover_art.dart';
import 'package:path/path.dart' as p;

/// Endereço onde ninguém atende, para valer como "sem rede".
Future<String> _semRede() async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final url = 'http://127.0.0.1:${s.port}/capa.jpg';
  await s.close(force: true);
  return url;
}

String _arquivo(String dir, String chaveSemTamanho, int tamanho) =>
    p.join(dir, '${fnv1a32(chaveSemTamanho).toRadixString(16)}_$tamanho.img');

void main() {
  late Directory dir;
  const base = 'conta1:cover:abc';

  setUp(() async => dir = await Directory.systemTemp.createTemp('capas'));
  tearDown(() async => dir.delete(recursive: true));

  test('sem rede, serve outro tamanho da mesma capa', () async {
    // A capa apareceu numa lista (128) e agora a tela pede 300.
    await File(_arquivo(dir.path, base, 128)).writeAsBytes([1, 2, 3]);
    final f = await CoverImageProvider.fetchFile(url: await _semRede(), cacheKey: '$base:300', cacheDir: dir.path);
    expect(await f.readAsBytes(), [1, 2, 3], reason: 'melhor a de 128 do que quadrado cinza');
  });

  test('entre vários tamanhos guardados, pega o maior', () async {
    await File(_arquivo(dir.path, base, 128)).writeAsBytes([1]);
    await File(_arquivo(dir.path, base, 600)).writeAsBytes([6]);
    await File(_arquivo(dir.path, base, 300)).writeAsBytes([3]);
    final f = await CoverImageProvider.fetchFile(url: await _semRede(), cacheKey: '$base:1200', cacheDir: dir.path);
    expect(await f.readAsBytes(), [6]);
  });

  test('capa de outro álbum não serve', () async {
    await File(_arquivo(dir.path, 'conta1:cover:OUTRO', 300)).writeAsBytes([9]);
    await expectLater(
      CoverImageProvider.fetchFile(url: await _semRede(), cacheKey: '$base:300', cacheDir: dir.path),
      throwsA(isA<Object>()),
    );
  });

  test('cache antigo é aproveitado e passa para o nome novo', () async {
    // Formato antigo: o tamanho ia dentro do nome embaralhado.
    const chave = '$base:300';
    final antigo = File(p.join(dir.path, '${fnv1a32(chave).toRadixString(16)}.img'));
    await antigo.writeAsBytes([7, 7]);
    final f = await CoverImageProvider.fetchFile(url: await _semRede(), cacheKey: chave, cacheDir: dir.path);
    expect(await f.readAsBytes(), [7, 7], reason: 'não pode perder o que já estava guardado');
    expect(await File(_arquivo(dir.path, base, 300)).exists(), isTrue, reason: 'migrou para o nome novo');
    expect(await antigo.exists(), isFalse);
  });

  test('o tamanho exato guardado continua tendo preferência', () async {
    await File(_arquivo(dir.path, base, 300)).writeAsBytes([3]);
    await File(_arquivo(dir.path, base, 600)).writeAsBytes([6]);
    final f = await CoverImageProvider.fetchFile(url: await _semRede(), cacheKey: '$base:300', cacheDir: dir.path);
    expect(await f.readAsBytes(), [3]);
  });
}
