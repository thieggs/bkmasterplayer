import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/offline_store.dart';
import 'package:player_musica/data/settings.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/l10n/app_localizations.dart';
import 'package:player_musica/ui/pages/offline_page.dart';

void main() {
  test('tamanho da música sobrevive à lista offline salva (o total de MB depende dele)', () {
    const s = Song(id: 's1', title: 'Um', size: 8912345);
    expect(Song.fromJson(s.toJson()).size, 8912345);
    expect(Song.fromJson(const Song(id: 's2', title: 'Dois').toJson()).size, isNull);
  });

  test('downloads ao mesmo tempo ficam entre 1 e 8', () {
    const d = AppSettings();
    expect(d.downloadParallel, 3);
    expect(d.copyWith(downloadParallel: 0).downloadParallel, 1);
    expect(d.copyWith(downloadParallel: 20).downloadParallel, 8);
    expect(AppSettings.fromJson({'downloadParallel': 99}).downloadParallel, 8);
    expect(AppSettings.fromJson(d.copyWith(downloadParallel: 5).toJson()).downloadParallel, 5);
  });

  test('coleção baixada guarda a qualidade; as antigas eram o original', () {
    const songs = [Song(id: 's1', title: 'Um')];
    const c = OfflineCollection(type: 'album', id: 'a', name: 'A', songs: songs, account: 'x', bitRate: 320);
    expect(OfflineCollection.fromJson(c.toJson()).bitRate, 320);
    final velha = c.toJson()..remove('bitRate');
    expect(OfflineCollection.fromJson(velha).bitRate, 0);
  });

  test('de fábrica baixa em MP3 320; a escolha salva fica', () {
    expect(const AppSettings().downloadMaxBitRate, 320);
    expect(AppSettings.fromJson(const AppSettings(downloadMaxBitRate: 0).toJson()).downloadMaxBitRate, 0);
  });

  test('tamanho do download segue a qualidade, não o arquivo original', () {
    const flac = Song(id: 'f', title: 'F', size: 40000000, duration: Duration(minutes: 4));
    expect(downloadBytes(flac, 0), 40000000);
    expect(downloadBytes(flac, 320), 9600000);
    expect(downloadBytes(flac, 128), 3840000);
    const mp3Pequeno = Song(id: 'm', title: 'M', size: 3000000, duration: Duration(minutes: 4));
    expect(downloadBytes(mp3Pequeno, 320), 3000000, reason: 'o servidor não aumenta a taxa do original');
    expect(downloadBytes(const Song(id: 'a', title: 'A', duration: Duration(minutes: 4)), 128), 3840000);
    expect(downloadBytes(const Song(id: 'b', title: 'B', size: 5), 128), 5, reason: 'sem duração, o que se sabe');
    expect(downloadBytes(const Song(id: 'c', title: 'C'), 128), 0);
  });

  group('confirmação de baixar a biblioteca', () {
    const flac = Song(id: 'f', title: 'F', size: 40000000, duration: Duration(minutes: 4));
    const nova = Song(id: 'n', title: 'N', size: 40000000, duration: Duration(minutes: 4));
    int? escolhida;

    Future<void> abre(WidgetTester tester, {required int regra, int? atual, List<Song> faltam = const [flac, nova]}) async {
      escolhida = null;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
            child: const Text('abrir'),
            onPressed: () async => escolhida = await showDialog<int>(
              context: context,
              builder: (_) => DownloadAllDialog(songs: const [flac, nova], pending: faltam, initialBitRate: regra, currentBitRate: atual),
            ),
          );
        })),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Finder texto(String parte) => find.textContaining(parte);

    testWidgets('mostra o tamanho na qualidade da regra e devolve ela', (tester) async {
      await abre(tester, regra: 128);
      expect(find.text('MP3 128 kbps'), findsOneWidget);
      expect(texto('Baixar 2 músicas (cerca de 7,3 MB)'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Baixar'));
      await tester.pumpAndSettle();
      expect(escolhida, 128);
    });

    testWidgets('trocar a qualidade ali mesmo muda o tamanho e o que ela devolve', (tester) async {
      await abre(tester, regra: 0);
      expect(texto('cerca de 76,3 MB'), findsOneWidget, reason: 'original');
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MP3 320 kbps').last);
      await tester.pumpAndSettle();
      expect(texto('cerca de 18,3 MB'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Baixar'));
      await tester.pumpAndSettle();
      expect(escolhida, 320);
    });

    testWidgets('já baixada nessa qualidade: conta só as novas', (tester) async {
      await abre(tester, regra: 320, atual: 320, faltam: const [nova]);
      expect(texto('Baixar 1 música ('), findsOneWidget);
      expect(texto('sai do aparelho'), findsNothing);
    });

    testWidgets('já baixada em outra qualidade: conta tudo e avisa que a cópia velha sai', (tester) async {
      await abre(tester, regra: 320, atual: 0, faltam: const []);
      expect(texto('Baixar 2 músicas'), findsOneWidget);
      expect(texto('O que já baixou em Original (sem conversão) sai do aparelho'), findsOneWidget);
    });

    testWidgets('nada novo: avisa e não deixa baixar', (tester) async {
      await abre(tester, regra: 320, atual: 320, faltam: const []);
      expect(texto('Já está tudo baixado'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Baixar')).onPressed, isNull);
    });

    testWidgets('cancelar não escolhe nada', (tester) async {
      await abre(tester, regra: 320);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(escolhida, isNull);
    });
  });
}
