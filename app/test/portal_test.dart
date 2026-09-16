import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/accounts.dart';
import 'package:player_musica/data/subsonic/subsonic_client.dart';

/// Servidor Subsonic falso que responde ok.
Future<HttpServer> _server(List<String> hits, String name) async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((req) {
    hits.add('$name ${req.uri.path}');
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'subsonic-response': {'status': 'ok', 'version': '1.16.1', 'genres': {'genre': []}},
      }));
    req.response.close();
  });
  return s;
}

/// Endereço onde ninguém atende (o túnel que trocou de nome).
Future<String> _deadAddress() async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final url = 'http://127.0.0.1:${s.port}';
  await s.close(force: true);
  return url;
}

void main() {
  test('quando o endereço de fora cai, pergunta ao portal e segue no novo', () async {
    final hits = <String>[];
    final novo = await _server(hits, 'novo');
    final client = SubsonicClient(
      baseUrl: await _deadAddress(),
      auth: SubsonicAuth.fromPassword('u', 'p'),
    );
    var perguntas = 0;
    client.onPortalLookup = () async {
      perguntas++;
      return 'http://127.0.0.1:${novo.port}';
    };

    await client.get('getGenres');

    expect(perguntas, 1, reason: 'perguntou uma vez');
    expect(hits, ['novo /rest/getGenres'], reason: 'o pedido foi refeito no endereço novo');
    expect(client.remoteUrl, 'http://127.0.0.1:${novo.port}', reason: 'o cliente passou a usar o novo');
    await novo.close(force: true);
  });

  test('sem portal, o erro de rede continua sendo erro de rede', () async {
    final client = SubsonicClient(baseUrl: await _deadAddress(), auth: SubsonicAuth.fromPassword('u', 'p'));
    await expectLater(client.get('getGenres'), throwsA(isA<SubsonicException>()));
  });

  test('não fica perguntando ao portal a cada pedido que falha', () async {
    final client = SubsonicClient(baseUrl: await _deadAddress(), auth: SubsonicAuth.fromPassword('u', 'p'));
    var perguntas = 0;
    // O portal responde, mas o endereço novo também está morto: sem a trava,
    // cada tentativa seguinte viraria uma pergunta nova.
    final tambemMorto = await _deadAddress();
    client.onPortalLookup = () async {
      perguntas++;
      return tambemMorto;
    };

    for (var i = 0; i < 5; i++) {
      await expectLater(client.get('getGenres'), throwsA(isA<SubsonicException>()));
    }
    expect(perguntas, 1, reason: 'uma pergunta, não cinco');
  });

  test('portal devolvendo o mesmo endereço não vira tentativa infinita', () async {
    final morto = await _deadAddress();
    final client = SubsonicClient(baseUrl: morto, auth: SubsonicAuth.fromPassword('u', 'p'));
    var perguntas = 0;
    client.onPortalLookup = () async {
      perguntas++;
      return morto;
    };

    await expectLater(client.get('getGenres'), throwsA(isA<SubsonicException>()));
    expect(perguntas, 1);
    expect(client.remoteUrl, morto);
  });

  test('portal fora do ar não derruba o pedido com outro erro', () async {
    final client = SubsonicClient(baseUrl: await _deadAddress(), auth: SubsonicAuth.fromPassword('u', 'p'));
    client.onPortalLookup = () async => throw Exception('portal fora do ar');
    await expectLater(client.get('getGenres'), throwsA(isA<SubsonicException>()));
  });

  group('conta com portal', () {
    test('guarda e relê o endereço do portal e a chave fixada', () {
      const key = 'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef561234'; // gitleaks:allow (chave pública falsa do teste)
      const a = ServerAccount(
        id: '1',
        name: 'Casa',
        baseUrl: 'https://tunel.trycloudflare.com',
        username: 'eu',
        portalUrl: 'https://pc.ts.net',
        portalKey: key,
      );
      final voltou = ServerAccount.fromJson(a.toJson());
      expect(voltou.portalUrl, 'https://pc.ts.net');
      expect(voltou.portalKey, key);
    });

    test('chave em formato errado é descartada em vez de fixada', () {
      for (final ruim in ['', 'nao-e-hexadecimal', 'ab12', 'z' * 64]) {
        final j = {
          'id': '1',
          'name': 'Casa',
          'baseUrl': 'https://x.com',
          'username': 'eu',
          'portalKey': ruim,
        };
        expect(ServerAccount.fromJson(j).portalKey, isNull, reason: 'recusa "$ruim"');
      }
    });

    test('o endereço novo entra na conta sem perder o resto', () {
      const chave = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const a = ServerAccount(
        id: '1',
        name: 'Casa',
        baseUrl: 'https://antigo.trycloudflare.com',
        username: 'eu',
        localUrl: 'http://192.168.1.229:4533',
        portalUrl: 'https://pc.ts.net',
        portalKey: chave,
      );
      final b = a.copyWith(baseUrl: 'https://novo.trycloudflare.com');
      expect(b.baseUrl, 'https://novo.trycloudflare.com');
      expect(b.localUrl, 'http://192.168.1.229:4533');
      expect(b.portalUrl, 'https://pc.ts.net');
      expect(b.portalKey, chave);
      expect(b.id, '1');
    });
  });
}
