import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

/// Buscas recentes (só neste aparelho), a mais nova primeiro.
class RecentSearchesNotifier extends Notifier<List<String>> {
  static const _key = 'recentSearches';
  static const max = 12;

  @override
  List<String> build() => ref.watch(prefsProvider).getStringList(_key) ?? const [];

  /// Guarda [query] no topo (sem repetir, sem diferença de maiúsculas).
  void add(String query) {
    final q = query.trim();
    if (q.isEmpty || q.length > 200) return;
    final lower = q.toLowerCase();
    _set([q, ...state.where((s) => s.toLowerCase() != lower)].take(max).toList());
  }

  void remove(String query) => _set(state.where((s) => s != query).toList());

  void clear() => _set(const []);

  void _set(List<String> list) {
    state = list;
    ref.read(prefsProvider).setStringList(_key, list);
  }
}

final recentSearchesProvider = NotifierProvider<RecentSearchesNotifier, List<String>>(RecentSearchesNotifier.new);
