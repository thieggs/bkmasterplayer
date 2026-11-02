import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/ui/actions.dart';

void main() {
  late BuildContext ctx;
  final undone = <String>[];

  void note(String song) => showUndoSnack(ctx, song, undoLabel: 'Desfazer', onUndo: () => undone.add(song));

  Future<void> app(WidgetTester tester) async {
    undone.clear();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
  }

  testWidgets('o aviso some sozinho em 10 s', (tester) async {
    await app(tester);
    note('A');
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text('A'), findsOneWidget, reason: 'ainda dentro dos 10 s');

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
  });

  testWidgets('pular várias seguidas deixa só o último aviso', (tester) async {
    await app(tester);
    note('A');
    await tester.pumpAndSettle();
    note('B');
    await tester.pump();
    note('C');
    await tester.pump();
    note('D');
    await tester.pumpAndSettle();

    expect(find.text('D'), findsOneWidget);
    expect(find.text('B'), findsNothing);
    expect(find.text('C'), findsNothing);

    // Some o último e não sobra ninguém na fila.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('desfazer vale para a música do aviso na tela', (tester) async {
    await app(tester);
    note('A');
    await tester.pumpAndSettle();
    note('B');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(undone, ['B']);
    expect(find.byType(SnackBar), findsNothing);
  });
}
