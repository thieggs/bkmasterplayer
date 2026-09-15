import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/core/diagnostics.dart';

void main() {
  test('registro nunca guarda senha, token, salt, chave nem usuário', () {
    const token = '0123456789abcdef0123456789abcdef'; // gitleaks:allow (token falso do teste)
    final samples = {
      'DioException: http://192.168.1.10:4533/rest/stream?u=thiago&t=$token&s=a1b2c3&v=1.16.1&id=Song42': ['thiago', token, 'a1b2c3'],
      '{"username":"thiago","token":"$token","salt":"x9y8","connectKey":"${'ab' * 32}"}': ['thiago', token, 'x9y8', 'ab' * 32],
      'Authorization: Bearer 7f3a9c1e5b2d8f4a6c0e': ['7f3a9c1e5b2d8f4a6c0e'],
      'hello {"t":"hello","id":"dev1","n":"Ana","k":"passe-secreto"}': ['passe-secreto'],
      'ws://pc:47800/connect?cid=x&h=${'cd' * 32}&n=${'ef' * 16}': ['cd' * 32, 'ef' * 16],
      'FileSystemException: /home/thieggs/.local/share/app/x.json': ['thieggs'],
    };
    for (final e in samples.entries) {
      final out = redactSecrets(e.key);
      for (final secret in e.value) {
        expect(out, isNot(contains(secret)), reason: '${e.key} → $out');
      }
    }
    // O que ajuda a achar o bug continua.
    expect(redactSecrets(samples.keys.first), contains('id=Song42'));
    expect(redactSecrets(samples.keys.last), contains('~/.local/share/app/x.json'));
  });

  test('registro guarda erros, limita o tamanho e traz a sessão anterior', () async {
    final dir = await Directory.systemTemp.createTemp('bk-log');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/logs/app.log')
      ..createSync(recursive: true)
      ..writeAsStringSync('2026-09-15 10:00:00 [erro] falhou ontem\n');
    final log = AppLog.instance;
    await log.clear();
    log.add('info', 'antes do disco');
    await log.init(dir);
    expect(log.lines.first, '— sessão anterior —');
    expect(log.lines, contains(contains('falhou ontem')));
    expect(log.lines.last, contains('antes do disco'), reason: 'ordem do relógio');
    final errorsBefore = log.errors;
    log.add('erro', 'quebrou\nlinha 2');
    expect(log.errors, errorsBefore + 1);
    expect(log.lines.last, '    linha 2');
    for (var i = 0; i < AppLog.maxLines + 50; i++) {
      log.add('info', 'linha $i');
    }
    expect(log.lines.length, AppLog.maxLines);
    expect(logEntries(['a [erro] x', '    #0 f', '    #1 g', 'b [info] y']), [
      ['a [erro] x', '    #0 f', '    #1 g'],
      ['b [info] y'],
    ]);
    final report = diagnosticReport(info: {'Conta': 'Navidrome 0.58', 'Teste': 'u=thiago&t=abc'});
    expect(report, contains('Conta: Navidrome 0.58'));
    expect(report, isNot(contains('thiago')));
  });
}
