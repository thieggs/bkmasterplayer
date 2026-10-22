import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/network.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sem o plugin de rede (como nos testes), a consulta falha: não pode estourar.
  test('consulta de rede que falha não estoura', () async {
    final c = ProviderContainer();
    expect(c.read(meteredProvider), false);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.read(meteredProvider), false);
  });
}
