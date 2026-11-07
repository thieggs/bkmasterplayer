import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../domain/models.dart';

/// O que a pessoa marcou com os botões do aleatório smart: "+" (quero mais
/// disso) e "−" (nunca mais esse tipo de música).
///
/// Pedido do usuário (07/11/2026): as marcas valem para sempre, em toda
/// sessão do modo, até a pessoa tirar no painel "O que ele aprendeu". Por isso
/// ficam aqui, à parte da sessão — que recomeça do zero a cada aleatório smart
/// novo. Uma lista por conta: os ids das músicas são de cada servidor.
@immutable
class SmartMarks {
  const SmartMarks({this.more = const [], this.never = const []});

  /// Marcadas com "+", da mais nova para a mais antiga.
  final List<Song> more;

  /// Marcadas com "−", da mais nova para a mais antiga.
  final List<Song> never;

  bool isMore(String id) => more.any((s) => s.id == id);
  bool isNever(String id) => never.any((s) => s.id == id);

  Map<String, dynamic> toJson() => {
    'more': [for (final s in more) s.toJson()],
    'never': [for (final s in never) s.toJson()],
  };

  static SmartMarks fromJson(Object? j) {
    if (j is! Map) return const SmartMarks();
    List<Song> lista(Object? x) => [
      if (x is List)
        for (final s in x)
          if (s is Map) Song.fromJson(Map<String, dynamic>.from(s)),
    ];
    return SmartMarks(more: lista(j['more']), never: lista(j['never']));
  }
}

class SmartMarksNotifier extends Notifier<SmartMarks> {
  /// Teto de cada lista: com mais que isso a marca mais antiga sai.
  static const max = 300;

  String? _key;

  @override
  SmartMarks build() {
    final account = ref.watch(sessionProvider.select((s) => s.value?.provider.accountId));
    _key = account == null ? null : 'smartMarks.$account';
    final raw = _key == null ? null : ref.watch(prefsProvider).getString(_key!);
    if (raw == null) return const SmartMarks();
    try {
      return SmartMarks.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('marcas do aleatório smart: $e');
      return const SmartMarks();
    }
  }

  /// Marca [song] com "+" (e tira o "−", se tinha).
  void more(Song song) => _set(
    SmartMarks(
      more: [song, ...state.more.where((s) => s.id != song.id)].take(max).toList(),
      never: [
        for (final s in state.never)
          if (s.id != song.id) s,
      ],
    ),
  );

  /// Marca [song] com "−" (e tira o "+", se tinha).
  void never(Song song) => _set(
    SmartMarks(
      more: [
        for (final s in state.more)
          if (s.id != song.id) s,
      ],
      never: [song, ...state.never.where((s) => s.id != song.id)].take(max).toList(),
    ),
  );

  /// Tira a marca de [id], seja qual for.
  void unmark(String id) => _set(
    SmartMarks(
      more: [
        for (final s in state.more)
          if (s.id != id) s,
      ],
      never: [
        for (final s in state.never)
          if (s.id != id) s,
      ],
    ),
  );

  void _set(SmartMarks m) {
    state = m;
    final k = _key;
    if (k != null) ref.read(prefsProvider).setString(k, jsonEncode(m.toJson()));
  }
}

final smartMarksProvider = NotifierProvider<SmartMarksNotifier, SmartMarks>(SmartMarksNotifier.new);
