import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/ui/shell.dart';

void main() {
  const original = ['home', 'search', 'library'];

  test('abas do celular do jeito original', () {
    expect(mobileSelectedTab('/', original), 0);
    expect(mobileSelectedTab('/search', original), 1);
    expect(mobileSelectedTab('/album/42', original), 2);
    expect(mobileSelectedTab('/songs', original), 2);
    expect(mobileSelectedTab('/settings/look/colors', original), 3);
    expect(mobileSelectedTab('/equalizer', original), 3);
    expect(mobileSelectedTab('/jam', original), 0);
  });

  test('abas escolhidas: a específica vence a Biblioteca', () {
    const mine = ['home', 'albums', 'library', 'playlists'];
    expect(mobileSelectedTab('/album/42', mine), 1);
    expect(mobileSelectedTab('/albums', mine), 1);
    expect(mobileSelectedTab('/playlist/7', mine), 3);
    expect(mobileSelectedTab('/artist/3', mine), 2);
    expect(mobileSelectedTab('/settings', mine), 4);
    expect(mobileSelectedTab('/artist/3', const ['home', 'albums']), 0);
  });

  test('voltar sem histórico', () {
    expect(backTargetFor('/', original), isNull);
    expect(backTargetFor('/search', original), '/');
    expect(backTargetFor('/library', original), '/');
    expect(backTargetFor('/album/42', original), '/library');
    expect(backTargetFor('/settings/look/colors', original), '/settings/look');
    expect(backTargetFor('/settings/playback', original), '/settings');
    expect(backTargetFor('/settings/diagnostics', original), '/settings/about');
    expect(backTargetFor('/equalizer', original), '/settings');
    expect(backTargetFor('/album/42', const ['home', 'albums']), '/albums');
    expect(backTargetFor('/artist/3', const ['home', 'albums']), '/');
  });
}
