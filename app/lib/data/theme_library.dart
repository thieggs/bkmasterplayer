import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Pasta das imagens de fundo dos temas.
String themeImagesDir(String supportDir) => p.join(supportDir, 'themes', 'images');

/// Imagem de fundo aceita (tamanho máximo, ao escolher ou importar).
const maxThemeImageBytes = 12 * 1024 * 1024;

/// Copia uma imagem escolhida para a pasta dos temas e devolve o nome (o tema
/// guarda só o nome, nunca um caminho). Mesmo conteúdo = mesmo nome.
Future<String> importThemeImage(String supportDir, List<int> bytes, {String ext = '.jpg'}) async {
  if (bytes.isEmpty || bytes.length > maxThemeImageBytes) throw const FormatException('imagem inválida');
  final clean = ext.toLowerCase().replaceAll(RegExp(r'[^a-z.]'), '');
  final name = '${sha1.convert(bytes).toString().substring(0, 20)}${RegExp(r'^\.[a-z]{2,4}$').hasMatch(clean) ? clean : '.img'}';
  final out = File(p.join(themeImagesDir(supportDir), name));
  await out.parent.create(recursive: true);
  if (!await out.exists()) await out.writeAsBytes(bytes, flush: true);
  return name;
}
