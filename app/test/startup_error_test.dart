import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/ui/startup_error.dart';

void main() {
  testWidgets('motor que não inicia mostra o motivo (sem segredo) em vez de travar', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final h = tester.ensureSemantics();
    await tester.pumpWidget(const StartupErrorApp(error: 'PanicException(driver) http://nd/rest/ping?u=thiago&t=abc'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining('PanicException(driver)'), findsOneWidget);
    expect(find.textContaining('thiago'), findsNothing);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    h.dispose();
  });
}
