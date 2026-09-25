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
    expect(p.sidebarTabs, ['home', 'search', 'albums', 'songs', 'artists', 'playlists', 'genres', 'generate', 'favorites', 'downloads']);
    expect(p.mobileTabs, ['home', 'search', 'library']);
    // Só vale no layout vinil, que não é o padrão: nada muda para quem não escolheu.
    expect((p.nowPlayingLayout, p.vinylScratch, p.vinylScratchAudio), ('side', true, true));
    expect((p.vinylMaxSpeed, p.vinylSecondsPerTurn), (4.0, 1.8));
    // 0 = a música inteira: voltar girando alcança do fim ao começo.
    expect(p.vinylMemory, 0);
  });

  test('girar o disco: guarda o desligado e ignora lixo', () {
    const off = UiPrefs(vinylScratch: false, vinylScratchAudio: false);
    expect(off.themeJson()['vinylScratch'], false);
    expect(off.themeJson()['vinylScratchAudio'], false);
    final back = UiPrefs.fromJson(off.toJson());
    expect((back.vinylScratch, back.vinylScratchAudio), (false, false));
    expect(UiPrefs.fromJson({'vinylScratch': 'sim', 'vinylScratchAudio': 1}).vinylScratch, isTrue);
  });

  test('limite da agulha: zero é sem limite, o resto cai na faixa', () {
    // Zero não é um valor da faixa (o mínimo é 2): quer dizer sem limite.
    expect(UiPrefs.fromJson({'vinylMaxSpeed': 0}).vinylMaxSpeed, 0);
    expect(UiPrefs.fromJson({'vinylMaxSpeed': 12}).vinylMaxSpeed, 12);
    expect(UiPrefs.fromJson({'vinylMaxSpeed': 999}).vinylMaxSpeed, UiPrefs.maxVinylMaxSpeed);
    expect(UiPrefs.fromJson({'vinylMaxSpeed': 0.5}).vinylMaxSpeed, UiPrefs.minVinylMaxSpeed);
    expect(UiPrefs.fromJson({'vinylMaxSpeed': -3}).vinylMaxSpeed, 0);
    expect(UiPrefs.fromJson({'vinylMaxSpeed': 'rapido'}).vinylMaxSpeed, 4.0);
    const semLimite = UiPrefs(vinylMaxSpeed: 0);
    expect(UiPrefs.fromJson(semLimite.toJson()).vinylMaxSpeed, 0);
  });

  test('quanto dá para voltar girando: a música inteira é o padrão', () {
    expect(UiPrefs.vinylMemoryChoices.first, 0);
    expect(UiPrefs.fromJson({'vinylMemory': 60}).vinylMemory, 60);
    expect(UiPrefs.fromJson({'vinylMemory': 9999}).vinylMemory, 600);
    expect(UiPrefs.fromJson({'vinylMemory': 'tudo'}).vinylMemory, 0);
  });

  test('música por volta do disco fica na faixa do controle', () {
    expect(UiPrefs.fromJson({'vinylSecondsPerTurn': 0.5}).vinylSecondsPerTurn, 0.5);
    expect(UiPrefs.fromJson({'vinylSecondsPerTurn': 0}).vinylSecondsPerTurn, UiPrefs.minVinylSecondsPerTurn);
    expect(UiPrefs.fromJson({'vinylSecondsPerTurn': 90}).vinylSecondsPerTurn, UiPrefs.maxVinylSecondsPerTurn);
    expect(UiPrefs.fromJson({'vinylSecondsPerTurn': 'devagar'}).vinylSecondsPerTurn, 1.8);
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
      'nowPlayingBlur': 'muito',
      'variant': 'evil',
      'themeMode': 42,
      'colors': {'primary': 'red', 'bogus': 1, 'text': 0xFFFFFFFF},
      'sidebarTabs': ['x', 'home', 'home', 'library'],
      'mobileTabs': ['home', 'search', 'albums', 'artists', 'playlists', 'songs'],
      'playerButtons': ['queue', 'rm -rf'],
      'playerButtonsVersion': 2,
    });
    expect(p.backgroundImage, isNull);
    // Número escrito como texto cai no padrão em vez de estourar.
    expect(p.nowPlayingBlur, const UiPrefs().nowPlayingBlur);
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
    expect(p.playerButtons, ['queue', 'sleep'], reason: 'lista da versão 2 ganha o botão novo (timer)');
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
