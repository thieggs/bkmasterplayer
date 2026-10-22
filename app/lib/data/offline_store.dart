import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/providers.dart';
import '../domain/models.dart';
import '../player/player_controller.dart';
import '../src/rust/api/engine.dart' as engine;
import '../ui/widgets/cover_art.dart';

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
    this.bitRate = 0,
  });

  final String type; // album | playlist
  final String id;
  final String name;
  final String? artist;
  final String? coverArt;
  final List<Song> songs;
  final String account;

  /// Qualidade com que foi baixada (kbps, MP3; 0 = original). Fica guardada
  /// na coleção: mudar o ajuste depois não pode fazer o que já está no disco
  /// "sumir" (a chave do arquivo no cache depende da qualidade).
  final int bitRate;

  OfflineCollection withBitRate(int b) =>
      OfflineCollection(type: type, id: id, name: name, artist: artist, coverArt: coverArt, songs: songs, account: account, bitRate: b);

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'artist': artist,
        'coverArt': coverArt,
        'account': account,
        'bitRate': bitRate,
        'songs': songs.map((s) => s.toJson()).toList(),
      };

  factory OfflineCollection.fromJson(Map<String, dynamic> j) => OfflineCollection(
        type: j['type'] as String,
        id: j['id'] as String,
        name: j['name'] as String? ?? '?',
        artist: j['artist'] as String?,
        coverArt: j['coverArt'] as String?,
        account: j['account'] as String? ?? '',
        bitRate: j['bitRate'] as int? ?? 0,
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

  List<OfflineCollection>? _idsFor;
  Map<String, int> _ids = const {};
  Set<String> _idSet = const {};

  /// Música baixada -> qualidade da cópia no disco (para tocar a versão
  /// baixada). Em duas coleções com qualidades diferentes, vale a melhor:
  /// original (0) ganha de tudo, senão a taxa maior. Guardado: a biblioteca
  /// inteira pode ter milhares e isto é consultado a cada faixa.
  Map<String, int> get _songBitRates {
    if (!identical(_idsFor, state)) {
      _idsFor = state;
      final m = <String, int>{};
      for (final c in state) {
        for (final s in c.songs) {
          final antes = m[s.id];
          if (antes == null || (antes != 0 && (c.bitRate == 0 || c.bitRate > antes))) m[s.id] = c.bitRate;
        }
      }
      _ids = m;
      _idSet = m.keys.toSet();
    }
    return _ids;
  }

  /// Músicas disponíveis offline.
  Set<String> get songIds {
    _songBitRates;
    return _idSet;
  }

  /// Qualidade da cópia baixada desta música; null se não foi baixada.
  int? bitRateFor(String songId) => _songBitRates[songId];

  /// Músicas para a fila de downloads do motor (as já baixadas ele ignora).
  List<engine.OfflineTrack> _tracks(Iterable<Song> songs, int bitRate) {
    final player = ref.read(playerProvider.notifier);
    return [
      for (final s in songs)
        if (player.sourceFor(s, offline: true, downloadBitRate: bitRate) case final src? when src.cacheKey != null)
          engine.OfflineTrack(
            cacheKey: src.cacheKey!,
            url: src.url,
            title: s.title,
            artist: s.displayArtist,
            sizeBytes: s.size ?? 0,
          ),
    ];
  }

  /// Baixa na qualidade escolhida nos ajustes. Já baixada em outra
  /// qualidade: a cópia velha sai antes, para não ficar ocupando o disco.
  Future<void> add(OfflineCollection c) async {
    c = c.withBitRate(ref.read(settingsProvider).downloadMaxBitRate);
    final antes = state.where((x) => x.id == c.id).firstOrNull;
    if (antes != null && antes.bitRate != c.bitRate) await remove(c.id);
    state = [...state.where((x) => x.id != c.id), c];
    await _save();
    unawaited(_cacheCovers(c.songs));
    await engine.playerDownloadOffline(tracks: _tracks(c.songs, c.bitRate));
  }

  /// Guarda a capa junto com a música.
  ///
  /// Sem isto a capa offline dependia de a pessoa ter aberto o álbum antes
  /// (é o que enche o cache). Baixa no maior tamanho que as telas usam: os
  /// menores saem dele quando faltar (ver `CoverImageProvider.fetchFile`).
  Future<void> _cacheCovers(Iterable<Song> songs) async {
    final provider = ref.read(musicProvider);
    final dir = p.join(ref.read(cacheDirProvider).path, 'ui_covers');
    final ids = {for (final s in songs) s.coverArt}.whereType<String>();
    for (final id in ids) {
      final uri = provider.coverUri(id, size: 600);
      final key = provider.coverCacheKey(id, size: 600);
      if (uri == null || key == null) continue;
      try {
        await CoverImageProvider.fetchFile(url: uri.toString(), cacheKey: key, cacheDir: dir);
      } catch (e) {
        debugPrint('capa offline de $id: $e');
      }
    }
  }

  /// Ao abrir o app (com o login pronto): a fila de downloads é só da memória,
  /// então volta a pedir o que ainda falta das coleções desta conta.
  Future<void> resumePending(String account) async {
    final tracks = [
      for (final c in state)
        if (c.account == account) ..._tracks(c.songs, c.bitRate),
    ];
    if (tracks.isEmpty) return;
    await engine.playerDownloadOffline(tracks: tracks);
  }

  Future<void> remove(String id) async {
    final c = state.where((x) => x.id == id).firstOrNull;
    if (c == null) return;
    state = state.where((x) => x.id != id).toList();
    await _save();
    // Só apaga as músicas que não estão em outra coleção baixada na mesma
    // qualidade (em outra qualidade é outro arquivo).
    final still = {
      for (final x in state)
        if (x.bitRate == c.bitRate) ...x.songs.map((s) => s.id),
    };
    final player = ref.read(playerProvider.notifier);
    final keys = c.songs
        .where((s) => !still.contains(s.id))
        .map((s) => player.sourceFor(s, offline: true, downloadBitRate: c.bitRate)?.cacheKey)
        .whereType<String>()
        .toList();
    await engine.playerRemoveOffline(cacheKeys: keys);
  }

  /// Quantas músicas da coleção já estão no disco.
  Future<int> downloadedCount(OfflineCollection c) async {
    final player = ref.read(playerProvider.notifier);
    final keys =
        c.songs.map((s) => player.sourceFor(s, offline: true, downloadBitRate: c.bitRate)?.cacheKey).whereType<String>().toList();
    final state = await engine.playerCachedState(cacheKeys: keys);
    return state.where((b) => b).length;
  }
}

final offlineProvider = NotifierProvider<OfflineStore, List<OfflineCollection>>(OfflineStore.new);
