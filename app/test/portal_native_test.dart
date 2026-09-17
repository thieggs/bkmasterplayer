import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/portal.dart';
import 'package:player_musica/data/subsonic/subsonic_client.dart';
import 'package:player_musica/src/rust/frb_generated.dart';

/// Portal de ponta a ponta, com as peças de verdade: o `bk-portal` assina e
/// serve o anúncio, o Dart baixa, e o motor em Rust confere a assinatura.
///
/// Os outros testes cobrem cada lado sozinho; este cobre a emenda. Se ela
/// quebrar (a ligação Dart→Rust, ou o texto do erro que o Dart usa para
/// reconhecer uma chave trocada), o portal falharia calado no celular.
///
/// Pula quando os binários não estão compilados:
///   cd app/rust && cargo build --release && cargo build --release --features portal-server --bin bk-portal
void main() {
  final lib = File('rust/target/release/libplayer_engine.so');
  final bin = File('rust/target/release/bk-portal');
  final skip = !Platform.isLinux
      ? 'só no Linux'
      : (!lib.existsSync() || !bin.existsSync())
          ? 'compile o motor e o bk-portal em release'
          : null;

  late HttpServer navidrome;
  late Process portal;
  late Directory dados;
  late String endereco;
  final log = StringBuffer();

  setUpAll(() async {
    if (skip != null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(lib.absolute.path));

    // Navidrome falso: aceita qualquer login.
    navidrome = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    navidrome.listen((req) {
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'subsonic-response': {'status': 'ok', 'version': '1.16.1', 'type': 'navidrome'},
        }));
      req.response.close();
    });

    final livre = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final porta = livre.port;
    await livre.close();
    endereco = 'http://127.0.0.1:$porta';
    dados = await Directory.systemTemp.createTemp('bk-portal-teste');

    portal = await Process.start(bin.absolute.path, [
      'serve',
      '--listen', '127.0.0.1:$porta',
      '--navidrome', 'http://127.0.0.1:${navidrome.port}',
      '--analyzer', 'http://127.0.0.1:9',
      '--url', endereco, // endereço fixo: sem túnel de verdade no teste
      '--nome', 'Servidor de teste',
    ], environment: {'XDG_DATA_HOME': dados.path});
    portal.stderr.transform(utf8.decoder).listen(log.write);

    // Espera o anúncio sair.
    final fim = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(fim)) {
      try {
        final r = await HttpClient().getUrl(Uri.parse('$endereco/bk/portal.json')).then((q) => q.close());
        await r.drain<void>();
        if (r.statusCode == 200) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    fail('o bk-portal não publicou o anúncio: $log');
  });

  tearDownAll(() async {
    if (skip != null) return;
    portal.kill();
    await portal.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    await navidrome.close(force: true);
    await dados.delete(recursive: true);
  });

  test('o anúncio assinado pelo bk-portal passa pela conferência em Rust', () async {
    final n = await Portal.fetch(endereco);
    expect(n.name, 'Servidor de teste');
    expect(n.music, endereco);
    expect(n.analysis, '$endereco/bk/analise');
    expect(n.key, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(n.fingerprint, matches(RegExp(r'^[0-9A-F]{4}(-[0-9A-F]{4}){7}$')));
    // Com a chave já fixada, continua aceitando.
    expect((await Portal.fetch(endereco, pinnedKey: n.key)).music, endereco);
  }, skip: skip);

  test('chave diferente da fixada é reconhecida como troca de chave', () async {
    // O Dart identifica esse caso pelo texto do erro que vem do Rust: se o
    // texto mudar lá, isto quebra aqui, em vez de o app tratar a troca de
    // chave como um anúncio qualquer com defeito.
    await expectLater(
      Portal.fetch(endereco, pinnedKey: 'ab' * 32),
      throwsA(isA<PortalException>().having((e) => e.problem, 'problema', PortalProblem.keyChanged)),
    );
    // E a sondagem da tela de entrar não engole esse caso.
    await expectLater(Portal.probe(endereco, pinnedKey: 'ab' * 32), throwsA(isA<PortalException>()));
  }, skip: skip);

  test('um Navidrome comum não é tomado por portal', () async {
    expect(await Portal.probe('http://127.0.0.1:${navidrome.port}'), isNull);
  }, skip: skip);

  test('a conta entra no servidor pelo endereço que o portal indica', () async {
    final n = await Portal.fetch(endereco);
    final client = SubsonicClient(baseUrl: 'https://antigo.invalid', auth: SubsonicAuth.fromPassword('dev', 'dev'));
    expect(await client.answersAt(n.music), isTrue);
    client.useRemote(n.music);
    expect((await client.get('ping'))['status'], 'ok');
  }, skip: skip);
}
