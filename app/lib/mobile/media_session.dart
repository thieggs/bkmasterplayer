import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../player/player_controller.dart';
import '../ui/widgets/cover_art.dart';

/// Celular (Android): notificação de mídia, tela de bloqueio, botões do fone e
/// da caixa Bluetooth e foco de áudio (pausa numa ligação, abaixa o volume
/// para o GPS falar). O som sai pelo motor em Rust; aqui o estado do player é
/// espelhado para o sistema e os comandos do sistema voltam para o player.
Future<void> initMobileMedia(ProviderContainer container) async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  await AudioService.init(
    builder: () => _BkAudioHandler(container, session),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'io.github.playermusica.player_musica.playback',
      androidNotificationChannelName: Platform.localeName.startsWith('pt') ? 'Reprodução' : 'Playback',
      androidNotificationIcon: 'drawable/ic_stat_bk',
      // Na pausa sai do primeiro plano: solta o wake lock (bateria) e a
      // notificação pode ser dispensada. Voltar a tocar pelo botão do fone ou
      // da caixa funciona com o app em segundo plano porque o Android libera o
      // serviço por um tempo quando um controle de mídia manda um comando.
      androidStopForegroundOnPause: true,
    ),
  );
}

class _BkAudioHandler extends BaseAudioHandler {
  _BkAudioHandler(this._container, this._session) {
    _session.interruptionEventStream.listen(_onInterruption);
    // Fone desconectado / Bluetooth caiu: pausa em vez de sair no alto-falante.
    _session.becomingNoisyEventStream.listen((_) {
      if (!_remote) _player.pause();
    });
    _container.listen<PlayerState>(playerProvider, (_, s) => _update(s), fireImmediately: true);
  }

  final ProviderContainer _container;
  final AudioSession _session;

  PlayerController get _player => _container.read(playerProvider.notifier);

  /// Fechado pela notificação: some do sistema até voltar a tocar.
  bool _stopped = false;
  bool _wasPlaying = false;
  bool _resumeAfterInterruption = false;
  String? _itemUid;
  (bool, bool, Duration)? _published;
  Duration _publishedPos = Duration.zero;
  DateTime _publishedAt = DateTime.now();

  /// Controlando outro aparelho: o som sai de lá; aqui a notificação só controla.
  bool get _remote => _container.read(playerProvider).remoteDevice != null;

  void _update(PlayerState s) {
    if (s.playing && !_wasPlaying && s.remoteDevice == null) {
      _stopped = false;
      // Pede o foco de áudio (os outros players pausam); negado = ligação em curso.
      _session.setActive(true).then((ok) {
        if (!ok) _player.pause();
      });
    }
    _wasPlaying = s.playing;
    if (_stopped) return;

    final item = s.current;
    if (item == null) {
      if (mediaItem.value != null) mediaItem.add(null);
      if (playbackState.value.processingState != AudioProcessingState.idle) {
        playbackState.add(PlaybackState());
      }
      _itemUid = null;
      _published = null;
      return;
    }

    final song = item.song;
    final duration = s.duration > Duration.zero ? s.duration : (song.duration ?? Duration.zero);
    if (item.uid != _itemUid || mediaItem.value?.duration != duration) {
      final changed = item.uid != _itemUid;
      _itemUid = item.uid;
      mediaItem.add(
        MediaItem(
          id: item.uid,
          title: song.title,
          artist: song.displayArtist,
          album: song.album,
          duration: duration > Duration.zero ? duration : null,
          artUri: changed ? null : mediaItem.value?.artUri,
        ),
      );
      if (changed) _loadArt(item);
    }

    // O sistema extrapola a posição sozinho enquanto toca: só republica quando
    // o estado muda ou a posição foge da conta (seek, faixa nova).
    final now = DateTime.now();
    final predicted = _publishedPos + (playbackState.value.playing ? now.difference(_publishedAt) : Duration.zero);
    final jumped = (s.position - predicted).abs() > const Duration(milliseconds: 1500);
    final sig = (s.playing, s.buffering, duration);
    if (sig == _published && !jumped) return;
    _published = sig;
    _publishedPos = s.position;
    _publishedAt = now;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          s.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: s.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
        playing: s.playing,
        updatePosition: s.position,
        bufferedPosition: duration * s.buffered.clamp(0.0, 1.0),
        queueIndex: s.index,
      ),
    );
  }

  /// Capa da notificação a partir do cache local: a URL do servidor leva o
  /// token do login, e os metadados da sessão de mídia são visíveis a outros apps.
  Future<void> _loadArt(QueueItem item) async {
    try {
      final p = _container.read(musicProvider);
      final uri = p.coverUri(item.song.coverArt, size: 600);
      final key = p.coverCacheKey(item.song.coverArt, size: 600);
      if (uri == null || key == null) return;
      final dir = '${_container.read(cacheDirProvider).path}/ui_covers';
      final file = await CoverImageProvider.fetchFile(url: uri.toString(), cacheKey: key, cacheDir: dir);
      final cur = mediaItem.value;
      if (cur != null && cur.id == item.uid) mediaItem.add(cur.copyWith(artUri: Uri.file(file.path)));
    } catch (e) {
      debugPrint('capa da notificação: $e');
    }
  }

  void _onInterruption(AudioInterruptionEvent e) {
    if (_remote) return;
    if (e.begin) {
      switch (e.type) {
        case AudioInterruptionType.duck:
          _player.duck(true);
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          // pause = passageiro (ligação): volta sozinho depois; unknown = outro
          // app de música assumiu: fica pausado.
          if (_container.read(playerProvider).playing) {
            _resumeAfterInterruption = e.type == AudioInterruptionType.pause;
            _player.pause();
          }
      }
    } else {
      switch (e.type) {
        case AudioInterruptionType.duck:
          _player.duck(false);
        case AudioInterruptionType.pause:
          if (_resumeAfterInterruption) _player.play();
          _resumeAfterInterruption = false;
        case AudioInterruptionType.unknown:
          _resumeAfterInterruption = false;
      }
    }
  }

  @override
  Future<void> play() async => _player.play();

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> skipToNext() async => _player.next();

  @override
  Future<void> skipToPrevious() async => _player.previous();

  @override
  Future<void> skipToQueueItem(int index) async => _player.jumpTo(index);

  @override
  Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> fastForward() async => _player.seekBy(const Duration(seconds: 10));

  @override
  Future<void> rewind() async => _player.seekBy(const Duration(seconds: -10));

  /// "Fechar" na notificação: pausa e tira o player do sistema.
  @override
  Future<void> stop() async {
    _player.pause();
    _stopped = true;
    _itemUid = null;
    _published = null;
    await _session.setActive(false);
    playbackState.add(playbackState.value.copyWith(processingState: AudioProcessingState.idle, playing: false));
    await super.stop();
  }

  /// App arrastado para fora dos recentes: se estava pausado, encerra.
  @override
  Future<void> onTaskRemoved() async {
    if (!_container.read(playerProvider).playing) await stop();
  }

  @override
  Future<void> onNotificationDeleted() => stop();
}
