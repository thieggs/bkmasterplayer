import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/settings.dart';
import 'package:player_musica/data/subsonic/subsonic_client.dart';
import 'package:player_musica/data/subsonic/subsonic_provider.dart';

void main() {
  test('servidor de análise é salvo e pode ser desligado', () {
    const off = AppSettings();
    expect(off.analysisServer, isNull);
    final on = off.copyWith(analysisServer: 'http://192.168.1.10:4540');
    expect(AppSettings.fromJson(on.toJson()).analysisServer, 'http://192.168.1.10:4540');
    expect(on.copyWith(clearAnalysisServer: true).analysisServer, isNull);
    // Mexer em outra coisa não apaga o servidor.
    expect(on.copyWith(automixBars: 8).analysisServer, 'http://192.168.1.10:4540');
  });

  test('endereço da análise leva o login da conta (token, nunca a senha)', () {
    final p = SubsonicProvider(
      accountId: 'conta',
      client: SubsonicClient(
        baseUrl: 'https://musica.exemplo',
        auth: const SubsonicAuth.token(username: 'thi ago', token: 'abc', salt: 'xyz'),
      ),
    );
    final uri = p.analyzerUri('http://pc:4540/', '/api/analysis/${Uri.encodeComponent('id/1')}')!;
    expect(uri.toString(), startsWith('http://pc:4540/api/analysis/id%2F1?'));
    expect(uri.queryParameters, {'u': 'thi ago', 't': 'abc', 's': 'xyz'});
    expect(p.analyzerUri('pc:4540', '/api/summary'), isNull, reason: 'sem http(s):// não é endereço');
  });
}
