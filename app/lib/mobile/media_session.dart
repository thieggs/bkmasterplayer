import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../core/providers.dart';
import '../data/similar.dart';
import '../domain/models.dart';
import '../player/player_controller.dart';
import '../ui/widgets/cover_art.dart';
import 'auto_browser.dart';

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
      // Android Auto: lista/grade por pasta e busca na tela do carro.
      androidBrowsableRootExtras: AutoBrowser.rootExtras,
    ),
  );
}

class _BkAudioHandler extends BaseAudioHandler {
  _BkAudioHandler(this._container, this._session)
      : _auto = AutoBrowser(
          provider: () {
            try {
              return _container.read(musicProvider);
            } catch (_) {
              return null; // sem login
            }
          },
          artDir: '${_container.read(cacheDirProvider).path}/aa_art',
          pt: Platform.localeName.startsWith('pt'),
        ) {
    _session.interruptionEventStream.listen(_onInterruption);
    // Fone desconectado / Bluetooth caiu: pausa em vez de sair no alto-falante.
    _session.becomingNoisyEventStream.listen((_) {
      if (!_remote) _player.pause();
    });
    _container.listen<PlayerState>(playerProvider, (_, s) => _update(s), fireImmediately: true);
    // O carro abriu o app antes do login voltar (ou trocou a conta): recarrega as pastas.
    _container.listen(sessionProvider, (prev, next) {
      if (prev?.value?.provider.accountId != next.value?.provider.accountId) {
        for (final s in _children.values) {
          s.add(const {});
        }
      }
    });
  }

  final _children = <String, BehaviorSubject<Map<String, dynamic>>>{};

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) =>
      _children.putIfAbsent(parentMediaId, BehaviorSubject.new);

  final ProviderContainer _container;
  final AudioSession _session;
  final AutoBrowser _auto;

  PlayerController get _player => _container.read(playerProvider.notifier);

  /// Fila mostrada no carro: uma janela em volta da atual (fila de milhares
  /// de músicas estoura o limite do Binder).
  List<QueueItem>? _queueOf;
  int _queueStart = 0;

  /// Fechado pela notificação: some do sistema até voltar a tocar.
  bool _stopped = false;
  bool _wasPlaying = false;
  bool _resumeAfterInterruption = false;
  String? _itemUid;
  (bool, bool, Duration, int)? _published;
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

    _publishQueue(s);
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
    final sig = (s.playing, s.buffering, duration, s.index - _queueStart);
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
        queueIndex: s.index - _queueStart,
      ),
    );
  }

  void _publishQueue(PlayerState s) {
    const before = 20, size = 100;
    final inWindow = s.index - _queueStart >= 0 && s.index - _queueStart < size - 30;
    if (identical(s.queue, _queueOf) && inWindow) return;
    _queueOf = s.queue;
    _queueStart = (s.index - before).clamp(0, (s.queue.length - 1).clamp(0, 1 << 30));
    final end = (_queueStart + size).clamp(0, s.queue.length);
    queue.add([
      for (final q in s.queue.sublist(_queueStart, end))
        MediaItem(id: q.uid, title: q.song.title, artist: q.song.displayArtist, album: q.song.album, duration: q.song.duration),
    ]);
  }

  /// Capa da notificação a partir do cache local: a URL do servidor leva o
  /// token do login, e os metadados da sessão de mídia são visíveis a outros apps.
  Future<void> _loadArt(QueueItem item) async {
    try {
      if (isFileCover(item.song.coverArt)) {
        final cur = mediaItem.value;
        if (cur != null && cur.id == item.uid) mediaItem.add(cur.copyWith(artUri: Uri.file(item.song.coverArt!)));
        return;
      }
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
  Future<void> skipToQueueItem(int index) async => _player.jumpTo(_queueStart + index);

  // ---- Android Auto: navegação, busca e voz ----

  Song? get _current => _container.read(playerProvider).current?.song;

  /// O carro pode abrir o app do zero: espera o login (e a fila salva) voltar.
  Future<void> _ready() async {
    try {
      if (_auto.provider() == null) await _container.read(sessionProvider.future).timeout(const Duration(seconds: 8));
      // A fila salva é restaurada logo depois do login.
      if (_auto.provider() != null) await _player.restored.timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    try {
      await _ready();
      if (parentMediaId == AudioService.recentRootId) {
        // "Continuar ouvindo" do sistema: a música da fila salva.
        final song = _current;
        if (song == null) return const [];
        return [
          MediaItem(id: 'do:resume', title: song.title, artist: song.displayArtist, album: song.album, artUri: _auto.art(song.coverArt), playable: true),
        ];
      }
      if (parentMediaId != AudioService.browsableRootId && _auto.provider() == null) {
        final pt = Platform.localeName.startsWith('pt');
        return [MediaItem(id: 'info:login', title: pt ? 'Entre na sua conta no BKmasterplayer do celular' : 'Sign in on the BKmasterplayer phone app', playable: false)];
      }
      return await _auto.children(parentMediaId, current: _current);
    } catch (e) {
      debugPrint('Android Auto ($parentMediaId): $e');
      return const [];
    }
  }

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async {
    try {
      await _ready();
      return await _auto.search(query);
    } catch (e) {
      debugPrint('Android Auto (busca): $e');
      return const [];
    }
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    await _ready();
    final song = _current;
    switch (mediaId) {
      case 'do:resume':
        _player.play();
      case 'do:dj':
        if (song != null) _player.startDj(song);
      case 'do:mix':
        final p = _auto.provider();
        if (song == null || p == null) return;
        final s = _container.read(settingsProvider);
        final similar = await findSimilar(p, song, count: 60, lastFm: s.lastFmForRadio ? _container.read(lastFmProvider) : null);
        _player.playSongs([song, ...similar.where((x) => x.id != song.id)]);
        _player.setRadio(true);
      case 'do:shuffle':
        final p = _auto.provider();
        if (p != null) _player.playSongs(await p.randomSongs(size: 100));
      default:
        final r = await _auto.resolve(mediaId);
        if (r != null) _player.playSongs(r.$1, start: r.$2);
    }
  }

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    await _ready();
    try {
      final songs = await _auto.voice(query, extras);
      if (songs.isNotEmpty) _player.playSongs(songs);
    } catch (e) {
      debugPrint('Android Auto (voz): $e');
    }
  }

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
