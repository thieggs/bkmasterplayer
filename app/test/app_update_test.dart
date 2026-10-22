import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/app_update.dart';
import 'package:player_musica/ui/update_dialog.dart';

void main() {
  test('compara versões número a número', () {
    expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    expect(compareVersions('v1.3.0', '1.2.0'), greaterThan(0));
    expect(compareVersions('1.2.0', '1.2.0+839911'), 0);
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('1.2.0', '1.2.1'), lessThan(0));
    expect(compareVersions('2.0.0-beta', '1.9.9'), greaterThan(0));
  });

  // Recorte da resposta real de /releases/latest (v1.2.0).
  final rel = AppRelease.fromGitHub({
    'tag_name': 'v1.2.0',
    'html_url': 'https://github.com/thieggs/bkmasterplayer/releases/tag/v1.2.0',
    'body': '### Mudou\n\n- **O disco tem rolamento.**',
    'assets': [
      for (final n in [
        'BKmasterplayer-1.2.0-instalador.exe',
        'BKmasterplayer-1.2.0-x86_64.AppImage',
        'BKmasterplayer-1.2.0.ipa',
        'bkmasterplayer_1.2.0+202609260354_amd64.deb',
        'bkmasterplayer_1.2.0+839911_arm64.apk',
      ])
        {'name': n, 'browser_download_url': 'https://github.com/x/$n', 'size': 10, 'digest': 'sha256:4ED168BD'},
      {'name': 'antigo.apk', 'browser_download_url': 'u', 'size': 1, 'digest': null},
    ],
  });

  test('lê o release do GitHub', () {
    expect(rel.version, '1.2.0');
    expect(rel.assets.first.sha256, '4ed168bd');
    expect(rel.assets.last.sha256, isNull);
  });

  test('cada jeito de instalar pega o seu arquivo', () {
    expect(assetFor(InstallKind.apk, rel.assets)?.name, 'bkmasterplayer_1.2.0+839911_arm64.apk');
    expect(assetFor(InstallKind.appImage, rel.assets)?.name, 'BKmasterplayer-1.2.0-x86_64.AppImage');
    expect(assetFor(InstallKind.deb, rel.assets)?.name, 'bkmasterplayer_1.2.0+202609260354_amd64.deb');
    expect(assetFor(InstallKind.userFolder, rel.assets)?.name, 'bkmasterplayer_1.2.0+202609260354_amd64.deb');
    expect(assetFor(InstallKind.windowsSetup, rel.assets)?.name, 'BKmasterplayer-1.2.0-instalador.exe');
    expect(assetFor(InstallKind.none, rel.assets), isNull);
  });

  test('novidades viram texto simples', () {
    expect(plainNotes(rel.notes), 'Mudou\n\n• O disco tem rolamento.');
  });
}
