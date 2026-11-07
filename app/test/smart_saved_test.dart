import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/data/smart_saved.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/l10n/l10n.dart';
import 'package:player_musica/player/player_controller.dart';
import 'package:player_musica/ui/pages/smart_saved_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aleatórios smart salvos: o que se guarda e a aba da biblioteca.

Song _s(String id, {String? artist, String? cover}) =>
    Song(id: id, title: 'Música $id', artist: artist ?? 'Artista $id', coverArt: cover);

SavedSmart _salvo(String id, String name, {DateTime? saved, DateTime? played}) => SavedSmart(
      id: id,
      name: name,
      liked: [(_s('a', artist: 'Zeca', cover: 'c1'), 3.5), (_s('b', artist: 'Cartola', cover: 'c2'), 1.2)],
      avoid: [_s('p')],
      saved: saved ?? DateTime(2026, 11, 7),
      played: played,
    );

/// Lista de mentira, sem conta nem preferências.
class _Lista extends SavedSmartNotifier {
  _Lista(this.inicial);
  final List<SavedSmart> inicial;

  @override
  List<SavedSmart> build() => inicial;
}

/// Player sem o motor, parado.
class _Player extends PlayerController {
  @override
  PlayerState build() => const PlayerState();
}

Future<AppLocalizations> _abre(WidgetTester tester, List<SavedSmart> salvos) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      savedSmartProvider.overrideWith(() => _Lista(salvos)),
      playerProvider.overrideWith(_Player.new),
    ],
    child: MaterialApp(
      locale: const Locale('pt'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const Scaffold(body: SmartSavedPage()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  return AppLocalizations.delegate.load(const Locale('pt'));
}

void main() {
  test('guardado e lido de volta sem perder nada; lixo é ignorado', () {
    final s = _salvo('smart-1', 'Samba', played: DateTime(2026, 11, 8));
    final volta = SavedSmart.fromJson(jsonDecode(jsonEncode(s.toJson())))!;
    expect(volta.id, 'smart-1');
    expect(volta.name, 'Samba');
    expect(volta.liked.map((x) => (x.$1.id, x.$2)), [('a', 3.5), ('b', 1.2)]);
    expect(volta.avoid.map((x) => x.id), ['p']);
    expect(volta.saved, s.saved);
    expect(volta.played, s.played);
    expect(SavedSmart.fromJson('lixo'), isNull);
    expect(SavedSmart.fromJson({'id': 'x', 'name': 'sem ímã', 'saved': 0, 'liked': []}), isNull,
        reason: 'salvo sem nada que puxe não serve para voltar');
  });

  test('nome sugerido e capas saem dos ímãs, sem repetir', () {
    final liked = [
      (_s('1', artist: 'Zeca', cover: 'c1'), 3.0),
      (_s('2', artist: 'Zeca', cover: 'c1'), 2.0),
      (_s('3', artist: 'Cartola', cover: 'c2'), 1.0),
      (_s('4', artist: 'Beth', cover: 'c3'), 1.0),
      (_s('5', artist: 'Alcione', cover: 'c4'), 1.0),
    ];
    expect(SavedSmart.suggestName(liked), 'Zeca, Cartola, Beth');
    final s = SavedSmart(id: 'x', name: 'x', liked: liked, saved: DateTime(2026));
    expect(s.covers, ['c1', 'c2', 'c3', 'c4']);
  });

  testWidgets('aba vazia explica como salvar', (tester) async {
    final l10n = await _abre(tester, const []);
    expect(find.text(l10n.smartSavedTab), findsOneWidget);
    expect(find.text(l10n.smartSavedEmpty), findsOneWidget);
    // Sem aleatório smart tocando, o atalho é começar um.
    expect(find.text(l10n.smartShuffle), findsOneWidget);
  });

  testWidgets('aba lista os salvos; excluir tem desfazer; renomear muda o nome', (tester) async {
    final l10n = await _abre(tester, [_salvo('smart-1', 'Samba de domingo'), _salvo('smart-2', 'Metal')]);
    expect(find.text('Samba de domingo'), findsOneWidget);
    expect(find.text('Metal'), findsOneWidget);
    expect(find.textContaining(l10n.smartSavedCount(2)), findsNWidgets(2));
    expect(find.textContaining('Zeca, Cartola'), findsNWidgets(2));

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.delete));
    await tester.pumpAndSettle();
    expect(find.text('Metal'), findsNothing);
    await tester.tap(find.text(l10n.smartUndo));
    await tester.pumpAndSettle();
    expect(find.text('Metal'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.rename));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pagode');
    await tester.tap(find.text(l10n.ok));
    await tester.pumpAndSettle();
    expect(find.text('Pagode'), findsOneWidget);
  });
}
