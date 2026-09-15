import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/connect/connect_auth.dart';
import 'package:player_musica/connect/connect_service.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/data/subsonic/subsonic_client.dart';
import 'package:player_musica/jam/jam_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Servidor Connect mínimo no loopback: faz o desafio com [key] e, se o outro
/// lado provar, manda o "hello" com a prova (ou [forgeHello], para testar o
/// cliente contra um aparelho falso).
Future<(HttpServer, Future<bool>)> _server(String key, {bool forgeHello = false}) async {
  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = Completer<bool>();
  http.listen((req) async {
    final ws = await WebSocketTransformer.upgrade(req);
    if (forgeHello) {
      ws.add(jsonEncode({'t': 'challenge', 'n': connectNonce()}));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ws.add(jsonEncode({'t': 'hello', 'h': 'f' * 64}));
      return;
    }
    final ok = await acceptConnectHandshake(ws, key);
    accepted.complete(ok != null);
    if (ok == null) return ws.close();
    ws.add(jsonEncode({'t': 'hello', 'id': 'srv', 'n': 'Sala', 'p': 'linux', 'h': ok.$2}));
  });
  return (http, accepted.future);
}

ConnectDevice _device(HttpServer http) =>
    ConnectDevice(id: 'srv', name: 'Sala', platform: 'linux', host: '127.0.0.1', port: http.port, seen: DateTime.now());

const _me = ConnectInfo(id: 'eu', name: 'Celular', platform: 'android');

