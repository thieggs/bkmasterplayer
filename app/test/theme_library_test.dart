import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:player_musica/data/theme_library.dart';
import 'package:player_musica/data/ui_prefs.dart';
import 'package:player_musica/ui/theme/app_theme.dart';

void main() {
  late Directory dir;
  late ThemeLibrary lib;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bk-themes');
    lib = ThemeLibrary(dir.path);
    await lib.load();
  });
  tearDown(() => dir.delete(recursive: true));

  test('o tema BKmasterplayer pronto é o visual original', () {
    expect(const UiPrefs().sameTheme(builtInThemes.first.theme), isTrue);
    expect(builtInThemes.map((t) => t.id).toSet(), hasLength(builtInThemes.length));
  });

  test('todos os temas prontos montam em claro e escuro', () {
    for (final t in builtInThemes) {
      for (final b in Brightness.values) {
        expect(() => AppTheme.build(AppTheme.seeded(t.prefs, b), prefs: t.prefs), returnsNormally, reason: t.id);
      }
    }
  });

  test('salvar, renomear, sobrescrever e excluir ficam no disco', () async {
    final a = await lib.add('Meu', const UiPrefs(radius: 3).themeJson());
    final b = await lib.add('Meu', const UiPrefs(bodyFont: 'nunito').themeJson());
    expect(b.name, 'Meu (2)');
    await lib.rename(a.id, 'Noite');
    await lib.overwrite(b.id, const UiPrefs(bodyFont: 'jetbrainsMono').themeJson());
    final again = ThemeLibrary(dir.path);
    await again.load();
    expect(again.userThemes.map((t) => t.name), ['Noite', 'Meu (2)']);
    expect(again.byId(b.id)!.prefs.bodyFont, 'jetbrainsMono');
    await again.delete(a.id);
    final third = ThemeLibrary(dir.path);
    await third.load();
    expect(third.userThemes.map((t) => t.id), [b.id]);
  });

  test('exportar e importar um tema com imagem de fundo', () async {
    final img = await importThemeImage(dir.path, List.generate(5000, (i) => i % 256), ext: '.png');
    final t = await lib.add('Com foto', UiPrefs(background: 'image', backgroundImage: img, radius: 20).themeJson());
    final file = await lib.exportTheme(t);

    final other = await Directory.systemTemp.createTemp('bk-themes-2');
    addTearDown(() => other.delete(recursive: true));
    final lib2 = ThemeLibrary(other.path);
    final imported = await lib2.importTheme(file);
    expect(imported.name, 'Com foto');
    expect(imported.prefs.radius, 20);
    final name = imported.prefs.backgroundImage!;
    expect(File(p.join(themeImagesDir(other.path), name)).lengthSync(), 5000);
  });

  test('backup completo e restauração', () async {
    await lib.add('A', const UiPrefs(titleFont: 'bebas').themeJson());
    await lib.add('B', const UiPrefs(themeMode: 'light').themeJson());
    const current = UiPrefs(playerStyle: 'floating', variant: 'vibrant');
    final backup = await lib.exportBackup(current);

    final other = await Directory.systemTemp.createTemp('bk-themes-3');
    addTearDown(() => other.delete(recursive: true));
    final lib2 = ThemeLibrary(other.path);
    await lib2.add('vai sumir', const UiPrefs().themeJson());
    final (theme, _) = await lib2.restoreBackup(backup);
    expect(lib2.userThemes.map((t) => t.name), ['A', 'B']);
    expect(current.sameTheme(theme), isTrue);
  });

  test('backups automáticos: guarda só os 10 últimos, o mais novo primeiro', () async {
    for (var i = 0; i < 12; i++) {
      await lib.autoBackup(UiPrefs(radius: i.toDouble()), now: DateTime(2026, 9, 14, 12, 0, i));
    }
    final list = await lib.autoBackups();
    expect(list, hasLength(ThemeLibrary.keepAutoBackups));
    final newest = jsonDecode(await File(list.first.path).readAsString()) as Map;
    expect((newest['current'] as Map)['radius'], 11);
  });

  test('arquivos estranhos não entram', () async {
    expect(() => lib.importTheme('{"app":"outro","type":"theme","theme":{}}'), throwsFormatException);
    expect(() => lib.importTheme('não é json'), throwsFormatException);
    final t = await lib.importTheme(jsonEncode({
      'app': 'bkplayer',
      'type': 'theme',
      'name': 'x' * 300,
      'theme': {'backgroundImage': '../../etc/passwd', 'radius': 500},
      'images': {'../../../evil.sh': base64Encode(utf8.encode('#!/bin/sh'))},
    }));
    expect(t.name.length, 40);
    expect(t.prefs.backgroundImage, isNull);
    expect(t.prefs.radius, 28);
    // A imagem entrou só na pasta de imagens, com nome pelo conteúdo.
    expect(File(p.join(dir.path, 'evil.sh')).existsSync(), isFalse);
    expect(Directory(themeImagesDir(dir.path)).listSync().map((f) => p.basename(f.path)).single, matches(RegExp(r'^[0-9a-f]{20}\.(img|sh)$')));
  });
}
