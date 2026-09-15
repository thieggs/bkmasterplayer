import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/subsonic/subsonic_provider.dart';

void main() {
  test('link criado em casa sai com o endereço de fora', () {
    const home = 'http://192.168.1.10:4533', outside = 'https://musica.exemplo.net';
    expect(
      shareLinkForOutside(Uri.parse('http://192.168.1.10:4533/share/Ab12'), current: home, main: outside).toString(),
      'https://musica.exemplo.net/share/Ab12',
    );
    // Servidor numa subpasta (/navidrome) dos dois lados.
    expect(
      shareLinkForOutside(Uri.parse('http://192.168.1.10:4533/navidrome/share/X'),
              current: 'http://192.168.1.10:4533/navidrome', main: 'https://exemplo.net/navidrome')
          .toString(),
      'https://exemplo.net/navidrome/share/X',
    );
    // Já pelo endereço de fora, ou link de outro host (ND_SHAREURL): fica como veio.
    final out = Uri.parse('https://musica.exemplo.net/share/Ab12');
    expect(shareLinkForOutside(out, current: outside, main: outside), out);
    final custom = Uri.parse('https://links.exemplo.net/share/Ab12');
    expect(shareLinkForOutside(custom, current: home, main: outside), custom);
  });
}
