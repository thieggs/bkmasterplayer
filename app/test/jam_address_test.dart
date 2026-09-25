import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/jam/jam_core.dart';

/// Entrar na Festa digitando o endereço.
///
/// Serve onde a descoberta automática não passa: no iPhone, porque a Apple
/// barra o broadcast sem conta paga, e em Wi-Fi de hotel ou empresa, que
/// costuma filtrar.
void main() {
  const padrao = 47802;
  dynamic ler(String s) => offerFromText(s, portaPadrao: padrao);

  test('só o endereço usa a porta padrão', () {
    final o = ler('192.168.1.10')!;
    expect(o.host, '192.168.1.10');
    expect(o.port, padrao);
  });

  test('endereço com porta', () {
    final o = ler('192.168.1.10:9000')!;
    expect(o.host, '192.168.1.10');
    expect(o.port, 9000);
  });

  test('aceita colado de um link', () {
    for (final s in ['ws://192.168.1.10:9000', 'http://192.168.1.10:9000/jam']) {
      final o = ler(s)!;
      expect(o.host, '192.168.1.10', reason: s);
      expect(o.port, 9000, reason: s);
    }
  });

  test('espaço em volta não atrapalha', () {
    expect(ler('  192.168.1.10:9000  ')!.port, 9000);
  });

  test('nome de máquina também serve', () {
    expect(ler('pc-da-sala.local')!.host, 'pc-da-sala.local');
  });

  test('o que não dá para entender vira nulo', () {
    for (final s in ['', '   ', ':9000', '192.168.1.10:abc', '192.168.1.10:0', '192.168.1.10:70000']) {
      expect(ler(s), isNull, reason: 'era para recusar: "$s"');
    }
  });

  test('entrar à mão fica marcado como tal', () {
    expect(ler('192.168.1.10')!.manual, isTrue);
  });
}
