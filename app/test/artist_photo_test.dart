import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/online_meta.dart';

/// O Deezer devolve vários artistas com o mesmo nome. "Filipe Ret" aparece
/// duas vezes: um com dois milhões de fãs e outro com nove. Pegar o errado
/// põe a foto de outra pessoa na tela.
void main() {
  Map<String, Object?> art(String nome, int fas, String foto) =>
      {'name': nome, 'nb_fan': fas, 'picture_xl': foto};

  const foto1 = 'https://cdn-images.dzcdn.net/images/artist/aaa/1000x1000.jpg';
  const foto2 = 'https://cdn-images.dzcdn.net/images/artist/bbb/1000x1000.jpg';
  const semFoto = 'https://cdn-images.dzcdn.net/images/artist//1000x1000.jpg';

  test('entre homônimos, fica o de mais fãs', () {
    final r = escolheFotoDeezer([
      art('Filipe Ret', 9, foto1),
      art('Filipe Ret', 2120728, foto2),
    ], 'Filipe Ret');
    expect(r, foto2);
  });

  test('ignora quem só parece com o nome', () {
    final r = escolheFotoDeezer([
      art('Vini Vici & Astrix', 740, foto1),
      art('Vini Vici', 211444, foto2),
    ], 'Vini Vici');
    expect(r, foto2);
  });

  test('a foto vazia do Deezer não conta', () {
    final r = escolheFotoDeezer([art('Alguém', 99999, semFoto)], 'Alguém');
    expect(r, isNull);
  });

  test('sem nome igual, não inventa', () {
    final r = escolheFotoDeezer([art('Outro Artista', 5, foto1)], 'Mandragora');
    expect(r, isNull);
  });

  test('acento e caixa não atrapalham', () {
    final r = escolheFotoDeezer([art('MANDRÁGORA', 10, foto1)], 'Mandrágora');
    expect(r, foto1);
  });
}
