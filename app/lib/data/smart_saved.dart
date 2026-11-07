import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../domain/models.dart';

/// Um aleatório smart salvo: o estilo que ele tinha aprendido, com um nome,
/// para voltar a ele pela aba "Aleatórios smart" (pedido do usuário,
/// 07/11/2026).
///
/// O que se guarda é o que puxava e o que afastava na hora de salvar — os
/// ímãs com a força de cada um (já descontado o tempo e o que cada um
/// acertou) e as puladas que ainda valiam. Ao voltar, o modo recomeça dali e
/// continua aprendendo (ver `SmartSession.restore`). As marcas dos botões "+"
/// e "−" ficam de fora: elas valem em todo aleatório smart.
@immutable
class SavedSmart {
  const SavedSmart({
    required this.id,
    required this.name,
    required this.liked,
    this.avoid = const [],
    required this.saved,
    this.played,
  });

  final String id;
  final String name;

  /// Os ímãs, do mais forte para o mais fraco.
  final List<(Song, double)> liked;

  /// As puladas que ainda afastavam.
  final List<Song> avoid;

  /// Quando foi salvo (ou atualizado).
  final DateTime saved;

  /// Quando foi tocado pela última vez.
  final DateTime? played;

  /// Até quatro capas diferentes dos ímãs, para o mosaico da lista.
  List<String> get covers {
    final out = <String>[];
    for (final (s, _) in liked) {
      final c = s.coverArt;
      if (c != null && !out.contains(c)) out.add(c);
      if (out.length == 4) break;
    }
    return out;
  }

  /// Os primeiros [n] artistas dos ímãs, sem repetir.
  List<String> artists(int n) {
    final out = <String>[];
    for (final (s, _) in liked) {
      final a = s.displayArtist.trim();
      if (a.isNotEmpty && !out.contains(a)) out.add(a);
      if (out.length == n) break;
    }
    return out;
  }

  /// Nome sugerido: os artistas que mais puxam.
  static String suggestName(List<(Song, double)> liked) =>
      SavedSmart(id: '', name: '', liked: liked, saved: DateTime(2000)).artists(3).join(', ');

  SavedSmart copyWith({String? name, DateTime? played}) => SavedSmart(
        id: id,
        name: name ?? this.name,
        liked: liked,
        avoid: avoid,
        saved: saved,
        played: played ?? this.played,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'liked': [
          for (final (s, w) in liked) {'s': s.toJson(), 'w': w},
        ],
        'avoid': [for (final s in avoid) s.toJson()],
        'saved': saved.millisecondsSinceEpoch,
        if (played != null) 'played': played!.millisecondsSinceEpoch,
      };

  static SavedSmart? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], saved = j['saved'];
    if (id is! String || name is! String || saved is! int) return null;
    final liked = <(Song, double)>[];
    for (final x in (j['liked'] is List ? j['liked'] as List : const [])) {
      if (x is Map && x['s'] is Map && x['w'] is num) {
        liked.add((Song.fromJson(Map<String, dynamic>.from(x['s'] as Map)), (x['w'] as num).toDouble()));
      }
    }
    if (liked.isEmpty) return null;
    final played = j['played'];
    return SavedSmart(
      id: id,
      name: name,
      liked: liked,
      avoid: [
        for (final x in (j['avoid'] is List ? j['avoid'] as List : const []))
          if (x is Map) Song.fromJson(Map<String, dynamic>.from(x)),
      ],
      saved: DateTime.fromMillisecondsSinceEpoch(saved),
      played: played is int ? DateTime.fromMillisecondsSinceEpoch(played) : null,
    );
  }
}

/// Os aleatórios smart salvos desta conta (os ids das músicas são de cada
/// servidor), do usado por último para o mais antigo.
///
/// **Patente** (ver `player/smart_session.dart`): a lista é só do que a pessoa
/// salvou, na ordem em que usou. Nunca ordenar, filtrar nem sugerir estes
/// itens pela parecença com o gosto dela — isso viraria "várias sementes
/// escolhidas pelo perfil para a pessoa escolher uma" (regra 1).
class SavedSmartNotifier extends Notifier<List<SavedSmart>> {
  /// Teto da lista: com mais que isso sai o usado há mais tempo.
  static const max = 100;

  String? _key;

  @override
  List<SavedSmart> build() {
    final account = ref.watch(sessionProvider.select((s) => s.value?.provider.accountId));
    _key = account == null ? null : 'smartSaved.$account';
    final raw = _key == null ? null : ref.watch(prefsProvider).getString(_key!);
    if (raw == null) return const [];
    try {
      final j = jsonDecode(raw);
      return _sorted([
        if (j is List)
          for (final x in j) ?SavedSmart.fromJson(x),
      ]);
    } catch (e) {
      debugPrint('aleatórios smart salvos: $e');
      return const [];
    }
  }

  SavedSmart? byId(String id) => state.where((s) => s.id == id).firstOrNull;

  /// Guarda [s]; se já existe um com o mesmo id, ele é trocado.
  void put(SavedSmart s) => _set([s, ...state.where((x) => x.id != s.id)]);

  void rename(String id, String name) => _set([for (final s in state) s.id == id ? s.copyWith(name: name) : s]);

  void remove(String id) => _set([for (final s in state) if (s.id != id) s]);

  /// Tocou agora: sobe para o topo da lista.
  void touch(String id) => _set([for (final s in state) s.id == id ? s.copyWith(played: DateTime.now()) : s]);

  static DateTime _when(SavedSmart s) => s.played != null && s.played!.isAfter(s.saved) ? s.played! : s.saved;

  static List<SavedSmart> _sorted(List<SavedSmart> l) => [...l]..sort((a, b) => _when(b).compareTo(_when(a)));

  void _set(List<SavedSmart> list) {
    state = _sorted(list).take(max).toList();
    final k = _key;
    if (k != null) ref.read(prefsProvider).setString(k, jsonEncode([for (final s in state) s.toJson()]));
  }
}

final savedSmartProvider = NotifierProvider<SavedSmartNotifier, List<SavedSmart>>(SavedSmartNotifier.new);