void main() {
  group('chave do Connect', () {
    test('PBKDF2-HMAC-SHA256 bate com os vetores de teste (RFC 7914 / 6070)', () {
      final p = utf8.encode('password'), s = utf8.encode('salt');
      expect(_hex(pbkdf2Sha256(p, s, 1, 32)), '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(_hex(pbkdf2Sha256(p, s, 2, 32)), 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
      expect(_hex(pbkdf2Sha256(p, s, 4096, 32)), 'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('mesma conta dá a mesma chave em qualquer aparelho; outra senha, outra chave', () {
      final a = deriveConnectKey('Thiago', 'segredo', iterations: 50);
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(deriveConnectKey(' thiago ', 'segredo', iterations: 50), a, reason: 'usuário sem diferença de maiúsculas/espaços');
      expect(deriveConnectKey('thiago', 'Segredo', iterations: 50), isNot(a));
      expect(deriveConnectKey('outro', 'segredo', iterations: 50), isNot(a));
    });

    test('prova de um papel não serve no lugar de outro', () {
      const k = 'k';
      expect(connectProof(k, 'client', ['a', 'b']), isNot(connectProof(k, 'server', ['a', 'b'])));
      expect(connectProof(k, 'client', ['a', 'b']), isNot(connectProof(k, 'client', ['b', 'a'])));
      expect(sameDigest('abc', 'abc'), isTrue);
      expect(sameDigest('abc', 'abd'), isFalse);
      expect(sameDigest('abc', 'abcd'), isFalse);
    });

    test('pedido de status repetido ou fora da hora é recusado', () {
      final g = NonceGuard();
      final now = DateTime(2026, 9, 15, 12);
      final ts = now.millisecondsSinceEpoch ~/ 1000;
      final n = connectNonce();
      expect(g.fresh(n, ts, now: now), isTrue);
      expect(g.fresh(n, ts, now: now), isFalse, reason: 'mesmo pedido ouvido na rede');
      expect(g.fresh(connectNonce(), ts - 3600, now: now), isFalse, reason: 'uma hora atrás');
      expect(g.fresh('curto', ts, now: now), isFalse);
    });

    test('conta guarda a chave do Connect e recusa chave malformada', () {
      final key = deriveConnectKey('u', 'p', iterations: 10);
      final auth = SubsonicAuth.fromPassword('u', 'p', connectKey: key);
      final back = SubsonicAuth.fromJson(jsonDecode(jsonEncode(auth.toJson())) as Map<String, dynamic>)!;
      expect(back.connectKey, key);
      expect(back.params.keys, containsAll(['u', 't', 's']));
      expect(back.params.values, isNot(contains(key)), reason: 'a chave nunca vai para a rede');
      final old = SubsonicAuth.fromJson({'username': 'u', 'token': 't', 'salt': 's'})!;
      expect(old.connectKey, isNull, reason: 'conta de antes do Connect protegido');
      expect(SubsonicAuth.fromJson({'username': 'u', 'token': 't', 'salt': 's', 'connectKey': '../x'})!.connectKey, isNull);
    });

    test('ativar o Connect numa conta antiga confere a senha sem ir ao servidor', () {
      final auth = SubsonicAuth.fromPassword('thiago', 'sênha çom acento');
      expect(auth.matchesPassword('sênha çom acento'), isTrue);
      expect(auth.matchesPassword('senha com acento'), isFalse);
      expect(auth.matchesPassword(''), isFalse);
      expect(const SubsonicAuth.apiKey('k').matchesPassword('k'), isFalse);
    });
  });

  group('aperto de mão do Connect', () {
    test('mesma chave: conecta e recebe o estado', () async {
      final key = deriveConnectKey('u', 'p', iterations: 10);
      final (http, accepted) = await _server(key);
      final link = await ConnectLink.open(_device(http), key: key, me: _me);
      expect(await accepted, isTrue);
      final hello = await link.messages.first.timeout(const Duration(seconds: 5));
      expect(hello['t'], 'hello');
      await link.close();
      await http.close(force: true);
    });

    test('chave errada: o aparelho recusa e nada da conta é mandado', () async {
      final (http, accepted) = await _server(deriveConnectKey('u', 'p', iterations: 10));
      await expectLater(
        ConnectLink.open(_device(http), key: deriveConnectKey('u', 'outra', iterations: 10), me: _me),
        throwsA(isA<ConnectAuthException>()),
      );
      expect(await accepted, isFalse);
      await http.close(force: true);
    });

    test('aparelho falso que não sabe a chave não engana quem conecta', () async {
      final (http, _) = await _server('qualquer', forgeHello: true);
      await expectLater(
        ConnectLink.open(_device(http), key: deriveConnectKey('u', 'p', iterations: 10), me: _me),
        throwsA(isA<ConnectAuthException>()),
      );
      await http.close(force: true);
    });
  });

  group('Jam', () {
    test('capa de arquivo só sai se for imagem de verdade', () {
      expect(looksLikeImage([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]), isTrue);
      expect(looksLikeImage([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]), isTrue);
      expect(looksLikeImage([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]), isTrue);
      expect(looksLikeImage(utf8.encode('-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk')), isFalse);
      expect(looksLikeImage(utf8.encode('{"flutter.accounts":"[...]"}')), isFalse);
      expect(looksLikeImage(const []), isFalse);
    });

    test('"aceitar sempre" exige o passe entregue, não só o id do aparelho', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      final list = c.read(jamAllowlistProvider.notifier);
      final pass = list.add('aparelho-1', 'Ana');
      expect(list.allows('aparelho-1', pass), isTrue);
      expect(list.allows('aparelho-1', null), isFalse, reason: 'id copiado do anúncio da rede');
      expect(list.allows('aparelho-1', 'chute'), isFalse);
      expect(list.allows('aparelho-2', pass), isFalse);
      // Lista antiga (sem passe): o dono confirma de novo.
      SharedPreferences.setMockInitialValues({
        'jamAllowlist': [jsonEncode({'id': 'velho', 'n': 'Bia'})],
      });
      final c2 = ProviderContainer(overrides: [prefsProvider.overrideWithValue(await SharedPreferences.getInstance())]);
      addTearDown(c2.dispose);
      final old = c2.read(jamAllowlistProvider.notifier);
      expect(old.contains('velho'), isTrue);
      expect(old.allows('velho', null), isFalse);
      // O passe sobrevive a reabrir o app.
      final c3 = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      addTearDown(c3.dispose);
      expect(c3.read(jamAllowlistProvider.notifier).allows('aparelho-1', pass), isTrue);
    });
  });
}
