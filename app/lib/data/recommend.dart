import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/providers.dart';
import '../domain/models.dart';
import 'offline_store.dart';
import '../src/rust/api/recommend.dart' as rust;

/// Jeitos de medir "parecida". A conta de cada um mora no motor
/// (`engine/recommend.rs`); aqui fica só o nome que o app guarda.
enum RecommendStyle {
  sound('sound'),
  mood('mood'),
  genre('genre'),
  era('era'),
  lyrics('lyrics'),
  mix('mix'),
  server('server');

  const RecommendStyle(this.id);
  final String id;

  static RecommendStyle parse(String? id) =>
      RecommendStyle.values.firstWhere((s) => s.id == id, orElse: () => RecommendStyle.sound);
}

class RecommendState {
  const RecommendState({this.songs = 0, this.version, this.downloading = false, this.progress = 0, this.error});

  /// Quantas músicas o arquivo carregado conhece (0 = não há).
  final int songs;
  final String? version;
  final bool downloading;

  /// 0 a 1 enquanto baixa (-1 quando não se sabe o tamanho).
  final double progress;
  final String? error;

  bool get ready => songs > 0;

  RecommendState copyWith({int? songs, String? version, bool? downloading, double? progress, String? error, bool clearError = false}) =>
      RecommendState(
        songs: songs ?? this.songs,
        version: version ?? this.version,
        downloading: downloading ?? this.downloading,
        progress: progress ?? this.progress,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Recomendação no próprio aparelho, com os vetores que o AudioMuse gerou.
///
/// O servidor faz a parte cara (uma rede neural por música) e entrega um
/// arquivo; aqui só se compara, o que leva poucos milissegundos. Vale offline
/// e, mesmo com internet, gasta menos bateria que acordar o rádio para
/// perguntar ao servidor.
class RecommendNotifier extends Notifier<RecommendState> {
  static const _file = 'vetores.bkvec';
  static const _versionKey = 'vetores.versao';

  @override
  RecommendState build() {
    // Ligar a opção baixa; desligar apaga e solta a memória.
    final on = ref.watch(settingsProvider.select((s) => s.recommendOffline));
    if (on) {
      unawaited(sync());
    } else {
      unawaited(forget());
    }
    return const RecommendState();
  }

  File get _path => File(p.join(ref.read(supportDirProvider).path, _file));

  /// Dá para recomendar aqui mesmo? (De fora não se lê o estado direto.)
  bool get ready => state.ready;

  /// Baixa (ou atualiza) o arquivo e deixa pronto para consultar.
  ///
  /// O servidor devolve 304 quando nada mudou, então chamar isto de novo é
  /// barato.
  Future<void> sync({bool force = false}) async {
    if (state.downloading) return;
    final server = ref.read(settingsProvider).analysisServer;
    final provider = ref.read(musicProvider);
    final uri = server == null ? null : provider.analyzerUri(server, '/api/vectors');
    final arquivo = _path;

    // Já tem o arquivo: usa agora, e só então vê se mudou.
    if (!state.ready && await arquivo.exists()) {
      await _load(arquivo);
    }
    if (uri == null) return;

    final prefs = ref.read(prefsProvider);
    final atual = prefs.getString(_versionKey);
    state = state.copyWith(downloading: true, progress: 0, clearError: true);
    final tmp = File('${arquivo.path}.baixando');
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(minutes: 5)));
      final res = await dio.downloadUri(
        uri,
        tmp.path,
        options: Options(
          headers: {if (!force && atual != null && await arquivo.exists()) 'If-None-Match': atual},
          validateStatus: (c) => c == 200 || c == 304,
        ),
        onReceiveProgress: (r, t) => state = state.copyWith(progress: t > 0 ? r / t : -1),
      );
      if (res.statusCode == 304) {
        state = state.copyWith(downloading: false, progress: 0);
        if (!state.ready) await _load(arquivo);
        return;
      }
      await tmp.rename(arquivo.path);
      final versao = res.headers.value('etag');
      if (versao != null) await prefs.setString(_versionKey, versao);
      state = state.copyWith(downloading: false, progress: 0, version: versao);
      await _load(arquivo);
    } catch (e) {
      if (await tmp.exists()) await tmp.delete();
      debugPrint('vetores: $e');
      state = state.copyWith(downloading: false, progress: 0, error: '$e');
    }
  }

  Future<void> _load(File f) async {
    try {
      final n = await rust.recommendLoad(path: f.path);
      state = state.copyWith(songs: n, clearError: true);
    } catch (e) {
      debugPrint('vetores: não deu para ler: $e');
      // Arquivo pela metade ou de outra versão: apaga para baixar de novo.
      if (await f.exists()) await f.delete();
      state = state.copyWith(songs: 0, error: '$e');
    }
  }

  /// Apaga o arquivo e solta a memória.
  Future<void> forget() async {
    try {
      await rust.recommendUnload();
    } catch (_) {
      // Motor ainda não iniciou (testes de tela).
    }
    try {
      final f = _path;
      if (await f.exists()) await f.delete();
      await ref.read(prefsProvider).remove(_versionKey);
    } catch (_) {
      // Sem as pastas do app: não há o que apagar.
    }
    state = const RecommendState();
  }

  /// Esta música tem vetor? Sem ele não dá para recomendar a partir dela.
  Future<bool> knows(String songId) async => state.ready && await rust.recommendKnows(id: songId);

  /// As mais parecidas com [seed], do jeito escolhido nos ajustes.
  ///
  /// [pool] limita o que pode ser sugerido — offline, só o que está baixado,
  /// porque sugerir o que não toca não serve de nada. Sem [pool], vale a
  /// biblioteca toda e as músicas vêm do servidor pelos ids.
  Future<List<Song>> similar(Song seed, {RecommendStyle? style, int count = 50, List<Song>? pool}) async {
    if (!state.ready) return const [];
    final s = style ?? RecommendStyle.parse(ref.read(settingsProvider).recommendStyle);
    final porId = {for (final x in pool ?? const <Song>[]) x.id: x};
    final hits = await rust.recommendSimilar(
      seed: seed.id,
      style: s.id,
      limit: count,
      allowed: porId.keys.toList(),
    );
    final ids = [for (final h in hits) h.id];
    if (ids.isEmpty) return const [];
    if (pool != null) return [for (final id in ids) ?porId[id]];
    try {
      final r = await ref.read(musicProvider).songsByIds(ids);
      if (r.isNotEmpty) return r;
    } catch (e) {
      debugPrint('vetores: não deu para buscar as músicas: $e');
    }
    // Sem servidor (offline): sugere entre as que estão baixadas, que são as
    // únicas que dá para tocar agora.
    final baixadas = downloaded();
    if (baixadas.isEmpty) return const [];
    return similar(seed, style: s, count: count, pool: baixadas);
  }

  /// Músicas que o aparelho tem guardadas para ouvir offline.
  List<Song> downloaded() {
    final porId = <String, Song>{};
    for (final c in ref.read(offlineProvider)) {
      for (final s in c.songs) {
        porId[s.id] = s;
      }
    }
    return porId.values.toList();
  }
}

final recommendProvider = NotifierProvider<RecommendNotifier, RecommendState>(RecommendNotifier.new);
