import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../connect/connect_service.dart';
import '../core/providers.dart';
import '../data/settings.dart';
import '../data/similar.dart';
import 'dj_mode.dart';
import '../domain/models.dart';
import '../data/offline_store.dart';
import '../domain/music_provider.dart';
import '../src/rust/api/engine.dart' as engine;

/// Resultado da análise (BPM/tom) de uma entrada da fila.
class TrackInsight {
  const TrackInsight({this.bpm, this.key, this.camelot, this.reliable = false, this.detail});
  final double? bpm;
  final String? key;
  final String? camelot;
  final bool reliable;

  /// Por que a batida é (ou não) confiável: uma linha por grade analisada.
  final String? detail;
}

/// Transição de DJ em andamento (para o indicador "Mixando…").
class MixInfo {
  const MixInfo({required this.summary, required this.style, required this.until});
  final String summary;
  final String style;
  final DateTime until;
}

class QueueItem {
  const QueueItem(this.uid, this.song);

  /// Único por entrada na fila (a mesma música pode aparecer duas vezes).
  final String uid;
  final Song song;
}

@immutable
class PlayerState {
  const PlayerState({
    this.queue = const [],
    this.index = -1,
    this.playing = false,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = 0,
    this.repeat = LoopMode.off,
    this.shuffle = false,
    this.volume = 1.0,
    this.message,
    this.insights = const {},
    this.mix,
    this.plannedMix,
    this.plannedSynced = false,
    this.radio = false,
    this.dj = false,
    this.remoteDevice,
    this.remoteDeviceId,
  });

  final List<QueueItem> queue;
  final int index;
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final double buffered;
  final LoopMode repeat;
  final bool shuffle;
  final double volume;

  /// Mensagem para o usuário (erro ao tocar etc.). O shell mostra e limpa.
  final String? message;

  /// BPM/tom analisados, por uid da fila.
  final Map<String, TrackInsight> insights;

  /// Transição de DJ tocando agora.
  final MixInfo? mix;

  /// Resumo da próxima transição planejada.
  final String? plannedMix;

  /// A próxima transição é sincronizada (batidas casadas) ou simples.
  final bool plannedSynced;

  /// Rádio infinita: quando a fila acaba, completa com músicas parecidas.
  final bool radio;

  /// Modo DJ: a próxima é escolhida pelo melhor encaixe (AudioMuse + AutoMix).
  final bool dj;

  /// Controlando outro aparelho (BKmasterplayer Connect): nome e id dele. O estado
  /// acima é o de lá.
  final String? remoteDevice;
  final String? remoteDeviceId;

  QueueItem? get current => index >= 0 && index < queue.length ? queue[index] : null;
  bool get hasNext => index + 1 < queue.length || repeat != LoopMode.off;

  PlayerState copyWith({
    List<QueueItem>? queue,
    int? index,
    bool? playing,
    bool? buffering,
    Duration? position,
    Duration? duration,
    double? buffered,
    LoopMode? repeat,
    bool? shuffle,
    double? volume,
    String? message,
    bool clearMessage = false,
    Map<String, TrackInsight>? insights,
    MixInfo? mix,
    bool clearMix = false,
    String? plannedMix,
    bool? plannedSynced,
    bool clearPlanned = false,
    bool? radio,
    bool? dj,
  }) =>
      PlayerState(
        dj: dj ?? this.dj,
        remoteDevice: remoteDevice,
        remoteDeviceId: remoteDeviceId,
        queue: queue ?? this.queue,
        index: index ?? this.index,
        playing: playing ?? this.playing,
        buffering: buffering ?? this.buffering,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        buffered: buffered ?? this.buffered,
        repeat: repeat ?? this.repeat,
        shuffle: shuffle ?? this.shuffle,
        volume: volume ?? this.volume,
        message: clearMessage ? null : (message ?? this.message),
        insights: insights ?? this.insights,
        mix: clearMix ? null : (mix ?? this.mix),
        plannedMix: clearPlanned ? null : (plannedMix ?? this.plannedMix),
        plannedSynced: clearPlanned ? false : (plannedSynced ?? this.plannedSynced),
        radio: radio ?? this.radio,
      );
}

/// Formatos que o motor ainda não decodifica.
const _undecodable = {'opus', 'wma', 'ape', 'wv', 'dsf', 'dff', 'mpc', 'tta', 'ac3', 'dts'};

class PlayerController extends Notifier<PlayerState> {
  StreamSubscription<engine.PlayerEvent>? _sub;
  int _uidSeq = 0;
  List<QueueItem>? _unshuffled;
  String? _scheduledKey;

  // Scrobble
  String? _scrobbleUid;
  Duration _listened = Duration.zero;
  Duration _lastPos = Duration.zero;
  DateTime? _startedAt;
  bool _submitted = false;

