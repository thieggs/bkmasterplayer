import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/providers.dart';
import '../data/settings.dart';
import '../domain/models.dart';
import '../domain/music_provider.dart';
import '../src/rust/api/engine.dart' as engine;

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
  }) =>
      PlayerState(
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
      );
}

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
          prev?.replayGainPreampDb != next.replayGainPreampDb) {
        _scheduledKey = null;
        _scheduleNext();
      }
    });
    return PlayerState(volume: volume);
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
    state = state.copyWith(queue: items, shuffle: shuffle, clearMessage: true);
    _startAt(startIndex);
  }

  void enqueue(List<Song> songs) {
    if (songs.isEmpty) return;
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
    if (i < 0 || i >= state.queue.length) return;
    _startAt(i);
  }

  void removeAt(int i) {
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
    final q = List.of(state.queue);
    final item = q.removeAt(from);
    q.insert(to, item);
    final currentUid = state.current?.uid;
    state = state.copyWith(queue: q, index: q.indexWhere((e) => e.uid == currentUid));
    _scheduleNext();
  }

  void clearUpcoming() {
    if (state.current == null) return;
    state = state.copyWith(queue: state.queue.sublist(0, state.index + 1));
    _scheduleNext();
  }

  void toggleShuffle() {
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
    final next = LoopMode.values[(state.repeat.index + 1) % LoopMode.values.length];
    state = state.copyWith(repeat: next);
    _scheduleNext();
  }

  // ---- Transporte ----

  void toggle() {
    if (state.current == null) return;
    if (!state.playing && state.position == Duration.zero && !state.buffering && !_engineHasTrack) {
      _startAt(state.index);
      return;
    }
    engine.playerToggle();
  }

  void play() => state.playing ? null : toggle();
  void pause() => engine.playerPause();

  void stop() {
    engine.playerStop();
    state = state.copyWith(playing: false, position: Duration.zero);
  }

  void next() {
    final n = _nextIndex(manual: true);
    if (n != null) _startAt(n);
  }

  void previous() {
    if (state.position > const Duration(seconds: 3) || state.index <= 0) {
      seek(Duration.zero);
      return;
    }
    _startAt(state.index - 1);
  }

  void seek(Duration to) {
    engine.playerSeek(positionMs: to.inMilliseconds);
    state = state.copyWith(position: to);
    _lastPos = to;
  }

  void seekBy(Duration delta) => seek(state.position + delta < Duration.zero ? Duration.zero : state.position + delta);

  void setVolume(double v) {
    final vol = v.clamp(0.0, 1.0);
    engine.playerSetVolume(volume: _gain(vol));
    state = state.copyWith(volume: vol);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(volume: vol));
  }

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
    state = state.copyWith(index: i, position: start, duration: item.song.duration ?? Duration.zero, buffered: 0);
    _scheduledKey = null;
    engine.playerPlay(track: src, startMs: start.inMilliseconds);
    _scheduleNext();
  }

  void _scheduleNext() {
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
    // Faixas seguidas do mesmo álbum sempre sem pausa e sem crossfade (álbuns ao vivo, conceituais).
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

  engine.TrackSource? _source(QueueItem item) {
    final p = _provider;
    if (p == null) return null;
    final s = ref.read(settingsProvider);
    final song = item.song;
    final (gain, peak) = _replayGain(item);
    final format = s.transcodeFormat;
    final bitrate = s.maxBitRate > 0 ? s.maxBitRate : null;
    return engine.TrackSource(
      id: item.uid,
      url: p.streamUri(song, format: format, maxBitRate: bitrate).toString(),
      cacheKey: p.streamCacheKey(song, format: format, maxBitRate: bitrate),
      formatHint: format ?? song.suffix,
      durationMs: song.duration?.inMilliseconds,
      gainDb: gain,
      peak: peak,
      title: song.title,
      artist: song.displayArtist,
      album: song.album ?? '',
      coverUrl: p.coverUri(song.coverArt, size: 600)?.toString(),
      coverKey: p.coverCacheKey(song.coverArt, size: 600),
    );
  }

  void _onEvent(engine.PlayerEvent e) {
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
