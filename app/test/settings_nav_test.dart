import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/l10n/l10n.dart';
import 'package:player_musica/ui/pages/settings/sections.dart';
import 'package:player_musica/ui/pages/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Ajustes: cada categoria abre na própria tela e a seta volta', (tester) async {
    // Tela de celular (540×1200).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/settings',
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
        locale: const Locale('pt'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Personalização gráfica'), findsOneWidget);
    await tester.tap(find.text('Comportamento'));
    await tester.pumpAndSettle();
    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Personalização gráfica'), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Personalização gráfica'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });
}