  @override
  PlayerState build() {
    _sub = engine.playerEvents().listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());
    final volume = ref.read(settingsProvider).volume;
    engine.playerSetVolume(volume: _gain(volume));
    // Se as regras de transição mudarem (crossfade, ReplayGain), reagenda a próxima.
    ref.listen(settingsProvider, (prev, next) {
      if (prev?.crossfadeSeconds != next.crossfadeSeconds ||
          prev?.replayGainMode != next.replayGainMode ||
          prev?.replayGainPreampDb != next.replayGainPreampDb ||
          prev?.automixEnabled != next.automixEnabled ||
          prev?.automixRespectAlbums != next.automixRespectAlbums ||
          prev?.analysisServer != next.analysisServer) {
        if (prev?.automixEnabled != next.automixEnabled) state = state.copyWith(clearPlanned: true);
        _scheduledKey = null;
        _scheduleNext();
      }
    });
    // Trocou entre o endereço de casa e o principal: a próxima faixa vai pelo novo.
    ref.listen(endpointProvider, (_, _) {
      _scheduledKey = null;
      _scheduleNext();
    });
    ref.listen(sessionProvider, (_, next) {
      final account = next.value?.provider.accountId;
      if (account != null && _accountId != null && account != _accountId) {
        // Outra conta (ou do servidor para as músicas do aparelho): a fila
        // antiga não toca aqui; carrega a desta conta.
        _mixTimer?.cancel();
        engine.playerStop();
        _engineHasTrack = false;
        _unshuffled = null;
        _scheduledKey = null;
        state = PlayerState(volume: state.volume);
        _restored = false;
      }
      if (account != null) _accountId = account;
      if (next.value != null && !_restored) {
        _restored = true;
        // Depois do build: com o login já pronto, isto dispara durante o
        // build, quando o estado ainda não existe (a restauração falhava calada).
        Future.microtask(() => _restore().whenComplete(() {
              if (!_restoredDone.isCompleted) _restoredDone.complete();
            }));
      }
    }, fireImmediately: true);
    ref.onDispose(() {
      _saveTimer?.cancel();
      _syncTimer?.cancel();
    });
    return PlayerState(volume: volume);
  }

  // ---- Fila salva (disco) e sincronizada (servidor) ----

  bool _restored = false;
  final _restoredDone = Completer<void>();
  String? _accountId;

  /// Completa quando a fila salva da conta foi carregada (ou não havia).
  Future<void> get restored => _restoredDone.future;
  Duration? _resumeAt;
  Timer? _saveTimer;
  Timer? _syncTimer;
  DateTime _lastPositionSave = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastServerSync = DateTime.fromMillisecondsSinceEpoch(0);

  File get _queueFile => File('${ref.read(supportDirProvider).path}/queue.json');

  void _persistSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _persistNow);
    _syncSoon();
  }

  Future<void> _saveChain = Future.value();

  /// Um salvamento por vez: dois ao mesmo tempo disputavam o arquivo
  /// temporário (o segundo não achava o que renomear).
  Future<void> _persistNow() => _saveChain = _saveChain.then((_) => _writeQueue());

  Future<void> _writeQueue() async {
    final p = _provider;
    if (p == null) return;
    // Guarda até 1000 faixas em volta da atual.
    final start = max(0, state.index - 200);
    final items = state.queue.skip(start).take(1000).toList();
    final data = {
      'account': p.accountId,
      'index': state.index - start,
      'position': state.position.inMilliseconds,
      'radio': state.radio,
      'dj': state.dj,
      'queue': items.map((q) => q.song.toJson()).toList(),
    };
    try {
      final tmp = File('${_queueFile.path}.tmp');
      await tmp.writeAsString(jsonEncode(data));
      await tmp.rename(_queueFile.path);
    } catch (e) {
      debugPrint('salvando fila: $e');
    }
  }

  void _syncSoon() {
    if (!ref.read(settingsProvider).syncQueue) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 5), _syncNow);
  }

  Future<void> _syncNow() async {
    final p = _provider;
    final cur = state.current;
    if (p == null || cur == null || !ref.read(settingsProvider).syncQueue) return;
    _lastServerSync = DateTime.now();
    final start = max(0, state.index - 100);
    final ids = state.queue.skip(start).take(500).map((q) => q.song.id).toList();
    try {
      await p.savePlayQueue(ids, current: cur.song.id, position: state.position);
    } catch (_) {}
  }

  Future<void> _restore() async {
    final p = _provider;
    if (p == null || state.queue.isNotEmpty) return;
    List<Song>? songs;
    int index = 0;
    Duration position = Duration.zero;
    var radio = false;
    var dj = false;
    try {
      if (await _queueFile.exists()) {
        final j = jsonDecode(await _queueFile.readAsString()) as Map<String, dynamic>;
        if (j['account'] == p.accountId) {
          songs = (j['queue'] as List).map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          index = (j['index'] as int?) ?? 0;
          position = Duration(milliseconds: (j['position'] as int?) ?? 0);
          radio = j['radio'] == true;
          dj = j['dj'] == true;
        }
      }
    } catch (e) {
      debugPrint('fila salva ilegível: $e');
    }
    if ((songs == null || songs.isEmpty) && ref.read(settingsProvider).syncQueue) {
      final remote = await p.playQueue();
      if (remote != null) {
        songs = remote.songs;
        index = max(0, remote.songs.indexWhere((s) => s.id == remote.current));
        position = remote.position;
      }
    }
    if (songs == null || songs.isEmpty || state.queue.isNotEmpty) return;
    final items = songs.map(_item).toList();
    index = index.clamp(0, items.length - 1);
    _resumeAt = position;
    state = state.copyWith(
      queue: items,
      index: index,
      position: position,
      duration: items[index].song.duration ?? Duration.zero,
      radio: radio,
      dj: dj,
    );
  }

  // ---- Rádio infinita ----

  bool _extending = false;

  void toggleRadio() {
    if (_fwd('radio', {'on': !state.radio})) return;
    state = state.copyWith(radio: !state.radio);
    _persistSoon();
    _maybeExtendRadio();
  }

  void setRadio(bool on) {
    if (_fwd('radio', {'on': on})) return;
    state = state.copyWith(radio: on);
    _maybeExtendRadio();
  }

  /// Com a rádio ligada e a fila acabando, completa com músicas parecidas com
  /// a última (análise sônica do AudioMuse quando o servidor tem; senão o
  /// "similar" do servidor; em último caso, aleatórias).
  Future<void> _maybeExtendRadio() async {
    if (!state.radio || _extending || state.queue.isEmpty) return;
    if (state.queue.length - state.index - 1 > 2) return;
    final p = _provider;
    if (p == null) return;
    _extending = true;
    try {
      final seed = state.queue.last.song;
      var songs = <Song>[];
      if (p.serverInfo?.sonicSimilarity ?? false) {
        songs = (await p.sonicSimilar(seed.id, count: 40)).map((m) => m.song).toList();
      }
      if (songs.isEmpty) {
        final s = ref.read(settingsProvider);
        songs = await findSimilar(p, seed, count: 40, lastFm: s.lastFmForRadio ? ref.read(lastFmProvider) : null);
      }
      if (songs.isEmpty) songs = await p.randomSongs(size: 20);
      final seen = state.queue.map((q) => q.song.id).toSet();
      final lastArtist = seed.artistId;
      // Evita repetir e alterna artistas quando possível.
      final fresh = songs.where((s) => !seen.contains(s.id)).toList()
        ..sort((a, b) => (a.artistId == lastArtist ? 1 : 0) - (b.artistId == lastArtist ? 1 : 0));
      if (fresh.isNotEmpty) enqueue(fresh.take(10).toList());
    } catch (e) {
      debugPrint('rádio: $e');
    } finally {
      _extending = false;
    }
  }

  MusicProvider? get _provider {
    try {
      return ref.read(musicProvider);
    } catch (_) {
      return null;
    }
  }

  QueueItem _item(Song s) => QueueItem('q${_uidSeq++}-${s.id}', s);

  // ---- Comandos da fila ----

  void playSongs(List<Song> songs, {int start = 0, bool shuffle = false}) {
    if (songs.isEmpty) return;
    if (_fwd('playSongs', {'songs': _json(songs), 'start': start, 'shuffle': shuffle})) return;
    var items = songs.map(_item).toList();
    var startIndex = start.clamp(0, items.length - 1);
    _unshuffled = null;
    if (shuffle) {
      _unshuffled = List.of(items);
      final first = items.removeAt(startIndex);
      items.shuffle(Random());
      items.insert(0, first);
      startIndex = 0;
    }
    // Lista nova escolhida: o Modo DJ só continua se foi ele que começou.
    state = state.copyWith(queue: items, shuffle: shuffle, clearMessage: true, dj: _startingDj);
    _startAt(startIndex);
  }

  /// Toque numa música de uma lista, conforme a preferência do usuário.
  void playFrom(List<Song> songs, int index) {
    switch (ref.read(uiPrefsProvider).songTap) {
      case 'playOne':
        playSongs([songs[index]]);
      case 'enqueue':
        enqueue([songs[index]]);
      default:
        playSongs(songs, start: index);
    }
  }

  void enqueue(List<Song> songs) {
    if (songs.isEmpty) return;
    if (_fwd('enqueue', {'songs': _json(songs)})) return;
    final items = songs.map(_item).toList();
    _unshuffled?.addAll(items);
    state = state.copyWith(queue: [...state.queue, ...items]);
    if (state.current == null) {
      _startAt(state.queue.length - items.length);
    } else {
      _scheduleNext();
    }
  }

  void playNext(List<Song> songs) {
    if (songs.isEmpty) return;
    if (_fwd('playNext', {'songs': _json(songs)})) return;
    final items = songs.map(_item).toList();
    final q = List.of(state.queue)..insertAll(state.index + 1, items);
    _unshuffled?.addAll(items);
    state = state.copyWith(queue: q);
    if (state.current == null) {
      _startAt(state.index + 1);
    } else {
      _scheduleNext();
    }
  }

  void jumpTo(int i) {
    if (_fwd('jump', {'i': i})) return;
    if (i < 0 || i >= state.queue.length) return;
    _startAt(i);
  }

  void removeAt(int i) {
    if (_fwd('remove', {'i': i})) return;
    if (i < 0 || i >= state.queue.length) return;
    final removed = state.queue[i];
    final q = List.of(state.queue)..removeAt(i);
    _unshuffled?.removeWhere((e) => e.uid == removed.uid);
    if (i == state.index) {
      state = state.copyWith(queue: q);
      if (i < q.length) {
        _startAt(i);
      } else {
        stop();
        state = state.copyWith(index: -1);
      }
      return;
    }
    state = state.copyWith(queue: q, index: i < state.index ? state.index - 1 : state.index);
    _scheduleNext();
  }

  void move(int from, int to) {
    if (from == to) return;
    if (_fwd('move', {'from': from, 'to': to})) return;
    final q = List.of(state.queue);
    final item = q.removeAt(from);
    q.insert(to, item);
    final currentUid = state.current?.uid;
    state = state.copyWith(queue: q, index: q.indexWhere((e) => e.uid == currentUid));
    _scheduleNext();
  }

  void clearUpcoming() {
    if (_fwd('clearUpcoming')) return;
    if (state.current == null) return;
    state = state.copyWith(queue: state.queue.sublist(0, state.index + 1));
    _scheduleNext();
  }

  void toggleShuffle() {
    if (_fwd('shuffle')) return;
    final cur = state.current;
    if (!state.shuffle) {
      _unshuffled = List.of(state.queue);
      final upcoming = state.queue.sublist(state.index + 1)..shuffle(Random());
      state = state.copyWith(queue: [...state.queue.sublist(0, state.index + 1), ...upcoming], shuffle: true);
    } else {
      final original = _unshuffled ?? state.queue;
      _unshuffled = null;
      state = state.copyWith(
        queue: original,
        shuffle: false,
        index: cur == null ? -1 : original.indexWhere((e) => e.uid == cur.uid),
      );
    }
    _scheduleNext();
  }

  void cycleRepeat() {
    if (_fwd('repeat')) return;
    final next = LoopMode.values[(state.repeat.index + 1) % LoopMode.values.length];
    state = state.copyWith(repeat: next);
    _scheduleNext();
  }

  // ---- Transporte ----

  void toggle() {
    if (_fwd('toggle')) return;
    if (state.current == null) return;
    if (!state.playing && !state.buffering && !_engineHasTrack) {
      final at = _resumeAt ?? Duration.zero;
      _resumeAt = null;
      _startAt(state.index, start: at);
      return;
    }
    engine.playerToggle();
  }

  void play() {
    if (_fwd('play')) return;
    if (!state.playing) toggle();
  }

  void pause() {
    if (_fwd('pause')) return;
    engine.playerPause();
    _persistSoon();
  }

  void stop() {
    if (_fwd('stop')) return;
    engine.playerStop();
    state = state.copyWith(playing: false, position: Duration.zero);
  }

  void next() {
    if (_fwd('next')) return;
    final n = _nextIndex(manual: true);
    if (n != null) _startAt(n);
  }

  void previous() {
    if (_fwd('previous')) return;
    if (state.position > const Duration(seconds: 3) || state.index <= 0) {
      seek(Duration.zero);
      return;
    }
    _startAt(state.index - 1);
  }

  void seek(Duration to) {
    if (_fwd('seek', {'ms': to.inMilliseconds})) {
      state = state.copyWith(position: to);
      return;
    }
    engine.playerSeek(positionMs: to.inMilliseconds);
    state = state.copyWith(position: to);
    _lastPos = to;
  }

  void seekBy(Duration delta) => seek(state.position + delta < Duration.zero ? Duration.zero : state.position + delta);

  void setVolume(double v) {
    final vol = v.clamp(0.0, 1.0);
    if (_fwd('vol', {'v': vol})) {
      state = state.copyWith(volume: vol);
      return;
    }
    engine.playerSetVolume(volume: _gain(vol));
    state = state.copyWith(volume: vol);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(volume: vol));
  }

  /// Abaixa o volume por um tempo (outro app pediu, ex.: navegação do GPS),
  /// sem mexer no volume salvo.
  void duck(bool on) => engine.playerSetVolume(volume: _gain(state.volume) * (on ? 0.3 : 1.0));

  /// Curva perceptual: o slider linear vira ganho ~cúbico.
  static double _gain(double v) => v * v * v;

  void consumeMessage() => state = state.copyWith(clearMessage: true);

  // ---- Internos ----

  bool _engineHasTrack = false;

  int? _nextIndex({bool manual = false}) {
    if (state.queue.isEmpty) return null;
    if (state.repeat == LoopMode.one && !manual) return state.index;
    if (state.index + 1 < state.queue.length) return state.index + 1;
    if (state.repeat != LoopMode.off) return 0;
    return null;
  }

  void _startAt(int i, {Duration start = Duration.zero}) {
    final item = state.queue[i];
    final src = _source(item);
    if (src == null) return;
    _resumeAt = null;
    _persistSoon();
    // Trocou na mão: a mixagem em andamento e a planejada deixam de valer.
    _mixTimer?.cancel();
    state = state.copyWith(
      index: i,
      position: start,
      duration: item.song.duration ?? Duration.zero,
      buffered: 0,
      clearMix: true,
      clearPlanned: true,
    );
    _scheduledKey = null;
    engine.playerPlay(track: src, startMs: start.inMilliseconds);
    _scheduleNext();
  }

  void _scheduleNext() {
    _persistSoon();
    final cur = state.current;
    final n = cur == null ? null : _nextIndex();
    final next = n == null ? null : state.queue[n];
    final mode = (cur != null && next != null) ? _transition(cur, next) : const engine.TransitionMode.gapless();
    final key = next == null ? 'none' : '${next.uid}|$mode';
    if (key == _scheduledKey) return;
    _scheduledKey = key;
    engine.playerSetNext(track: next == null ? null : _source(next), mode: mode);
  }

  engine.TransitionMode _transition(QueueItem cur, QueueItem next) {
    final s = ref.read(settingsProvider);
    final a = cur.song, b = next.song;
    final albumSequence = a.albumId != null &&
        a.albumId == b.albumId &&
        (a.disc ?? 1) == (b.disc ?? 1) &&
        a.track != null &&
        b.track == a.track! + 1;
    if (s.automixEnabled && cur.uid != next.uid) {
      // Álbum em ordem: o motor emenda sem pausa se o álbum for contínuo (ao
      // vivo, mixado, conceitual) e mixa se houver silêncio entre as faixas.
      return albumSequence && s.automixRespectAlbums
          ? const engine.TransitionMode.automixAlbum()
          : const engine.TransitionMode.automix();
    }
    if (s.crossfadeSeconds > 0 && !albumSequence) {
      return engine.TransitionMode.crossfade(ms: s.crossfadeSeconds * 1000);
    }
    return const engine.TransitionMode.gapless();
  }

  bool _albumContext(QueueItem item) {
    final i = state.queue.indexWhere((e) => e.uid == item.uid);
    if (i < 0) return false;
    bool same(int j) => j >= 0 && j < state.queue.length && state.queue[j].song.albumId == item.song.albumId;
    return item.song.albumId != null && (same(i - 1) || same(i + 1));
  }

  (double, double?) _replayGain(QueueItem item) {
    final s = ref.read(settingsProvider);
    final rg = item.song.replayGain;
    if (s.replayGainMode == ReplayGainMode.off || rg == null) return (0, null);
    final album = s.replayGainMode == ReplayGainMode.album ||
        (s.replayGainMode == ReplayGainMode.auto && _albumContext(item));
    final gain = album ? (rg.albumGain ?? rg.trackGain) : (rg.trackGain ?? rg.albumGain);
    final peak = album ? (rg.albumPeak ?? rg.trackPeak) : (rg.trackPeak ?? rg.albumPeak);
    return ((gain ?? rg.fallbackGain ?? 0) + (rg.baseGain ?? 0) + s.replayGainPreampDb, peak);
  }

  engine.TrackSource? _source(QueueItem item) => sourceFor(item.song, uid: item.uid, gain: _replayGain(item));

  /// Fonte de uma música para o motor. Músicas baixadas para ouvir offline
  /// sempre usam o arquivo original ("raw"), para achar o download mesmo que
  /// a qualidade de streaming mude depois.
  engine.TrackSource? sourceFor(Song song, {String? uid, (double, double?)? gain, bool offline = false}) {
    final (g0, peak0) = gain ?? (0.0, null);
    final path = song.path;
    if (path != null) {
      // Arquivo no aparelho: o motor lê direto, sem cache.
      final cover = song.coverArt;
      return engine.TrackSource(
        id: uid ?? song.id,
        url: path,
        formatHint: song.suffix,
        durationMs: song.duration?.inMilliseconds,
        gainDb: g0,
        peak: peak0,
        title: song.title,
        artist: song.displayArtist,
        album: song.album ?? '',
        coverUrl: cover != null && cover.startsWith('/') ? cover : null,
        analysisKey: 'file:$path:${song.size ?? 0}',
      );
    }
    final p = _provider;
    if (p == null) return null;
    final s = ref.read(settingsProvider);
    final raw = offline || ref.read(offlineProvider.notifier).songIds.contains(song.id);
    // Formato que o motor não decodifica (Opus etc.): o servidor converte, até no download.
    final convert = _undecodable.contains(song.suffix?.toLowerCase());
    final format = convert ? (s.transcodeFormat ?? 'mp3') : (raw ? null : s.transcodeFormat);
    final bitrate = raw && !convert ? null : (s.maxBitRate > 0 ? s.maxBitRate : null);
    final (g, peak) = gain ?? (0.0, null);
    // Análise pronta no servidor de análise: só se o arquivo tocado é o mesmo
    // que ele analisou (o original, ou o MP3 que o servidor converte dos
    // formatos que o motor não lê), senão as batidas podem estar deslocadas.
    final server = s.analysisServer;
    final sameFile = bitrate == null && (format == null || (convert && format == 'mp3'));
    final analysisUrl = server != null && sameFile ? p.analyzerUri(server, '/api/analysis/${Uri.encodeComponent(song.id)}')?.toString() : null;
    return engine.TrackSource(
      id: uid ?? song.id,
      url: p.streamUri(song, format: format, maxBitRate: bitrate).toString(),
      cacheKey: p.streamCacheKey(song, format: format, maxBitRate: bitrate),
      formatHint: format ?? song.suffix,
      durationMs: song.duration?.inMilliseconds,
      gainDb: g,
      peak: peak,
      title: song.title,
      artist: song.displayArtist,
      album: song.album ?? '',
      coverUrl: p.coverUri(song.coverArt, size: 600)?.toString(),
      coverKey: p.coverCacheKey(song.coverArt, size: 600),
      analysisKey: '${p.accountId}:song:${song.id}',
      analysisUrl: analysisUrl,
    );
  }

  void _onEvent(engine.PlayerEvent e) {
    // Controlando outro aparelho: o motor daqui está parado.
    if (_remote != null) return;
    switch (e) {
      case engine.PlayerEvent_TrackStarted(:final id):
        final i = state.queue.indexWhere((q) => q.uid == id);
        if (i >= 0) {
          final item = state.queue[i];
          state = state.copyWith(
            index: i,
            position: Duration.zero,
            duration: item.song.duration ?? Duration.zero,
          );
          _scheduleNext();
          _beginScrobble(item);
          _preAnalyze(i);
          if (state.dj) {
            _djExtend();
          } else {
            _maybeExtendRadio();
          }
        }
      case engine.PlayerEvent_TrackEnded(:final id, :final error):
        if (error != null) {
          final title = state.queue.where((q) => q.uid == id).firstOrNull?.song.title ?? '';
          state = state.copyWith(message: 'Não foi possível tocar "$title": $error');
        }
      case engine.PlayerEvent_Position(:final id, :final positionMs, :final durationMs, :final buffered):
        if (state.current?.uid != id) return;
        final pos = Duration(milliseconds: positionMs);
        _trackListening(pos);
        final now = DateTime.now();
        if (now.difference(_lastPositionSave) > const Duration(seconds: 15)) {
          _lastPositionSave = now;
          _persistNow();
        }
        if (now.difference(_lastServerSync) > const Duration(seconds: 60)) {
          _syncSoon();
        }
        state = state.copyWith(
          position: pos,
          duration: durationMs != null ? Duration(milliseconds: durationMs) : state.duration,
          buffered: buffered ?? state.buffered,
        );
      case engine.PlayerEvent_State(:final playing, :final buffering, :final hasTrack):
        _engineHasTrack = hasTrack;
        state = state.copyWith(playing: playing, buffering: buffering);
        if (!hasTrack && state.current != null && _nextIndex() == null) {
          // Fim da fila.
          state = state.copyWith(position: Duration.zero, playing: false);
        }
      case engine.PlayerEvent_MediaControl(:final action):
        _onMediaAction(action);
      case engine.PlayerEvent_DeviceChanged():
        break;
      case engine.PlayerEvent_Error(:final message):
        state = state.copyWith(message: message);
      case engine.PlayerEvent_Analysis(:final id, :final bpm, :final key, :final camelot, :final reliable, :final detail):
        final insight = TrackInsight(bpm: bpm, key: key, camelot: camelot, reliable: reliable, detail: detail);
        // Candidatas do Modo DJ: só a espera, sem mexer no estado da fila.
        final waiter = _analysisWaiters.remove(id);
        if (waiter != null) {
          waiter.complete(insight);
        } else {
          state = state.copyWith(insights: {...state.insights, id: insight});
        }
      case engine.PlayerEvent_MixPlanned(:final summary, :final beatmatched):
        state = state.copyWith(plannedMix: summary, plannedSynced: beatmatched);
      case engine.PlayerEvent_MixStarted(:final summary, :final style, :final durationMs):
        final until = DateTime.now().add(Duration(milliseconds: durationMs));
        state = state.copyWith(mix: MixInfo(summary: summary, style: style, until: until), clearPlanned: true);
        _mixTimer?.cancel();
        _mixTimer = Timer(Duration(milliseconds: durationMs), () => state = state.copyWith(clearMix: true));
    }
  }

  Timer? _mixTimer;

  /// Pré-análise das próximas faixas da fila (AutoMix pronto na hora da troca).
  void _preAnalyze(int index) {
    final s = ref.read(settingsProvider);
    if (!s.automixEnabled || !s.preAnalyze) return;
    for (var j = index + 2; j < state.queue.length && j <= index + 3; j++) {
      final src = _source(state.queue[j]);
      if (src != null) engine.playerAnalyze(track: src);
    }
  }

  void _onMediaAction(engine.MediaAction a) {
    switch (a) {
      case engine.MediaAction_Play():
        play();
      case engine.MediaAction_Pause():
        pause();
      case engine.MediaAction_Toggle():
        toggle();
      case engine.MediaAction_Next():
        next();
      case engine.MediaAction_Previous():
        previous();
      case engine.MediaAction_Stop():
        stop();
      case engine.MediaAction_SeekTo(:final positionMs):
        seek(Duration(milliseconds: positionMs));
      case engine.MediaAction_SeekBy(:final deltaMs):
        seekBy(Duration(milliseconds: deltaMs));
      case engine.MediaAction_SetVolume(:final volume):
        setVolume(volume);
      case engine.MediaAction_Raise():
        if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
          windowManager.show();
          windowManager.focus();
        }
      case engine.MediaAction_Quit():
        exit(0);
    }
  }

  // ---- Modo DJ ----

  bool _startingDj = false;
  bool _djBusy = false;
  final _djHeard = <String>{};
  final _analysisWaiters = <String, Completer<TrackInsight>>{};

  /// Começa pelo [seed] e deixa o AudioMuse e o AutoMix escolherem as próximas.
  void startDj(Song seed) {
    if (_remote != null) return;
    ref.read(settingsProvider.notifier).update((s) => s.automixEnabled ? s : s.copyWith(automixEnabled: true));
    _djHeard.clear();
    _startingDj = true;
    playSongs([seed]);
    _startingDj = false;
    state = state.copyWith(dj: true, radio: false);
    _djExtend();
  }

  void setDj(bool on) {
    state = state.copyWith(dj: on, radio: on ? false : state.radio);
    _persistSoon();
    if (on) _djExtend();
  }

  /// Análise de uma candidata (BPM/tom) pelo motor do AutoMix; null se demorar.
  Future<TrackInsight?> _analyzeFor(Song song, Duration wait) async {
    final id = 'dj:${song.id}';
    final src = sourceFor(song, uid: id);
    if (src == null) return null;
    final c = Completer<TrackInsight>();
    _analysisWaiters[id] = c;
    engine.playerAnalyze(track: src);
    return c.future.timeout(wait, onTimeout: () {
      _analysisWaiters.remove(id);
      return const TrackInsight();
    });
  }

  /// Dá para analisar sem gastar dados móveis (arquivo no aparelho ou já no cache)?
  Future<bool> _freeToAnalyze(Song song) async {
    if (song.path != null) return true;
    final key = sourceFor(song)?.cacheKey;
    try {
      return key != null && await engine.playerIsCached(cacheKey: key);
    } catch (_) {
      return false;
    }
  }

  /// Escolhe a próxima quando a fila está no fim: parecidas pelo AudioMuse
  /// (ou Last.fm/servidor), as melhores analisadas pelo AutoMix (fora dos
  /// dados móveis) e a de melhor encaixe entra na fila.
  Future<void> _djExtend() async {
    if (!state.dj || _djBusy || _remote != null) return;
    final cur = state.current;
    final p = _provider;
    if (cur == null || p == null || state.queue.length - state.index - 1 >= 1) return;
    _djBusy = true;
    try {
      _djHeard.add(cur.song.id);
      var cands = <(Song, double)>[];
      if (p.serverInfo?.sonicSimilarity ?? false) {
        cands = [for (final m in await p.sonicSimilar(cur.song.id, count: 30)) (m.song, m.similarity)];
      }
      if (cands.isEmpty) {
        final s = ref.read(settingsProvider);
        final list = await findSimilar(p, cur.song, count: 30, lastFm: s.lastFmForRadio ? ref.read(lastFmProvider) : null);
        cands = [for (final (i, x) in list.indexed) (x, 1 - 0.5 * i / max(1, list.length))];
      }
      final inQueue = state.queue.map((q) => q.song.id).toSet();
      cands = cands.where((c) => !inQueue.contains(c.$1.id) && !_djHeard.contains(c.$1.id)).toList();
      if (cands.isEmpty) {
        final random = await p.randomSongs(size: 10);
        cands = [for (final x in random) if (!inQueue.contains(x.id)) (x, 0.3)];
      }
      if (cands.isEmpty || !state.dj) return;
      final here = state.insights[cur.uid];
      final hereBpm = here?.reliable == true ? here?.bpm : cur.song.bpm?.toDouble();
      final conn = await Connectivity().checkConnectivity();
      final mobileData = conn.contains(ConnectivityResult.mobile) && !conn.contains(ConnectivityResult.wifi);
      final top = cands.take(5).toList();
      final analyzed = <String, TrackInsight>{};
      // Espera as análises só enquanto sobra tempo antes do fim da atual (o
      // AutoMix ainda precisa planejar a transição); as do cache voltam na hora.
      final left = (cur.song.duration ?? const Duration(minutes: 3)) - state.position;
      final wait = Duration(seconds: (left.inSeconds - 25).clamp(2, 40));
      await Future.wait(top.map((c) async {
        // Nos dados móveis, só o que já está analisado (sem baixar as candidatas).
        if (mobileData && !(await _freeToAnalyze(c.$1))) return;
        final ins = await _analyzeFor(c.$1, wait);
        if (ins != null) analyzed[c.$1.id] = ins;
      }));
      final recent = state.queue.skip(max(0, state.index - 3)).map((q) => q.song.artistId).toSet();
      (Song, double)? best;
      for (final (song, sim) in top) {
        final ins = analyzed[song.id];
        final bpm = ins?.reliable == true ? ins?.bpm : song.bpm?.toDouble();
        final score = djScore(
          similarity: sim,
          tempo: tempoFit(hereBpm, bpm),
          key: keyFit(here?.camelot, ins?.camelot),
          sameArtist: song.artistId != null && song.artistId == cur.song.artistId,
          recentArtist: recent.contains(song.artistId),
        );
        if (best == null || score > best.$2) best = (song, score);
      }
      if (best != null && state.dj && state.queue.length - state.index - 1 < 1) {
        enqueue([best.$1]);
      }
    } catch (e) {
      debugPrint('modo DJ: $e');
    } finally {
      _djBusy = false;
    }
  }

  // ---- Jam ----

  final _jamUids = <String>{};

  /// Músicas pedidas na Jam: entram depois da atual e das outras já pedidas
  /// (em ordem de chegada). Com nada tocando, começa por elas.
  List<String> jamInsert(List<Song> songs) {
    if (songs.isEmpty) return const [];
    if (_fwd('playNext', {'songs': _json(songs)})) return const [];
    final items = songs.map(_item).toList();
    var at = state.index + 1;
    while (at < state.queue.length && _jamUids.contains(state.queue[at].uid)) {
      at++;
    }
    final q = List.of(state.queue)..insertAll(at, items);
    _unshuffled?.addAll(items);
    _jamUids.addAll(items.map((e) => e.uid));
    state = state.copyWith(queue: q, index: state.index < 0 ? 0 : state.index);
    if (state.current == null || (!state.playing && !state.buffering && !_engineHasTrack)) {
      _startAt(at);
    } else {
      _scheduleNext();
    }
    return [for (final e in items) e.uid];
  }

  // ---- Tocar em outro aparelho (BKmasterplayer Connect) ----

  ConnectLink? _remote;
  StreamSubscription<Map<String, dynamic>>? _remoteSub;
  List<QueueItem> _remoteQueue = const [];

  bool get isRemote => _remote != null;

  static List<Map<String, dynamic>> _json(List<Song> songs) => [for (final s in songs) s.toJson()];

  /// No modo remoto, manda o comando para o outro aparelho (e devolve true).
  bool _fwd(String c, [Map<String, dynamic> args = const {}]) {
    final r = _remote;
    if (r == null) return false;
    r.cmd(c, args);
    return true;
  }

  /// Passa a tocar em [device]. Com [transfer], a fila daqui vai para lá e
  /// continua do mesmo ponto; sem, só controla o que ele já está tocando.
  Future<void> connectTo(ConnectDevice device, {required bool transfer}) async {
    final p = _provider;
    final me = ref.read(connectProvider.notifier).me;
    if (p == null || me == null) throw StateError('Connect indisponível');
    final link = await ConnectLink.open(device, auth: p.authParams, me: me);
    final local = state;
    await _dropRemote();
    if (transfer && local.current != null) {
      link.cmd('transfer', {
        'songs': _json(local.queue.map((q) => q.song).toList()),
        'index': local.index,
        'pos': local.position.inMilliseconds,
        'play': local.playing,
        'shuffle': local.shuffle,
        'repeat': local.repeat.name,
        'radio': local.radio,
      });
    }
    // O som passa a sair de lá: guarda a fila daqui e para o motor.
    if (local.current != null) await _persistNow();
    _mixTimer?.cancel();
    engine.playerStop();
    _engineHasTrack = false;
    _scheduledKey = null;
    _remote = link;
    _remoteQueue = const [];
    state = PlayerState(volume: local.volume, remoteDevice: device.name, remoteDeviceId: device.id);
    _remoteSub = link.messages.listen(_onRemote, onDone: () => _remoteLost(link));
  }

  /// Volta a tocar neste aparelho (como no Spotify): traz a fila e a posição
  /// de lá, pausa lá e continua aqui se estava tocando.
  Future<void> playHere() async {
    final r = _remote;
    if (r == null) return;
    final remote = state;
    r.cmd('pause');
    await _dropRemote();
    _adoptFromRemote(remote, play: remote.playing);
  }

  Future<void> _dropRemote() async {
    final r = _remote;
    _remote = null;
    await _remoteSub?.cancel();
    _remoteSub = null;
    await r?.close();
  }

  void _remoteLost(ConnectLink link) {
    if (_remote != link) return; // saída normal
    final remote = state;
    _remote = null;
    _remoteSub = null;
    _adoptFromRemote(remote, play: false);
    state = state.copyWith(message: 'Conexão com ${link.device.name} perdida');
  }

  void _adoptFromRemote(PlayerState remote, {required bool play}) {
    final vol = ref.read(settingsProvider).volume;
    engine.playerSetVolume(volume: _gain(vol));
    state = PlayerState(volume: vol, repeat: remote.repeat, shuffle: remote.shuffle, radio: remote.radio);
    final songs = remote.queue.map((q) => q.song).toList();
    if (songs.isEmpty) return;
    adoptQueue(
      songs,
      index: remote.index,
      position: remote.position,
      play: play,
      shuffle: remote.shuffle,
      repeat: remote.repeat,
      radio: remote.radio,
    );
  }

  void _onRemote(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'queue':
        final items = m['items'] as List? ?? const [];
        _remoteQueue = [
          for (final e in items)
            if (e is Map) QueueItem(e['u'] as String, Song.fromJson(Map<String, dynamic>.from(e['s'] as Map))),
        ];
        state = state.copyWith(queue: _remoteQueue);
      case 'state':
        final idx = (m['i'] as num?)?.toInt() ?? -1;
        final cur = idx >= 0 && idx < _remoteQueue.length ? _remoteQueue[idx].uid : null;
        final mix = m['mix'] as Map?;
        final ins = m['ins'] as Map?;
        state = PlayerState(
          queue: _remoteQueue,
          index: idx,
          playing: m['pl'] == true,
          buffering: m['bf'] == true,
          position: Duration(milliseconds: (m['pos'] as num?)?.toInt() ?? 0),
          duration: Duration(milliseconds: (m['dur'] as num?)?.toInt() ?? 0),
          volume: (m['vol'] as num?)?.toDouble() ?? state.volume,
          repeat: LoopMode.values.asNameMap()[m['rep']] ?? LoopMode.off,
          shuffle: m['sh'] == true,
          radio: m['rad'] == true,
          mix: mix == null
              ? null
              : MixInfo(
                  summary: mix['s'] as String? ?? '',
                  style: mix['st'] as String? ?? '',
                  until: DateTime.now().add(Duration(milliseconds: (mix['ms'] as num?)?.toInt() ?? 0)),
                ),
          plannedMix: m['pm'] as String?,
          plannedSynced: m['ps'] == true,
          insights: cur == null || ins == null
              ? const {}
              : {
                  cur: TrackInsight(
                    bpm: (ins['bpm'] as num?)?.toDouble(),
                    key: ins['key'] as String?,
                    camelot: ins['cam'] as String?,
                    reliable: ins['rel'] == true,
                  ),
                },
          remoteDevice: state.remoteDevice,
          remoteDeviceId: state.remoteDeviceId,
        );
    }
  }

  /// Troca a fila inteira e posiciona nela (fila vinda de outro aparelho).
  void adoptQueue(
    List<Song> songs, {
    required int index,
    Duration position = Duration.zero,
    bool play = true,
    bool shuffle = false,
    LoopMode repeat = LoopMode.off,
    bool radio = false,
  }) {
    if (songs.isEmpty) return;
    final items = songs.map(_item).toList();
    final i = index.clamp(0, items.length - 1);
    _unshuffled = null;
    state = state.copyWith(queue: items, shuffle: shuffle, repeat: repeat, radio: radio, clearMessage: true);
    if (play) {
      _startAt(i, start: position);
      return;
    }
    _mixTimer?.cancel();
    engine.playerStop();
    _engineHasTrack = false;
    _resumeAt = position;
    _scheduledKey = null;
    state = state.copyWith(
      index: i,
      position: position,
      duration: items[i].song.duration ?? Duration.zero,
      playing: false,
      clearMix: true,
      clearPlanned: true,
    );
    _persistSoon();
  }

  // ---- Scrobble: "tocando agora" no início, e registro após metade da faixa (ou 4 min) ----

  void _beginScrobble(QueueItem item) {
    _scrobbleUid = item.uid;
    _listened = Duration.zero;
    _lastPos = Duration.zero;
    _startedAt = DateTime.now();
    _submitted = false;
    _provider?.scrobble(item.song.id, submission: false).catchError((_) {});
  }

  void _trackListening(Duration pos) {
    final item = state.current;
    if (item == null || item.uid != _scrobbleUid || _submitted) return;
    final delta = pos - _lastPos;
    _lastPos = pos;
    if (state.playing && delta > Duration.zero && delta < const Duration(seconds: 2)) {
      _listened += delta;
    }
    final dur = item.song.duration ?? state.duration;
    final threshold = Duration(milliseconds: min(dur.inMilliseconds ~/ 2, 4 * 60 * 1000));
    if (dur > const Duration(seconds: 30) && _listened >= threshold) {
      _submitted = true;
      _provider?.scrobble(item.song.id, submission: true, time: _startedAt).catchError((_) {});
    }
  }
}

final playerProvider = NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
