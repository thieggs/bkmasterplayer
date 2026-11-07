import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/connect/connect_service.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/data/recommend.dart';
import 'package:player_musica/l10n/l10n.dart';
import 'package:player_musica/player/player_controller.dart';
import 'package:player_musica/ui/player/now_playing_page.dart';
import 'package:player_musica/ui/player/player_bar.dart';
import 'package:player_musica/ui/recommend_style_ui.dart';
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

/// O mesmo, com o aleatório smart ligado: os botões "−" e "+" aparecem.
class _FakeSmartPlayer extends _FakePlayer {
  @override
  PlayerState build() => super.build().copyWith(smart: true);
}

class _NoConnect extends ConnectNotifier {
  @override
  List<ConnectDevice> build() => const [];
}

Future<void> _pump(WidgetTester tester, Widget child, Size size, {bool dark = false, bool smart = false}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      playerProvider.overrideWith(smart ? _FakeSmartPlayer.new : _FakePlayer.new),
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

    // Com os botões do aleatório smart a fileira tem sete botões: no celular
    // estreito (360 dp) ela encolhe para caber, e os botões continuam com
    // área de toque de 48 dp.
    testWidgets('acessível: botões "−" e "+" do aleatório smart no celular estreito ($tema)', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, const NowPlayingPage(), const Size(360, 780), dark: dark, smart: true);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      await _guidelines(tester);
      h.dispose();
    });

    testWidgets('acessível: botões "−" e "+" na barra do computador ($tema)', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, Align(alignment: Alignment.bottomCenter, child: PlayerBar(onToggleQueue: () {}, queueOpen: false)),
          const Size(1024, 700), dark: dark, smart: true);
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      await _guidelines(tester);
      h.dispose();
    });

    testWidgets('acessível: rádio do player ($tema)', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, const NowPlayingPage(), const Size(400, 860), dark: dark);
      await tester.tap(find.byIcon(Icons.radio));
      await tester.pumpAndSettle();
      // As sete maneiras de recomendar, cada uma com nome e explicação.
      final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
      for (final e in RecommendStyle.values) {
        expect(find.text(e.label(l10n)), findsOneWidget, reason: e.id);
      }
      await _guidelines(tester);
      h.dispose();
    });
  }
}
