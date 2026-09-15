import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/l10n/l10n.dart';
import 'package:player_musica/ui/pages/settings/sections.dart';
import 'package:player_musica/ui/pages/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Diretrizes de acessibilidade do Flutter nas telas de Ajustes: todo botão
/// com nome para o leitor de tela, área de toque de pelo menos 48 dp e texto
/// com contraste suficiente (WCAG), no tema claro e no escuro.
void main() {
  const sections = ['', 'account', 'playback', 'automix', 'storage', 'sources', 'devices', 'behavior', 'about', 'diagnostics'];

  for (final dark in [false, true]) {
    for (final section in sections) {
      testWidgets('acessível: /settings/$section (${dark ? 'escuro' : 'claro'})', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final handle = tester.ensureSemantics();
        final router = GoRouter(
          initialLocation: section.isEmpty ? '/settings' : '/settings/$section',
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const Scaffold(body: SettingsPage()),
              routes: [
                GoRoute(path: ':section', builder: (_, s) => Scaffold(body: settingsSectionPage(s.pathParameters['section']!))),
              ],
            ),
          ],
        );
        await tester.pumpWidget(ProviderScope(
          overrides: [prefsProvider.overrideWithValue(prefs)],
          child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(colorSchemeSeed: const Color(0xFF6446C9)),
            darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF6446C9), brightness: Brightness.dark),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            locale: const Locale('pt'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
          ),
        ));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }
}
