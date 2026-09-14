import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/subsonic/subsonic_client.dart';

/// Servidor Subsonic falso: responde ping e getGenres com status ok.
Future<HttpServer> _fakeServer(List<String> hits, String name) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    hits.add('$name ${req.uri.path}');
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'subsonic-response': {'status': 'ok', 'version': '1.16.1', 'genres': {'genre': []}},
      }));
    req.response.close();
  });
  return server;
}

void main() {
  test('usa o endereço de casa quando responde e volta ao principal quando some', () async {
    final hits = <String>[];
    final remote = await _fakeServer(hits, 'principal');
    final local = await _fakeServer(hits, 'casa');
    final client = SubsonicClient(
      baseUrl: 'http://127.0.0.1:${remote.port}',
      localUrl: 'http://127.0.0.1:${local.port}',
      auth: SubsonicAuth.fromPassword('u', 'p'),
    );
    final changes = <bool>[];
    client.endpointChanges.listen(changes.add);

    expect(await client.checkLocal(), isTrue);
    expect(client.baseUrl, 'http://127.0.0.1:${local.port}');
    await client.get('getGenres');
    expect(hits.last, 'casa /rest/getGenres');

    // Saiu de casa: o endereço local some; a chamada seguinte vai pelo principal.
    await local.close(force: true);
    await client.get('getGenres');
    expect(hits.last, 'principal /rest/getGenres');
    expect(client.onLocal, isFalse);
    expect(await client.checkLocal(), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(changes, [true, false]);
    await remote.close(force: true);
  });

  test('sem endereço de casa, fica sempre no principal', () async {
    final client = SubsonicClient(baseUrl: 'http://musica.exemplo.com', auth: SubsonicAuth.fromPassword('u', 'p'));
    expect(await client.checkLocal(), isFalse);
    expect(client.baseUrl, 'http://musica.exemplo.com');
  });
}
