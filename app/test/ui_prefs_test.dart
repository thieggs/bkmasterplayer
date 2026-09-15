import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/ui_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('o padrão é o visual original', () {
    const p = UiPrefs();
    expect(p.themeMode, 'dark');
    expect(p.colorSource, 'cover');
    expect(p.seed, 0xFF7C4DFF);
    expect(p.variant, 'tonalSpot');
    expect(p.contrast, 0);
    expect(p.colors, isEmpty);
    expect((p.bodyFont, p.titleFont), ('system', 'system'));
    expect((p.radius, p.buttonStyle, p.cardStyle), (12, 'filled', 'flat'));
    expect((p.background, p.playerStyle, p.navLabels), ('solid', 'docked', 'auto'));
    expect((p.transitions, p.animations), ('default', 'normal'));
    expect(p.sidebarTabs, ['home', 'search', 'albums', 'songs', 'artists', 'playlists', 'genres', 'favorites', 'downloads']);
    expect(p.mobileTabs, ['home', 'search', 'library']);
  });

  test('migra modo, cor, cor da capa e escala das configurações antigas (e salva)', () async {
    SharedPreferences.setMockInitialValues({
      'ui': jsonEncode({'radius': 20, 'amoled': true}),
      'settings': jsonEncode({'themeMode': 'light', 'seedColor': 0xFF2196F3, 'dynamicColorFromCover': false, 'uiScale': 1.2}),
    });
    final prefs = await SharedPreferences.getInstance();
    final p = UiPrefs.load(prefs);
    expect(p.themeMode, 'light');
    expect(p.seed, 0xFF2196F3);
    expect(p.colorSource, 'accent');
    expect(p.uiScale, 1.2);
    expect((p.radius, p.amoled), (20, true));
    expect(jsonDecode(prefs.getString('ui')!)['themeVersion'], 2);
  });

  test('a cor livre da versão 1 vence a cor da paleta', () async {
    SharedPreferences.setMockInitialValues({
      'ui': jsonEncode({'customColor': 0xFF00BFA5}),
      'settings': jsonEncode({'seedColor': 0xFF2196F3}),
    });
    expect(UiPrefs.load(await SharedPreferences.getInstance()).seed, 0xFF00BFA5);
  });

  test('tema importado com lixo: tudo validado', () {
    final p = UiPrefs.fromJson({
      'backgroundImage': '../../etc/passwd',
      'radius': 999,
      'uiScale': -3,
      'variant': 'evil',
      'themeMode': 42,
      'colors': {'primary': 'red', 'bogus': 1, 'text': 0xFFFFFFFF},
      'sidebarTabs': ['x', 'home', 'home', 'library'],
      'mobileTabs': ['home', 'search', 'albums', 'artists', 'playlists', 'songs'],
      'playerButtons': ['queue', 'rm -rf'],
      'playerButtonsVersion': 2,
    });
    expect(p.backgroundImage, isNull);
    for (final bad in ['..', '.hidden', '/etc/passwd', 'a/b.jpg', r'..\x', 'x' * 200]) {
      expect(UiPrefs.fromJson({'backgroundImage': bad}).backgroundImage, isNull, reason: bad);
    }
    expect(UiPrefs.fromJson({'backgroundImage': 'a1b2c3.jpg'}).backgroundImage, 'a1b2c3.jpg');
    expect(p.radius, 28);
    expect(p.uiScale, 0.8);
    expect(p.variant, 'tonalSpot');
    expect(p.themeMode, 'dark');
    expect(p.colors, {'text': 0xFFFFFFFF});
    expect(p.sidebarTabs, ['home']);
    expect(p.mobileTabs, hasLength(UiPrefs.maxMobileTabs));
    expect(p.playerButtons, ['queue']);
  });

  test('ida e volta do JSON sem perda', () {
    const p = UiPrefs(
      themeMode: 'light',
      variant: 'vibrant',
      contrast: 0.5,
      colors: {'background': 0xFF101010, 'primary': 0xFFFF2E88},
      bodyFont: 'nunito',
      titleFont: 'playfair',
      background: 'image',
      backgroundImage: 'fundo_1.jpg',
      mobileTabs: ['home', 'albums'],
      playerStyle: 'floating',
      transitions: 'fade',
      songTap: 'enqueue',
      themeId: 'user:1',
    );
    final back = UiPrefs.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), jsonEncode(p.toJson()));
  });

  test('trocar de tema mantém o comportamento', () {
    const mine = UiPrefs(songTap: 'enqueue', startPage: '/albums', showQueue: true, radius: 4);
    final other = const UiPrefs(radius: 24, bodyFont: 'spaceGrotesk').themeJson();
    final applied = mine.withTheme(other, id: 'neon');
    expect((applied.radius, applied.bodyFont), (24, 'spaceGrotesk'));
    expect((applied.songTap, applied.startPage, applied.showQueue, applied.themeId), ('enqueue', '/albums', true, 'neon'));
    expect(applied.sameTheme(other), isTrue);
    expect(mine.sameTheme(other), isFalse);
  });
}
