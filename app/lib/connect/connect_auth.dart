import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Autenticação do Connect entre aparelhos da mesma conta, sem que o token do
/// servidor saia do aparelho.
///
/// No login, a senha vira uma chave do Connect (PBKDF2-HMAC-SHA256, com o
/// usuário no sal), igual em todo aparelho que entrou com a mesma senha. Na
/// conexão, cada lado prova que tem a chave respondendo a um desafio aleatório
/// do outro (HMAC). Quem escuta a rede, ou finge ser um aparelho, não leva nada
/// que sirva para entrar no servidor nem para repetir depois.
const connectKeyIterations = 100000;

/// Janela de relógio aceita nos pedidos de status (aparelhos com a hora um
/// pouco diferente ainda se entendem).
const connectClockWindow = Duration(minutes: 10);

Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations, int length) {
  final hmac = Hmac(sha256, password);
  final out = BytesBuilder(copy: false);
  for (var block = 1; out.length < length; block++) {
    var u = hmac.convert([...salt, block >> 24 & 0xff, block >> 16 & 0xff, block >> 8 & 0xff, block & 0xff]).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.sublistView(out.toBytes(), 0, length);
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Chave do Connect (hex) a partir do login. Lenta de propósito: rode com
/// [deriveConnectKeyInIsolate] via `compute`.
String deriveConnectKey(String username, String password, {int iterations = connectKeyIterations}) => _hex(pbkdf2Sha256(
      utf8.encode(password),
      utf8.encode('bkmasterplayer-connect|${username.trim().toLowerCase()}'),
      iterations,
      32,
    ));

/// Para `compute`: [usuário, senha].
String deriveConnectKeyInIsolate(List<String> login) => deriveConnectKey(login[0], login[1]);

/// Prova (HMAC) de quem tem a chave: [what] separa os usos (cliente, servidor,
/// status), para uma prova não servir no lugar de outra.
String connectProof(String keyHex, String what, List<String> parts) =>
    Hmac(sha256, utf8.encode(keyHex)).convert(utf8.encode(['bk-connect-v2', what, ...parts].join('|'))).toString();

/// Compara sem vazar pelo tempo quantos caracteres batem.
bool sameDigest(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Desafio aleatório (128 bits, hex).
String connectNonce() {
  final r = Random.secure();
  return _hex(List.generate(16, (_) => r.nextInt(256)));
}

/// Pedidos de status já vistos: o mesmo pedido (ouvido na rede) não vale duas vezes.
class NonceGuard {
  NonceGuard({this.window = connectClockWindow, this.max = 10000});
  final Duration window;
  final int max;
  final _seen = <String, DateTime>{};

  /// Aceita [nonce] com o horário [unixSeconds] se estiver na janela e for novo.
  bool fresh(String nonce, int unixSeconds, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final at = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    if (at.difference(t).abs() > window || nonce.length < 16 || nonce.length > 64) return false;
    _seen.removeWhere((_, seen) => t.difference(seen) > window * 2);
    if (_seen.length >= max || _seen.containsKey(nonce)) return false;
    _seen[nonce] = t;
    return true;
  }
}
