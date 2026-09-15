import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/data/recent_searches.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('buscas recentes: a mais nova no topo, sem repetir, com limite, e ficam salvas', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final r = c.read(recentSearchesProvider.notifier);
    r.add('Daft Punk');
    r.add('  ');
    r.add('beatles');
    r.add('daft punk');
    expect(c.read(recentSearchesProvider), ['daft punk', 'beatles']);
    for (var i = 0; i < 20; i++) {
      r.add('busca $i');
    }
    expect(c.read(recentSearchesProvider).length, RecentSearchesNotifier.max);
    expect(c.read(recentSearchesProvider).first, 'busca 19');
    r.remove('busca 19');
    expect(c.read(recentSearchesProvider).first, 'busca 18');

    final again = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    addTearDown(again.dispose);
    expect(again.read(recentSearchesProvider).first, 'busca 18');
    again.read(recentSearchesProvider.notifier).clear();
    expect(prefs.getStringList('recentSearches'), isEmpty);
  });
}
