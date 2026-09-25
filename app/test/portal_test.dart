import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/accounts.dart';
import 'package:player_musica/data/portal.dart';
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

  group('análise seguindo o portal', () {
    const portal = 'https://maquina-de-casa.tailnet-exemplo.ts.net';
    const tunelVelho = 'https://velho-nome-sorteado.trycloudflare.com';

    test('endereço de casa dá lugar ao portal (não funciona na rua)', () {
      for (final casa in [
        'http://192.168.1.229:4540',
        'http://10.0.0.5:4540',
        'http://172.20.1.2:4540',
        'http://100.64.180.93:4540', // Tailscale: só com o app dela
        'http://pc.local:4540',
        'http://localhost:4540',
        'http://[fd12::1]:4540',
      ]) {
        expect(Portal.canReplaceAnalysis(casa, portal: portal), isTrue, reason: casa);
      }
    });

    test('endereço antigo do próprio portal é trocado', () {
      expect(Portal.canReplaceAnalysis('$tunelVelho/bk/analise', previousMusic: tunelVelho, portal: portal), isTrue);
      expect(Portal.canReplaceAnalysis('$portal/bk/analise', portal: portal), isTrue);
    });

    test('endereço com /bk/analise veio de um portal: segue o portal, mesmo túnel de várias trocas atrás', () {
      // O caso real de 17/09: o túnel trocou com o celular em casa, e o
      // endereço salvo não batia nem com o anterior nem com o portal.
      expect(Portal.canReplaceAnalysis('https://greetings-iso-worth-cached.trycloudflare.com/bk/analise', portal: portal), isTrue);
    });

    test('outro servidor público escolhido à mão fica', () {
      expect(Portal.canReplaceAnalysis('https://analise.meudominio.com', previousMusic: tunelVelho, portal: portal), isFalse);
      expect(Portal.canReplaceAnalysis('http://8.8.8.8:4540', portal: portal), isFalse);
    });

    test('só endereço de casa conta como de casa', () {
      for (final fora in ['172.32.0.1', '100.128.0.1', '192.169.1.1', '11.0.0.1', 'exemplo.com', '999.1.1.1']) {
        expect(Portal.isHomeHost(fora), isFalse, reason: fora);
      }
    });
  });

  group('trocar de endereço com segurança', () {
    test('useRemote troca o principal e avisa', () async {
      final client = SubsonicClient(baseUrl: 'https://velho.trycloudflare.com', auth: SubsonicAuth.fromPassword('u', 'p'));
      final avisos = <bool>[];
      client.endpointChanges.listen(avisos.add);
      client.useRemote('https://novo.trycloudflare.com/');
      await Future<void>.delayed(Duration.zero);
      expect(client.remoteUrl, 'https://novo.trycloudflare.com');
      expect(avisos, [false]);
      // O mesmo endereço de novo não vira aviso repetido.
      client.useRemote('https://novo.trycloudflare.com');
      await Future<void>.delayed(Duration.zero);
      expect(avisos, [false]);
    });

    test('answersAt só diz sim quando a conta entra lá', () async {
      final hits = <String>[];
      final ok = await _server(hits, 'ok');
      final client = SubsonicClient(baseUrl: 'https://x', auth: SubsonicAuth.fromPassword('u', 'p'));
      expect(await client.answersAt('http://127.0.0.1:${ok.port}'), isTrue);
      expect(await client.answersAt(await _deadAddress()), isFalse, reason: 'ninguém atende');
      await ok.close(force: true);

      // Responde, mas recusa a senha: é outro servidor.
      final recusa = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      recusa.listen((req) {
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'subsonic-response': {'status': 'failed', 'error': {'code': 40, 'message': 'Wrong username or password'}},
          }));
        req.response.close();
      });
      expect(await client.answersAt('http://127.0.0.1:${recusa.port}'), isFalse, reason: 'senha recusada');
      await recusa.close(force: true);
    });
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
