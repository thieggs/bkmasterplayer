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
import '../data/current_version.dart';
import '../data/recommend.dart';
import '../data/settings.dart';
import '../data/similar.dart';
import '../data/smart_source.dart';
import 'dj_mode.dart';
import 'listen_signal.dart';
import 'radio.dart';
import 'smart_session.dart';
import '../domain/models.dart';
import '../data/network.dart';
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

/// Aviso do aleatório smart para a tela: entendeu o pulo de [song] como
/// "não gostei" (a tela oferece desfazer).
@immutable
class SmartNote {
  const SmartNote(this.song, this.seq);
  final Song song;

  /// Muda a cada aviso: dois pulos da mesma música são dois avisos.
  final int seq;
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
    this.smart = false,
    this.smartNote,
    this.remoteDevice,
    this.remoteDeviceId,
    this.jamHost,
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

  /// Aleatório smart: rodadas de amostras que aprendem com o que a pessoa
  /// ouve inteiro e com o que ela pula (ver `smart_session.dart`).
  final bool smart;

  /// Último pulo que o aleatório smart entendeu como "não gostei".
  final SmartNote? smartNote;

  /// Controlando outro aparelho (BKmasterplayer Connect): nome e id dele. O estado
  /// acima é o de lá.
  final String? remoteDevice;
  final String? remoteDeviceId;

  /// Convidado numa Festa: nome do dono. O estado acima é o de lá, e os
  /// comandos vão para ele (ver [JamRemote]).
  final String? jamHost;

