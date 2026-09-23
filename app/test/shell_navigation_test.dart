import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:player_musica/ui/actions.dart';

/// Sair da tela cheia do player para uma tela de dentro do shell.
///
/// O `/now-playing` fica fora do `ShellRoute` (é diálogo de tela cheia). Como
/// ele é aberto de uma tela do shell, empurrar dali outra tela do shell deixa
/// dois shells na pilha, com páginas de mesma chave: o Navigator recusa e a
/// tela abre vazia. `goFromPlayer` fecha o player antes.
GoRouter _router({required void Function(BuildContext) abrir}) => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/now-playing',
          pageBuilder: (_, _) => MaterialPage(
            fullscreenDialog: true,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(onPressed: () => abrir(context), child: const Text('abrir ajustes')),
                ),
              ),
            ),
          ),
        ),
        ShellRoute(
          builder: (_, _, child) => Scaffold(body: child),
          routes: [
            GoRoute(path: '/', builder: (_, _) => const Text('início')),
            GoRoute(
              path: '/settings',
              builder: (_, _) => const Text('ajustes'),
              routes: [GoRoute(path: ':section', builder: (_, _) => const Text('recomendações'))],
            ),
          ],
        ),
      ],
    );

Future<void> _ateOPlayer(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  expect(find.text('início'), findsOneWidget);
  // Como no app: o player é aberto de uma tela de dentro do shell.
  router.push('/now-playing');
  await tester.pumpAndSettle();
  expect(find.text('abrir ajustes'), findsOneWidget);
}

void main() {
  testWidgets('abrir uma tela a partir do player mostra o conteúdo', (tester) async {
    final router = _router(abrir: (c) => goFromPlayer(c, '/settings/recommend'));
    await _ateOPlayer(tester, router);

    await tester.tap(find.text('abrir ajustes'));
    await tester.pumpAndSettle();

    expect(find.text('recomendações'), findsOneWidget);
    // O player sai da frente, como em qualquer app de música.
    expect(find.text('abrir ajustes'), findsNothing);
  });
}
