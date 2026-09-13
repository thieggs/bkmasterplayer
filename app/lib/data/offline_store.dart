import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../domain/models.dart';
import '../player/player_controller.dart';
import '../src/rust/api/engine.dart' as engine;

/// Álbum ou playlist baixado para ouvir offline (com a lista de músicas
/// guardada localmente, para funcionar mesmo sem servidor).
@immutable
class OfflineCollection {
  const OfflineCollection({
    required this.type,
    required this.id,
    required this.name,
    this.artist,
    this.coverArt,
    required this.songs,
    required this.account,
  });

  final String type; // album | playlist
  final String id;
  final String name;
  final String? artist;
  final String? coverArt;
  final List<Song> songs;
  final String account;

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'artist': artist,
        'coverArt': coverArt,
        'account': account,
        'songs': songs.map((s) => s.toJson()).toList(),
      };

  factory OfflineCollection.fromJson(Map<String, dynamic> j) => OfflineCollection(
        type: j['type'] as String,
        id: j['id'] as String,
        name: j['name'] as String? ?? '?',
        artist: j['artist'] as String?,
        coverArt: j['coverArt'] as String?,
        account: j['account'] as String? ?? '',
        songs: (j['songs'] as List).map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

class OfflineStore extends Notifier<List<OfflineCollection>> {
  File get _file => File('${ref.read(supportDirProvider).path}/offline.json');

  @override
  List<OfflineCollection> build() {
    try {
      if (_file.existsSync()) {
        final list = jsonDecode(_file.readAsStringSync()) as List;
        return list.map((e) => OfflineCollection.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      }
    } catch (e) {
      debugPrint('offline.json ilegível: $e');
    }
    return const [];
  }

  Future<void> _save() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(state.map((c) => c.toJson()).toList()));
    await tmp.rename(_file.path);
  }

  bool contains(String id) => state.any((c) => c.id == id);

  /// Músicas disponíveis offline (para tocar a versão baixada).
  Set<String> get songIds => {for (final c in state) ...c.songs.map((s) => s.id)};

  Future<void> add(OfflineCollection c) async {
    state = [...state.where((x) => x.id != c.id), c];
    await _save();
    final player = ref.read(playerProvider.notifier);
    final tracks = c.songs.map((s) => player.sourceFor(s, offline: true)).whereType<engine.TrackSource>().toList();
    await engine.playerDownloadOffline(tracks: tracks);
  }

  Future<void> remove(String id) async {
    final c = state.where((x) => x.id == id).firstOrNull;
    if (c == null) return;
    state = state.where((x) => x.id != id).toList();
    await _save();
    // Só apaga as músicas que não estão em outra coleção baixada.
    final still = songIds;
    final player = ref.read(playerProvider.notifier);
    final keys = c.songs
        .where((s) => !still.contains(s.id))
        .map((s) => player.sourceFor(s, offline: true)?.cacheKey)
        .whereType<String>()
        .toList();
    await engine.playerRemoveOffline(cacheKeys: keys);
  }

  /// Quantas músicas da coleção já estão no disco.
  Future<int> downloadedCount(OfflineCollection c) async {
    final player = ref.read(playerProvider.notifier);
    final keys = c.songs.map((s) => player.sourceFor(s, offline: true)?.cacheKey).whereType<String>().toList();
    final state = await engine.playerCachedState(cacheKeys: keys);
    return state.where((b) => b).length;
  }
}

final offlineProvider = NotifierProvider<OfflineStore, List<OfflineCollection>>(OfflineStore.new);
