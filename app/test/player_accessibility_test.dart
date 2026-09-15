import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/connect/connect_service.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/l10n/l10n.dart';
import 'package:player_musica/player/player_controller.dart';
import 'package:player_musica/ui/player/now_playing_page.dart';
import 'package:player_musica/ui/player/player_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player falso (sem o motor): uma música tocando.
class _FakePlayer extends PlayerController {
  @override
  PlayerState build() => const PlayerState(
        queue: [QueueItem('q1', Song(id: 's1', title: 'Música de teste', artist: 'Artista', duration: Duration(minutes: 3)))],
        index: 0,
        playing: true,
        position: Duration(seconds: 42),
        duration: Duration(minutes: 3),
      );
}

class _NoConnect extends ConnectNotifier {
  @override
  List<ConnectDevice> build() => const [];
}

Future<void> _pump(WidgetTester tester, Widget child, Size size, {bool dark = false}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      playerProvider.overrideWith(_FakePlayer.new),
      connectProvider.overrideWith(_NoConnect.new),
    ],
    child: MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6446C9)),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF6446C9), brightness: Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('pt'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _guidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  for (final dark in [false, true]) {
    final tema = dark ? 'escuro' : 'claro';
    testWidgets('acessível: barra do player no computador ($tema)', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, Align(alignment: Alignment.bottomCenter, child: PlayerBar(onToggleQueue: () {}, queueOpen: false)), const Size(1280, 800), dark: dark);
      await _guidelines(tester);
      h.dispose();
    });

    testWidgets('acessível: mini player do celular ($tema)', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, const Align(alignment: Alignment.bottomCenter, child: MiniPlayer()), const Size(400, 800), dark: dark);
      await _guidelines(tester);
      h.dispose();
    });

    testWidgets('acessível: tocando agora no celular ($tema)', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, const NowPlayingPage(), const Size(400, 860), dark: dark);
      await _guidelines(tester);
      h.dispose();
    });
  }
}