  /// O som sai de outro aparelho (Connect ou Festa): aqui o motor está parado.
  bool get elsewhere => remoteDevice != null || jamHost != null;

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
    bool? smart,
    SmartNote? smartNote,
    bool clearSmartNote = false,
  }) =>
      PlayerState(
        dj: dj ?? this.dj,
        smart: smart ?? this.smart,
        smartNote: clearSmartNote ? null : (smartNote ?? this.smartNote),
        remoteDevice: remoteDevice,
        remoteDeviceId: remoteDeviceId,
        jamHost: jamHost,
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

/// Formatos que nenhum decodificador do motor lê, em nenhum aparelho: o
/// servidor já entrega convertidos (MP3). Os outros vão como estão, e se o
/// motor não abrir o arquivo (ex.: HE-AAC num .m4a), ele mesmo passa para a
/// conversão (`fallbackUrl`). Tem de bater com `UNDECODABLE` do BK Analyzer
/// (rust/src/bin/bk_analyzer/store.rs), que analisa o mesmo arquivo tocado.
const _undecodable = {'wma', 'asf', 'mpc', 'mp+', 'mpp', 'tta', 'ac3', 'eac3', 'dts', 'amr', 'awb', 'spx', 'tak', 'ofr', 'ofs', 'shn', 'ra', 'rm'};

/// Festa em que este aparelho entrou como convidado: o som sai do dono, e é
/// para lá que vão os comandos do player (ver `jam/jam_core.dart`).
abstract class JamRemote {
  /// Comando do player, com os mesmos nomes e argumentos do Connect
  /// (toggle, next, seek, playSongs…).
  void command(String c, Map<String, dynamic> args);

  /// Sai da Festa.
  Future<void> leave();
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

  // O que o aleatório smart lê de cada música (ver [_leave]).
  /// Entrada da fila já julgada.
  String? _judgedUid;

  /// A entrada tocando começou do meio (fila restaurada, vinda de outro
  /// aparelho): o começo não foi ouvido aqui.
  bool _fromMiddle = false;
  final _startMid = <String>{};
  DateTime? _pausedSince;
  bool _pausedLong = false;

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
          prev?.analysisServer != next.analysisServer ||
          prev?.maxBitRate != next.maxBitRate ||
          prev?.mobileMaxBitRate != next.mobileMaxBitRate) {
        if (prev?.automixEnabled != next.automixEnabled) state = state.copyWith(clearPlanned: true);
        _scheduledKey = null;
        _scheduleNext();
      }
    });
    // Entrou ou saiu dos dados móveis: a próxima faixa vem na qualidade da rede nova.
    ref.listen(meteredProvider, (_, _) {
      _scheduledKey = null;
      _scheduleNext();
    });
    // Trocou entre o endereço de casa e o principal: a próxima faixa vai pelo novo.
    ref.listen(endpointProvider, (_, _) {
      _scheduledKey = null;
      _scheduleNext();
    });
    ref.listen(sessionProvider, (_, next) {
      final account = next.value?.provider.accountId;
      if (account != null && _accountId != null && account != _accountId && _jam != null) {
        // Trocou de conta no meio da Festa: a fila guardada para a volta era
        // da outra conta; ao sair, carrega a desta.
        _beforeJam = null;
        _restored = false;
      } else if (account != null && _accountId != null && account != _accountId) {
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
              // A fila de downloads offline não sobrevive ao app fechado: pede de novo o que falta.
              if (account != null) unawaited(ref.read(offlineProvider.notifier).resumePending(account));
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

  /// Posição tocando, gravada à parte a cada 15 s: regravar a fila inteira
  /// (até 1000 músicas em JSON, na thread da tela) só para mudar a posição
  /// dava um engasgo de tempos em tempos.
  File get _positionFile => File('${ref.read(supportDirProvider).path}/queue_pos.json');

  /// O que está em `queue.json` agora: a fila (mesma instância), onde começa a
  /// fatia gravada, quantas músicas e a marca que casa com `queue_pos.json`.
  List<QueueItem>? _savedQueue;
  int _savedStart = 0;
  int _savedLength = 0;
  int _savedStamp = 0;

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
    // A fila de outro aparelho não é a daqui: não vai para o disco.
    if (p == null || _mirroring) return;
    // Guarda até 1000 faixas em volta da atual.
    final queue = state.queue;
    final start = max(0, state.index - 200);
    final items = queue.skip(start).take(1000).toList();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final data = {
      'account': p.accountId,
      'stamp': stamp,
      'index': state.index - start,
      'position': state.position.inMilliseconds,
      'radio': state.radio,
      'dj': state.dj,
      // O que o aleatório smart aprendeu: fechar o app não zera.
      if (state.smart && _smart != null) 'smart': _smart!.toJson(),
      'queue': items.map((q) => q.song.toJson()).toList(),
    };
    try {
      final tmp = File('${_queueFile.path}.tmp');
      await tmp.writeAsString(jsonEncode(data));
      await tmp.rename(_queueFile.path);
      _savedQueue = queue;
      _savedStart = start;
      _savedLength = items.length;
      _savedStamp = stamp;
    } catch (e) {
      debugPrint('salvando fila: $e');
    }
  }

  /// Grava só a posição (e qual música da fila gravada está tocando). Se a
  /// fila mudou desde a última gravação, grava tudo.
  Future<void> _savePosition() => _saveChain = _saveChain.then((_) {
        final p = _provider;
        if (p == null || _mirroring) return null;
        final rel = state.index - _savedStart;
        if (!identical(state.queue, _savedQueue) || rel < 0 || rel >= _savedLength) return _writeQueue();
        return _writePosition(p.accountId, rel);
      });

  Future<void> _writePosition(String account, int index) async {
    try {
      final tmp = File('${_positionFile.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'account': account,
        'stamp': _savedStamp,
        'index': index,
        'position': state.position.inMilliseconds,
      }));
      await tmp.rename(_positionFile.path);
    } catch (e) {
      debugPrint('salvando posição: $e');
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
    if (p == null || cur == null || _mirroring || !ref.read(settingsProvider).syncQueue) return;
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
    SmartSession? smart;
    try {
      if (await _queueFile.exists()) {
        final j = jsonDecode(await _queueFile.readAsString()) as Map<String, dynamic>;
        if (j['account'] == p.accountId) {
          songs = (j['queue'] as List).map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map))).toList();
          index = (j['index'] as int?) ?? 0;
          position = Duration(milliseconds: (j['position'] as int?) ?? 0);
          radio = j['radio'] == true;
          dj = j['dj'] == true;
          final sj = j['smart'];
          if (sj is Map) smart = SmartSession.fromJson(Map<String, dynamic>.from(sj));
          // A posição gravada depois, à parte, se for desta mesma fila.
          try {
            final pos = jsonDecode(await _positionFile.readAsString()) as Map<String, dynamic>;
            if (j['stamp'] != null && pos['stamp'] == j['stamp'] && pos['account'] == p.accountId) {
              index = (pos['index'] as int?) ?? index;
              position = Duration(milliseconds: (pos['position'] as int?) ?? position.inMilliseconds);
            }
          } catch (_) {}
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
    if (smart != null) {
      _smart = smart;
      // As que vêm depois da atual foram escolhidas por ele: podem ser trocadas.
      _smartUids.addAll(items.skip(index + 1).map((e) => e.uid));
    }
    state = state.copyWith(
      queue: items,
      index: index,
      position: position,
      duration: items[index].song.duration ?? Duration.zero,
      radio: radio,
      dj: dj,
      smart: smart != null,
    );
  }

  // ---- Rádio infinita ----

  bool _extending = false;

  /// A rádio em andamento: a semente e a vizinhança dela (ver `radio.dart`).
  /// Nula = a próxima extensão começa uma, a partir da música atual.
  RadioSession? _radioSession;

  /// Método escolhido para esta rádio na hora de começar (folha da rádio);
  /// nulo = o dos ajustes.
  RecommendStyle? _radioStyle;

  void toggleRadio() => setRadio(!state.radio, persist: true);

  void setRadio(bool on, {bool persist = false}) {
    if (_fwd('radio', {'on': on})) return;
    // Ligar de novo começa outra rádio, a partir do que toca agora.
    if (on != state.radio) {
      _radioSession = null;
      _radioStyle = null;
    }
    if (on) _dropSmart();
    state = state.copyWith(radio: on, smart: on ? false : state.smart);
    if (persist) _persistSoon();
    _maybeExtendRadio();
  }

  /// Começa uma rádio a partir de [seed]: ela e as primeiras parecidas, já
  /// com as regras da rádio (sem repetir artista, sem mix de uma hora). Falso
  /// se não achou nada.
  Future<bool> startRadio(Song seed, {RecommendStyle? style}) async {
    final p = _provider;
    // Na Festa a fila é do dono: uma rádio daqui mandaria vinte músicas para lá.
    if (p == null || _jam != null) return false;
    final session = RadioSession(seed, artists: _radioArtists);
    final first = await session.next(
      want: 20,
      history: [seed],
      fetch: _radioFetch(p, style),
      fallback: () => _radioFallback(p, seed, style),
    );
    if (first.isEmpty) return false;
    playSongs([seed, ...first]);
    setRadio(true);
    _radioSession = session;
    _radioStyle = style;
    return true;
  }

  RadioArtists get _radioArtists => RadioArtists.parse(ref.read(settingsProvider).radioArtists);

  /// Parecidas para a rádio: só a fonte boa (vetores ou análise sônica), para
  /// a sessão perceber quando a música é desconhecida e pedir a outra.
  SimilarFetch _radioFetch(MusicProvider p, RecommendStyle? style) {
    final s = ref.read(settingsProvider);
    final lastFm = s.lastFmForRadio ? ref.read(lastFmProvider) : null;
    final local = ref.read(recommendProvider.notifier);
    return (seed, count) => findSimilarScored(p, seed, count: count, lastFm: lastFm, local: local, style: style, strict: true);
  }

  /// Último recurso da rádio: as parecidas de qualquer fonte (Last.fm, o
  /// "similar" do servidor) e, sem nada, aleatórias.
  Future<List<Song>> _radioFallback(MusicProvider p, Song seed, RecommendStyle? style) async {
    final s = ref.read(settingsProvider);
    final r = await findSimilar(p, seed,
        count: 40,
        lastFm: s.lastFmForRadio ? ref.read(lastFmProvider) : null,
        local: ref.read(recommendProvider.notifier),
        style: style);
    return r.isNotEmpty ? r : p.randomSongs(size: 20);
  }

  /// Com a rádio ligada e a fila acabando, completa com mais dez, **do jeito
  /// escolhido nos ajustes** (quem decide a fonte é o método, ver
  /// `data/similar.dart`), seguindo a sessão da rádio (ver `radio.dart`).
  Future<void> _maybeExtendRadio() async {
    if (!state.radio || _extending || state.queue.isEmpty) return;
    if (state.queue.length - state.index - 1 > 2) return;
    final p = _provider;
    if (p == null) return;
    _extending = true;
    try {
      final session = _radioSession ??= RadioSession(state.current?.song ?? state.queue.last.song, artists: _radioArtists);
      session.artists = _radioArtists;
      final style = _radioStyle;
      final songs = await session.next(
        want: 10,
        history: [for (final q in state.queue) q.song],
        fetch: _radioFetch(p, style),
        fallback: () => _radioFallback(p, state.current?.song ?? session.seed, style),
      );
      // A rádio pode ter sido desligada (ou trocada) enquanto buscava.
      if (songs.isNotEmpty && state.radio && identical(_radioSession, session)) enqueue(songs);
    } catch (e) {
      debugPrint('rádio: $e');
    } finally {
      _extending = false;
    }
  }

  // ---- Aleatório smart ----

  /// A sessão em andamento: o que a pessoa aprovou, o que pulou e a
  /// exploração (ver `smart_session.dart`).
  SmartSession? _smart;

  /// Entradas da fila escolhidas pelo modo: as que ainda não tocaram podem ser
  /// trocadas depois de um "não gostei".
  final _smartUids = <String>{};

  /// Entradas que a pessoa pôs na fila à mão com o modo ligado: quando
  /// começam, contam como escolha dela ([SmartWeights.picked]).
  final _pickedUids = <String>{};

  bool _smartBusy = false;
  bool _startingSmart = false;
  int _smartSeq = 0;

  bool get _smartOn => state.smart && _smart != null && !_mirroring;

  int get _smartSamples => ref.read(settingsProvider).smartSamples.clamp(2, 10);

  void _configureSmart(SmartSession session) {
    final s = ref.read(settingsProvider);
    session
      ..start = SmartStart.parse(s.smartStart)
      ..explore = SmartExplore.parse(s.smartExplore)
      ..memory = SmartMemory.parse(s.smartMemory)
      ..artists = _radioArtists;
  }

  /// Com a análise guardada no aparelho, os vetores; sem ela, o servidor.
  SmartSource _smartSource(MusicProvider p) {
    final local = ref.read(recommendProvider.notifier);
    if (local.ready) return local;
    final s = ref.read(settingsProvider);
    return ServerSmartSource(p, lastFm: s.lastFmForRadio ? ref.read(lastFmProvider) : null);
  }

  void _dropSmart() {
    _smart = null;
    _smartUids.clear();
    _pickedUids.clear();
  }

  /// Começa o aleatório smart. [seed] é a música escolhida para começar (o
  /// primeiro ímã); sem ela, a primeira rodada é sorteio. Falso se não achou
  /// nada para tocar.
  Future<bool> startSmart({Song? seed}) async {
    if (_fwd('smartStart', {if (seed != null) 'seed': seed.toJson()})) return true;
    final p = _provider;
    // Na Festa a fila é do dono.
    if (p == null || _jam != null) return false;
    final session = SmartSession(seed: seed);
    _configureSmart(session);
    final first = await session.next(want: _smartSamples, history: [?seed], source: _smartSource(p));
    if (first.isEmpty) return false;
    _startingSmart = true;
    playSongs([?seed, ...first]);
    _startingSmart = false;
    _smart = session;
    _smartUids.addAll(state.queue.skip(seed == null ? 0 : 1).map((q) => q.uid));
    state = state.copyWith(smart: true, radio: false, dj: false);
    _persistSoon();
    return true;
  }

  void toggleSmart() => setSmart(!state.smart);

  /// Liga (o que está tocando vira o primeiro ímã) ou desliga.
  void setSmart(bool on) {
    if (_fwd('smart', {'on': on})) return;
    if (_jam != null || on == state.smart) return;
    if (on && state.current == null) {
      unawaited(startSmart());
      return;
    }
    _dropSmart();
    if (on) {
      _smart = SmartSession(seed: state.current?.song);
      _radioSession = null;
      _radioStyle = null;
    }
    state = state.copyWith(smart: on, radio: on ? false : state.radio, dj: on ? false : state.dj);
    _persistSoon();
    unawaited(_maybeExtendSmart());
  }

  /// Rodada acabando: puxa a próxima, já com o que a pessoa fez com as
  /// anteriores.
  Future<void> _maybeExtendSmart() async {
    final session = _smart;
    if (!_smartOn || session == null || _smartBusy || state.queue.isEmpty) return;
    final want = _smartSamples;
    if (state.queue.length - state.index - 1 >= max(1, want ~/ 2)) return;
    final p = _provider;
    if (p == null) return;
    _smartBusy = true;
    try {
      _configureSmart(session);
      final songs = await session.next(
        want: want,
        history: [for (final q in state.queue) q.song],
        source: _smartSource(p),
      );
      // Pode ter sido desligado (ou recomeçado) enquanto buscava.
      if (songs.isEmpty || !state.smart || !identical(_smart, session)) return;
      final items = songs.map(_item).toList();
      _smartUids.addAll(items.map((e) => e.uid));
      _append(items);
    } catch (e) {
      debugPrint('aleatório smart: $e');
    } finally {
      _smartBusy = false;
    }
  }

  /// A música que estava tocando saiu de cena: o aleatório smart lê o que a
  /// pessoa fez com ela (ver `listen_signal.dart`). Cada entrada é julgada uma
  /// vez: a que sai na mão, pelo comando (pulo, troca de fila); a que sai
  /// sozinha, quando a próxima começa.
  void _leave(TrackExit exit) {
    final uid = _scrobbleUid;
    if (uid == null || uid == _judgedUid) return;
    _judgedUid = uid;
    final session = _smart;
    if (!_smartOn || session == null) return;
    final item = state.queue.where((q) => q.uid == uid).firstOrNull;
    if (item == null) return;
    final pausa = _pausedSince;
    final signal = listenSignal(
      exit: exit,
      heard: _listened,
      position: state.current?.uid == uid ? state.position : _lastPos,
      duration: item.song.duration ?? state.duration,
      fromMiddle: _fromMiddle,
      pausedLong: _pausedLong || (pausa != null && DateTime.now().difference(pausa) > Listen.longPause),
    );
    session.left(item.song, signal);
    _persistSoon();
    if (signal < 0) {
      state = state.copyWith(smartNote: SmartNote(item.song, ++_smartSeq));
      unawaited(_smartReplan());
    }
  }

  void _notePause(bool playing) {
    final desde = _pausedSince;
    if (!playing && state.playing) {
      _pausedSince = DateTime.now();
    } else if (playing && desde != null) {
      if (DateTime.now().difference(desde) > Listen.longPause) _pausedLong = true;
      _pausedSince = null;
    }
  }

  /// Depois de um "não gostei": as escolhidas pelo modo que ainda não tocaram
  /// e caíram no que é para evitar saem da fila, e a rodada se completa com
  /// outras.
  Future<void> _smartReplan() async {
    final session = _smart;
    final p = _provider;
    if (!_smartOn || session == null || p == null) return;
    final upcoming = [for (final q in state.queue.skip(state.index + 1)) if (_smartUids.contains(q.uid)) q];
    if (upcoming.isNotEmpty) {
      Set<String> bad;
      try {
        bad = await _smartSource(p)
            .smartAvoided([for (final q in upcoming) q.song], session.avoided(), [for (final (s, _) in session.anchors()) s]);
      } catch (e) {
        debugPrint('aleatório smart: $e');
        bad = const {};
      }
      if (!identical(_smart, session)) return;
      final drop = {for (final q in upcoming) if (bad.contains(q.song.id)) q.uid};
      if (drop.isNotEmpty) {
        final cur = state.current?.uid;
        final q = [for (final e in state.queue) if (e.uid == cur || !drop.contains(e.uid)) e];
        _unshuffled?.removeWhere((e) => drop.contains(e.uid));
        _smartUids.removeAll(drop);
        state = state.copyWith(queue: q, index: q.indexWhere((e) => e.uid == cur));
        _scheduleNext();
      }
    }
    await _maybeExtendSmart();
  }

  /// A pessoa favoritou (ou desfez) [song]: para o aleatório smart é o sinal
  /// mais forte de "gostei".
  void noteStar(Song song, bool starred) {
    if (!_smartOn) return;
    _smart!.starred(song, starred);
    _persistSoon();
  }

  void consumeSmartNote() => state = state.copyWith(clearSmartNote: true);

  /// "Desfazer" do aviso: aquele pulo não foi "não gostei".
  void smartUndo(String songId) {
    _smart?.undo(songId);
    _persistSoon();
  }

  /// O ✕ do painel: esquece o que [songId] ensinou.
  void smartForget(String songId) {
    _smart?.forget(songId);
    _persistSoon();
  }

  /// Esquece tudo e continua aprendendo do zero.
  void smartForgetAll() {
    if (_smart == null) return;
    _smart = SmartSession();
    _persistSoon();
  }

  /// O que o aleatório smart aprendeu até agora, para o painel (nulo = modo
  /// desligado, ou ligado noutro aparelho).
  ({List<(Song, double)> liked, List<Song> avoiding, int exploreEvery, bool searching})? get smartLearned {
    final s = _smart;
    if (s == null || !_smartOn) return null;
    _configureSmart(s);
    return (liked: s.anchors(), avoiding: s.avoided(), exploreEvery: s.exploreEvery, searching: s.searching);
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
    _leave(TrackExit.interrupted);
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
    // Lista nova escolhida: o Modo DJ e o aleatório smart só continuam se
    // foram eles que começaram, e a rádio (se ficar ligada) recomeça a partir
    // dela.
    _radioSession = null;
    _radioStyle = null;
    _smartUids.clear();
    _pickedUids.clear();
    if (!_startingSmart) _smart = null;
    state = state.copyWith(queue: items, shuffle: shuffle, clearMessage: true, dj: _startingDj, smart: _startingSmart);
    _startAt(startIndex);
  }

  /// Toque numa música de uma lista, conforme a preferência do usuário.
  void playFrom(List<Song> songs, int index) {
    // Na Festa, tocar numa música da lista manda só ela (não a lista inteira).
    if (_jam != null) {
      ref.read(uiPrefsProvider).songTap == 'enqueue' ? enqueue([songs[index]]) : playNext([songs[index]]);
      return;
    }
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
    if (_smartOn) _pickedUids.addAll(items.map((e) => e.uid));
    _append(items);
  }

  void _append(List<QueueItem> items) {
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
    if (_smartOn) _pickedUids.addAll(items.map((e) => e.uid));
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
    if (i != state.index) {
      _leave(TrackExit.jumped);
      // Escolheu essa na fila: conta como escolha quando começar.
      if (_smartOn) _pickedUids.add(state.queue[i].uid);
    }
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
    _leave(TrackExit.interrupted);
    engine.playerStop();
    state = state.copyWith(playing: false, position: Duration.zero);
  }

  void next() {
    if (_fwd('next')) return;
    final n = _nextIndex(manual: true);
    if (n == null) return;
    _leave(TrackExit.skipped);
    _startAt(n);
  }

  void previous() {
    if (_fwd('previous')) return;
    if (state.position > const Duration(seconds: 3) || state.index <= 0) {
      // Voltou para o começo desta depois de ouvir um bom pedaço: quis ouvir
      // de novo.
      final cur = state.current;
      if (_smartOn && cur != null && _listened >= Listen.quick) {
        _smart!.note(cur.song, SmartWeights.replay, kind: SmartKind.replay);
      }
      seek(Duration.zero);
      return;
    }
    // Voltou para a anterior: quer ouvir aquela de novo; esta não foi julgada.
    _leave(TrackExit.interrupted);
    if (_smartOn) _smart!.note(state.queue[state.index - 1].song, SmartWeights.replay, kind: SmartKind.replay);
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

  /// Gira o disco de vinil (tela tocando agora): [speed] é a velocidade da
  /// agulha — 1 é o normal, 0 é o disco parado na mão e negativo toca de trás
  /// para frente. Acima de [maxSpeed] a agulha levanta (0 = sem limite).
  /// `null` solta o disco. Num aparelho remoto não há o que girar daqui: o som
  /// sai lá.
  void vinyl(double? speed, {double maxSpeed = 0}) {
    if (_mirroring) return;
    engine.playerSetVinyl(speed: speed ?? 1.0, maxSpeed: maxSpeed, active: speed != null);
  }

  /// Prepara a memória do disco de vinil: daqui em diante o motor guarda o que
  /// toca, e é esse passado que dá para voltar girando. Tem que ser **antes**
  /// do gesto — memória que chega junto com a mão nasce vazia, e aí voltar o
  /// disco não toca nada. [memorySeconds] em 0 = a faixa inteira.
  void prepareVinyl(double memorySeconds) {
    if (_mirroring) return;
    final secs = memorySeconds > 0 ? memorySeconds : state.duration.inSeconds.toDouble();
    if (secs <= 0) return;
    engine.playerPrepareVinyl(memorySecs: secs);
  }

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

  /// Volume relativo ao salvo (timer para dormir), sem gravar. No modo remoto
  /// não mexe (o volume de lá é do outro aparelho).
  void fadeVolume(double factor) {
    if (_mirroring) return;
    engine.playerSetVolume(volume: _gain(state.volume) * factor.clamp(0.0, 1.0));
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
    // Troca na mão que nenhum comando julgou (tirou da fila, voltou a tocar
    // depois de parar, erro): a que saiu não diz nada.
    _leave(TrackExit.interrupted);
    if (start > const Duration(seconds: 5)) _startMid.add(item.uid);
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
    // Tocando em outro aparelho: o motor daqui não tem o que preparar.
    if (_mirroring) return;
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
  /// usam a qualidade com que foram baixadas (`downloadBitRate` ao baixar;
  /// depois, a que a coleção guardou), nunca a do streaming: assim o download
  /// é achado mesmo que a qualidade de streaming mude.
  engine.TrackSource? sourceFor(Song song, {String? uid, (double, double?)? gain, bool offline = false, int downloadBitRate = 0}) {
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
    // Qualidade da cópia baixada (0 = original); null = não baixada.
    final dl = offline ? downloadBitRate : ref.read(offlineProvider.notifier).bitRateFor(song.id);
    // Formato que o motor não decodifica (WMA etc.): o servidor converte, até no download.
    final convert = _undecodable.contains(song.suffix?.toLowerCase());
    // Nos dados móveis, a qualidade escolhida para eles. Conversão sempre para
    // MP3: toda instalação do Navidrome converte para ele.
    final rate = streamBitRate(s, metered: ref.read(meteredProvider));
    final want = dl ?? rate; // kbps pedido ao servidor; 0 = original
    final format = convert || want > 0 ? 'mp3' : null;
    final bitrate = want > 0 ? want : null;
    final (g, peak) = gain ?? (0.0, null);
    // Análise pronta no servidor de análise: só se o arquivo tocado é o mesmo
    // que ele analisou (o original, ou o MP3 que o servidor converte dos
    // formatos que o motor não lê), senão as batidas podem estar deslocadas.
    final server = s.analysisServer;
    final sameFile = bitrate == null && (format == null || (convert && format == 'mp3'));
    final analysisUrl = server != null && sameFile ? p.analyzerUri(server, '/api/analysis/${Uri.encodeComponent(song.id)}')?.toString() : null;
    // Original num formato que o motor acabe não abrindo (um codec dentro do
    // contêiner que ele não conhece): toca a conversão para MP3.
    final fallback = format == null;
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
      fallbackUrl: fallback ? p.streamUri(song, format: 'mp3', maxBitRate: bitrate).toString() : null,
      fallbackCacheKey: fallback ? p.streamCacheKey(song, format: 'mp3', maxBitRate: bitrate) : null,
      fallbackFormatHint: fallback ? 'mp3' : null,
    );
  }

  void _onEvent(engine.PlayerEvent e) {
    // Controlando outro aparelho: o motor daqui está parado. Os botões de
    // mídia do sistema (MPRIS) ainda chegam por ele, e vão para lá.
    if (_mirroring) {
      if (e case engine.PlayerEvent_MediaControl(:final action)) _onMediaAction(action);
      return;
    }
    switch (e) {
      case engine.PlayerEvent_TrackStarted(:final id):
        final i = state.queue.indexWhere((q) => q.uid == id);
        if (i >= 0) {
          // A anterior saiu sozinha: acabou, ou o AutoMix começou a passar
          // para esta.
          _leave(TrackExit.ended);
          final item = state.queue[i];
          state = state.copyWith(
            index: i,
            position: Duration.zero,
            duration: item.song.duration ?? Duration.zero,
          );
          _scheduleNext();
          _beginScrobble(item);
          if (_pickedUids.remove(item.uid) && _smartOn) {
            _smart!.note(item.song, SmartWeights.picked, kind: SmartKind.picked);
          }
          _preAnalyze(i);
          if (state.dj) {
            _djExtend();
          } else if (state.smart) {
            _maybeExtendSmart();
          } else {
            _maybeExtendRadio();
          }
        }
      case engine.PlayerEvent_TrackEnded(:final id, :final error):
        if (error != null) {
          final item = state.queue.where((q) => q.uid == id).firstOrNull;
          if (item != null) unawaited(_recover(item, error));
        }
      case engine.PlayerEvent_Position(:final id, :final positionMs, :final durationMs, :final buffered):
        if (state.current?.uid != id) return;
        final pos = Duration(milliseconds: positionMs);
        final duration = durationMs != null ? Duration(milliseconds: durationMs) : state.duration;
        final buf = buffered ?? state.buffered;
        // Nada mudou: não acorda quem observa o player (tela, notificação, Connect).
        if (pos == state.position && duration == state.duration && buf == state.buffered) return;
        _trackListening(pos);
        final now = DateTime.now();
        if (now.difference(_lastPositionSave) > const Duration(seconds: 15)) {
          _lastPositionSave = now;
          _savePosition();
        }
        // Só agenda se não houver um agendado: remarcar a cada evento (4 por
        // segundo) empurrava o timer para frente sem parar, e a fila nunca ia
        // para o servidor com uma música carregada.
        if (now.difference(_lastServerSync) > const Duration(seconds: 60) && !(_syncTimer?.isActive ?? false)) {
          _syncSoon();
        }
        state = state.copyWith(position: pos, duration: duration, buffered: buf);
      case engine.PlayerEvent_State(:final playing, :final buffering, :final hasTrack):
        _engineHasTrack = hasTrack;
        _notePause(playing);
        state = state.copyWith(playing: playing, buffering: buffering);
        if (!hasTrack && state.current != null && _nextIndex() == null) {
          // Fim da fila.
          _leave(TrackExit.ended);
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
  /// Entradas da fila que já ganharam a segunda chance (uid): falhou de novo,
  /// aí sim é erro.
  final _retried = <String>{};

  /// Não tocou: antes de mostrar o erro, atualiza a música no servidor e tenta
  /// de novo. Quase sempre é música trocada por um arquivo melhor, com id novo
  /// no Navidrome (ver `currentVersion`), guardada com o id velho na fila, numa
  /// lista aberta antes ou num download; às vezes é só o servidor ocupado.
  Future<void> _recover(QueueItem item, String error) async {
    final p = _provider;
    if (item.song.path != null || p == null || !_retried.add(item.uid)) {
      _failed(item, error);
      return;
    }
    // Caiu no meio (servidor ocupado, rede): volta de onde parou.
    final at = state.current?.uid == item.uid ? state.position : Duration.zero;
    final failedAt = DateTime.now();
    Song? now;
    try {
      now = await currentVersion(p, item.song);
    } catch (e) {
      debugPrint('atualizando "${item.song.title}": $e');
    }
    final i = state.queue.indexWhere((q) => q.uid == item.uid);
    if (i < 0) return;
    if (now == null) {
      _failed(item, error);
      return;
    }
    final fresh = _item(now);
    _retried.add(fresh.uid);
    _replace(i, fresh);
    // O motor já passou para a seguinte: volta para esta, se foi agora há pouco.
    final justNow = DateTime.now().difference(failedAt) < const Duration(seconds: 10);
    if (state.index == i || (justNow && state.index == i + 1 && state.position < const Duration(seconds: 10))) {
      _startAt(i, start: at);
    } else {
      _scheduleNext();
    }
    if (now.id != item.song.id) unawaited(_refreshUpcoming(p, i + 1));
  }

  void _failed(QueueItem item, String error) {
    // O motor junta as camadas ("formato não reconhecido: …: servidor: …");
    // o que interessa é o que o servidor disse.
    final i = error.indexOf('servidor: ');
    final why = error.contains('no such file')
        ? 'o arquivo não existe mais no servidor, e não achei outra versão dela'
        : i >= 0
            ? error.substring(i)
            : error;
    state = state.copyWith(message: 'Não foi possível tocar "${item.song.title}": $why');
  }

  void _replace(int i, QueueItem fresh) {
    final old = state.queue[i];
    final q = List.of(state.queue)..[i] = fresh;
    final j = _unshuffled?.indexWhere((e) => e.uid == old.uid) ?? -1;
    if (j >= 0) _unshuffled![j] = fresh;
    state = state.copyWith(queue: q);
  }

  bool _refreshing = false;

  /// Achou uma música trocada: as outras da fila provavelmente foram guardadas
  /// na mesma época. Confere as próximas antes de chegar nelas, para não
  /// engasgar uma por uma, e as últimas que tocaram, para o "anterior".
  Future<void> _refreshUpcoming(MusicProvider p, int from) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final q = state.queue;
      final before = from - 1;
      final upcoming = [...q.skip(from).take(50), ...q.sublist(max(0, before - 20), max(0, before)).reversed];
      for (final item in upcoming) {
        if (item.song.path != null || _provider != p) continue;
        Song? now;
        try {
          now = await currentVersion(p, item.song, strict: true);
        } catch (_) {
          return;
        }
        if (now == null || now.id == item.song.id) continue;
        final i = state.queue.indexWhere((q) => q.uid == item.uid);
        if (i < 0 || i == state.index) continue;
        _replace(i, _item(now));
        if (i == state.index + 1) _scheduleNext();
      }
      _persistSoon();
    } finally {
      _refreshing = false;
    }
  }

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
    if (_mirroring) return;
    ref.read(settingsProvider.notifier).update((s) => s.automixEnabled ? s : s.copyWith(automixEnabled: true));
    _djHeard.clear();
    _startingDj = true;
    playSongs([seed]);
    _startingDj = false;
    state = state.copyWith(dj: true, radio: false, smart: false);
    _djExtend();
  }

  void setDj(bool on) {
    if (_jam != null) return;
    if (on) _dropSmart();
    state = state.copyWith(dj: on, radio: on ? false : state.radio, smart: on ? false : state.smart);
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
    if (!state.dj || _djBusy || _mirroring) return;
    final cur = state.current;
    final p = _provider;
    if (cur == null || p == null || state.queue.length - state.index - 1 >= 1) return;
    _djBusy = true;
    try {
      _djHeard.add(cur.song.id);
      // O método escolhido também manda aqui, e já vem com a nota de quanto
      // combina (do servidor é a medida dele; local é a ordem da lista).
      final s = ref.read(settingsProvider);
      var cands = await findSimilarScored(p, cur.song,
          count: 30,
          lastFm: s.lastFmForRadio ? ref.read(lastFmProvider) : null,
          local: ref.read(recommendProvider.notifier));
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
  /// (em ordem de chegada), ou no fim da fila com [atEnd]. Com nada tocando,
  /// começa por elas.
  List<String> jamInsert(List<Song> songs, {bool atEnd = false}) {
    if (songs.isEmpty) return const [];
    if (_fwd(atEnd ? 'enqueue' : 'playNext', {'songs': _json(songs)})) return const [];
    final items = songs.map(_item).toList();
    var at = state.index + 1;
    if (atEnd) {
      at = state.queue.length;
    } else {
      while (at < state.queue.length && _jamUids.contains(state.queue[at].uid)) {
        at++;
      }
      _jamUids.addAll(items.map((e) => e.uid));
    }
    final q = List.of(state.queue)..insertAll(at, items);
    _unshuffled?.addAll(items);
    state = state.copyWith(queue: q, index: state.index < 0 ? 0 : state.index);
    if (state.current == null || (!state.playing && !state.buffering && !_engineHasTrack)) {
      _startAt(at);
    } else {
      _scheduleNext();
    }
    return [for (final e in items) e.uid];
  }

  /// Pula para a entrada [uid] da fila (convidado da Festa tocou nela).
  void jumpToUid(String uid) {
    final i = state.queue.indexWhere((q) => q.uid == uid);
    if (i >= 0) jumpTo(i);
  }

  // ---- Convidado numa Festa ----

  JamRemote? _jam;

  /// Como estava o player daqui ao entrar na Festa: volta assim, pausado.
  PlayerState? _beforeJam;

  /// O som sai de outro aparelho (Connect ou Festa).
  bool get _mirroring => _remote != null || _jam != null;

  bool get inJam => _jam != null;

  /// Sai da Festa como convidado (o timer para dormir, por exemplo): o som
  /// do dono segue para os outros.
  Future<void> exitJam() async => _jam?.leave();

  /// Entrou numa Festa: o som sai do dono, e este player passa a mostrar e
  /// controlar o que toca lá — barra, tela cheia, fila, notificação e os
  /// botões de tocar das páginas, como no Connect. A fila daqui fica guardada
  /// para a volta.
  Future<void> enterJam(JamRemote jam, String host) async {
    if (_jam != null) {
      _jam = jam;
      state = PlayerState(volume: state.volume, jamHost: host);
      return;
    }
    if (_remote != null) {
      // Estava controlando outro aparelho: deixa ele tocando e volta para cá.
      final remote = state;
      await _dropRemote();
      _adoptFromRemote(remote, play: false);
    }
    if (state.current != null) await _persistNow();
    _mixTimer?.cancel();
    engine.playerStop();
    _engineHasTrack = false;
    _scheduledKey = null;
    _beforeJam = state;
    _jam = jam;
    state = PlayerState(volume: state.volume, jamHost: host);
  }

  /// O que toca na Festa agora, como o dono mandou: a atual e as próximas.
  void jamMirror({
    required String host,
    required List<QueueItem> queue,
    required bool playing,
    required Duration position,
    required Duration duration,
  }) {
    if (_jam == null) return;
    state = PlayerState(
      queue: queue,
      index: queue.isEmpty ? -1 : 0,
      playing: playing,
      position: position,
      duration: duration,
      volume: state.volume,
      jamHost: host,
    );
  }

  /// Saiu da Festa (ou ela acabou): volta a fila daqui, pausada onde estava.
  void leaveJam() {
    if (_jam == null) return;
    _jam = null;
    final before = _beforeJam;
    _beforeJam = null;
    if (before == null) {
      state = PlayerState(volume: state.volume);
      return;
    }
    _resumeAt = before.position;
    state = before.copyWith(playing: false, buffering: false, clearMix: true, clearPlanned: true, clearMessage: true);
  }

  // ---- Tocar em outro aparelho (BKmasterplayer Connect) ----

  ConnectLink? _remote;
  StreamSubscription<Map<String, dynamic>>? _remoteSub;
  List<QueueItem> _remoteQueue = const [];

  bool get isRemote => _mirroring;

  static List<Map<String, dynamic>> _json(List<Song> songs) => [for (final s in songs) s.toJson()];

  /// No modo remoto, manda o comando para o outro aparelho (e devolve true).
  bool _fwd(String c, [Map<String, dynamic> args = const {}]) {
    final r = _remote;
    if (r != null) {
      r.cmd(c, args);
      return true;
    }
    final j = _jam;
    if (j == null) return false;
    j.command(c, args);
    return true;
  }

  /// Passa a tocar em [device]. Com [transfer], a fila daqui vai para lá e
  /// continua do mesmo ponto; sem, só controla o que ele já está tocando.
  Future<void> connectTo(ConnectDevice device, {required bool transfer}) async {
    final p = _provider;
    final me = ref.read(connectProvider.notifier).me;
    if (p == null || me == null) throw StateError('Connect indisponível');
    // Escolher um aparelho é sair da Festa: o som passa a ser o daqui.
    await _jam?.leave();
    final key = p.connectKey;
    if (key == null) throw const ConnectAuthException('entre de novo na conta neste aparelho para usar o Connect');
    final link = await ConnectLink.open(device, key: key, me: me);
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
        'smart': local.smart,
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
    _dropSmart();
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
      smart: remote.smart,
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
          smart: m['sm'] == true,
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
    bool smart = false,
  }) {
    if (songs.isEmpty) return;
    _leave(TrackExit.interrupted);
    final items = songs.map(_item).toList();
    final i = index.clamp(0, items.length - 1);
    _unshuffled = null;
    // O que o outro aparelho aprendeu ficou lá: aqui recomeça a partir da atual.
    _dropSmart();
    if (smart) _smart = SmartSession(seed: items[i].song);
    state = state.copyWith(queue: items, shuffle: shuffle, repeat: repeat, radio: radio, smart: smart, clearMessage: true);
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
    _judgedUid = null;
    _fromMiddle = _startMid.remove(item.uid);
    _pausedSince = null;
    _pausedLong = false;
    _provider?.scrobble(item.song.id, submission: false).catchError((_) {});
  }

  void _trackListening(Duration pos) {
    final item = state.current;
    if (item == null || item.uid != _scrobbleUid) return;
    final delta = pos - _lastPos;
    _lastPos = pos;
    if (state.playing && delta > Duration.zero && delta < const Duration(seconds: 2)) {
      _listened += delta;
    }
    // O aleatório smart segue contando até a música sair; o registro no
    // servidor é um só.
    if (_submitted) return;
    final dur = item.song.duration ?? state.duration;
    final threshold = Duration(milliseconds: min(dur.inMilliseconds ~/ 2, 4 * 60 * 1000));
    if (dur > const Duration(seconds: 30) && _listened >= threshold) {
      _submitted = true;
      _provider?.scrobble(item.song.id, submission: true, time: _startedAt).catchError((_) {});
    }
  }
}

final playerProvider = NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
