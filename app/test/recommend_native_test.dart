import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/src/rust/api/recommend.dart' as rust;
import 'package:player_musica/src/rust/frb_generated.dart';

/// Recomendação de ponta a ponta com o motor de verdade.
///
/// O arquivo é montado aqui, byte a byte, no mesmo formato que
/// `dev/exporta_audiomuse.py` grava. Se um lado mudar o formato e o outro
/// não, este teste quebra — que é o ponto.
Uint8List montaArquivo({
  required List<String> ids,
  required List<int> paraVetor,
  required List<List<double>> audio,
  required List<List<double>> letra,
  required List<List<double>> estilos,
  required List<double> tempos,
  required List<int> tons,
  required List<int> anos,
  List<String> vocab = const ['rock', 'pop'],
}) {
  final b = BytesBuilder();
  void u32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void f32(double v) => b.add(Uint8List(4)..buffer.asByteData().setFloat32(0, v, Endian.little));

  b.add([0x42, 0x4b, 0x56, 0x45, 0x43, 0x02, 0x00, 0x00]); // "BKVEC" + versão 2
  u32(ids.length);
  u32(audio.length);
  u32(audio.first.length);
  u32(letra.first.length);
  u32(estilos.first.length);
  u32(32); // tamanho do id
  final v = vocab.join('\n').codeUnits;
  u32(v.length);
  b.add(v);
  for (var i = 0; i < ids.length; i++) {
    final id = Uint8List(32);
    id.setRange(0, ids[i].length, ids[i].codeUnits);
    b.add(id);
    u32(paraVetor[i]);
  }
  for (var i = 0; i < audio.length; i++) {
    f32(tempos[i]);
    f32(0.5); // energia
    b.add(Uint8List(2)..buffer.asByteData().setUint16(0, anos[i], Endian.little));
    b.add([tons[i], 0]); // tom, maior
    b.add(List.filled(6, 128)); // clima
    b.add([for (final x in estilos[i]) (x * 255).round().clamp(0, 255)]);
    for (final x in audio[i]) {
      f32(x);
    }
    for (final x in letra[i]) {
      f32(x);
    }
  }
  return b.toBytes();
}

void main() {
  final lib = File('rust/target/release/libplayer_engine.so');
  final skip = !Platform.isLinux || !lib.existsSync() ? 'compile o motor em release' : null;
  late Directory dir;
  late File arquivo;

  setUpAll(() async {
    if (skip != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(lib.absolute.path));
    dir = await Directory.systemTemp.createTemp('vetores');
    arquivo = File('${dir.path}/v.bkvec');
    await arquivo.writeAsBytes(montaArquivo(
      // "igual" aparece duas vezes na biblioteca (single e álbum).
      ids: ['semente', 'gemea', 'igualA', 'igualB', 'oposta'],
      paraVetor: [0, 1, 2, 2, 3],
      audio: [
        [1.0, 0.0],
        [0.98, 0.2],
        [0.0, 1.0],
        [-1.0, 0.0],
      ],
      letra: [
        [1.0, 0.0],
        [0.0, 1.0],
        [1.0, 0.0],
        [0.0, 1.0],
      ],
      estilos: [
        [0.6, 0.0],
        [0.0, 0.6],
        [0.6, 0.0],
        [0.0, 0.6],
      ],
      tempos: [128.0, 129.0, 64.0, 128.0],
      tons: [0, 0, 7, 6],
      anos: [2000, 1970, 2001, 1970],
    ));
  });

  tearDownAll(() async {
    if (skip == null) await dir.delete(recursive: true);
  });

  test('carrega o arquivo e conhece as músicas', () async {
    expect(await rust.recommendLoad(path: arquivo.path), 4, reason: '4 vetores, 5 arquivos');
    expect(await rust.recommendKnows(id: 'igualB'), isTrue);
    expect(await rust.recommendKnows(id: 'inexistente'), isFalse);
    expect(await rust.recommendCount(), 4);
  }, skip: skip);

  test('a mais parecida no som vem primeiro, e sem repetir a mesma música', () async {
    await rust.recommendLoad(path: arquivo.path);
    final r = await rust.recommendSimilar(seed: 'semente', style: 'sound', limit: 10, allowed: []);
    expect(r.first.id, 'gemea');
    expect(r.map((x) => x.id), isNot(contains('semente')), reason: 'a própria semente fica de fora');
    // "igualA" e "igualB" são o mesmo vetor: só uma pode aparecer.
    expect(r.where((x) => x.id == 'igualA' || x.id == 'igualB').length, 1, reason: 'arquivo repetido não vira sugestão repetida');
  }, skip: skip);

  test('cada estilo ordena pelo que promete', () async {
    await rust.recommendLoad(path: arquivo.path);
    Future<String> topo(String estilo) async =>
        (await rust.recommendSimilar(seed: 'semente', style: estilo, limit: 1, allowed: [])).first.id;
    expect(await topo('sound'), 'gemea', reason: 'som quase igual');
    expect(await topo('lyrics'), 'igualA', reason: 'mesma letra');
    expect(await topo('era'), 'igualA', reason: '2001 contra 1970');
  }, skip: skip);

  test('offline, só sugere o que está baixado', () async {
    await rust.recommendLoad(path: arquivo.path);
    final r = await rust.recommendSimilar(seed: 'semente', style: 'sound', limit: 10, allowed: ['oposta']);
    expect(r.map((x) => x.id), ['oposta'], reason: 'o resto não dá para tocar agora');
  }, skip: skip);

  test('semente desconhecida não quebra', () async {
    await rust.recommendLoad(path: arquivo.path);
    expect(await rust.recommendSimilar(seed: 'nao-existe', style: 'sound', limit: 5, allowed: []), isEmpty);
    expect(await rust.recommendSimilar(seed: 'semente', style: 'estilo-que-nao-existe', limit: 5, allowed: []), isEmpty);
  }, skip: skip);
}
