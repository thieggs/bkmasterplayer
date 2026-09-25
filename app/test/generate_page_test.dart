import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/l10n/l10n.dart';
import 'package:player_musica/ui/pages/generate_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tela de gerar playlist abre sem servidor (o que acontece ao entrar no
/// app antes de conectar) e os critérios respondem ao toque.
Future<void> _abre(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6446C9)),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF6446C9), brightness: Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('pt'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const Scaffold(body: GeneratePage()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('abre sem servidor e mostra os critérios', (tester) async {
    await _abre(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    expect(find.text(l10n.generatePlaylist), findsOneWidget);
    expect(find.text(l10n.genSeed), findsOneWidget);
    expect(find.text(l10n.genGenre), findsOneWidget);
    expect(find.text(l10n.genDo), findsOneWidget);
  });

  testWidgets('trocar de tempo para número muda as opções', (tester) async {
    await _abre(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    // Por tempo, o padrão.
    expect(find.text(l10n.genMinutes(60)), findsOneWidget);
    await tester.tap(find.text(l10n.genByCount));
    await tester.pumpAndSettle();
    expect(find.text(l10n.genSongs(25)), findsOneWidget);
    expect(find.text(l10n.genMinutes(60)), findsNothing);
  });

  testWidgets('a época só mostra a faixa de anos quando ligada', (tester) async {
    await _abre(tester);
    expect(find.byType(RangeSlider), findsNothing);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.byType(RangeSlider), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('acessível: gerar playlist (${dark ? 'escuro' : 'claro'})', (tester) async {
      final h = tester.ensureSemantics();
      await _abre(tester, dark: dark);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      h.dispose();
    });
  }
}
