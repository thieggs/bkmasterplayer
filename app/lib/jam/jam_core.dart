import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../connect/connect_service.dart';
import '../core/providers.dart';
import '../domain/models.dart';
import '../player/player_controller.dart';
import '../ui/widgets/cover_art.dart';

/// Jam: quem está perto entra na música deste aparelho, adiciona músicas (da
/// biblioteca daqui ou mandando as suas) e controla a reprodução. Ninguém
/// entra sem o dono aceitar, a não ser quem ele pôs em "aceitar sempre".
///
/// A lógica não depende do meio: pela rede local (Wi-Fi, via Connect) ou por
/// Bluetooth/Wi-Fi Direct (Nearby, no Android). As mensagens são mapas JSON
/// com o tipo em 't'; as músicas mandadas pelos convidados vão como arquivo.

/// Conexão com um participante (lado do dono) ou com o dono (lado do convidado).
abstract class JamLink {
  String get peerId;
  String get peerName;

  /// 'wifi' ou 'bluetooth'.
  String get via;

  /// Mensagens do outro lado; fecha quando a conexão cai.
  Stream<Map<String, dynamic>> get messages;
  void send(Map<String, dynamic> m);

  /// Manda um arquivo (música do convidado).
  Future<void> sendFile(String path, String fileId, {void Function(double progress)? onProgress});

  /// Arquivos recebidos: (id, caminho).
  Stream<(String, String)> get files;
  Future<void> close();
}

/// Pedido para entrar na Jam (lado do dono).
class JamJoinRequest {
  JamJoinRequest({required this.guestId, required this.guestName, required this.via});
  final String guestId;
  final String guestName;
  final String via;
  final decision = Completer<bool>();
  final at = DateTime.now();
}

/// Jam encontrada por perto (lado do convidado).
class JamOffer {
  const JamOffer({required this.key, required this.hostName, required this.via, required this.join});
  final String key;
  final String hostName;
  final String via;
  final Future<JamLink> Function(String myId, String myName) join;
}

class JamRejected implements Exception {
  const JamRejected();
}

/// Transporte extra (Nearby no Android). A rede local vem do Connect.
abstract class JamTransport {
  bool get available;
  Future<void> startHosting({
    required String hostName,
    required String hostId,
    required String jamId,
    required Future<bool> Function(JamJoinRequest req) onRequest,
    required void Function(JamLink link) onJoined,
  });
  Future<void> stopHosting();
  Stream<List<JamOffer>> discover({required String myId, required String myName});
  Future<void> stopDiscovery();
}

/// Transporte Nearby registrado pelo Android (null no desktop).
JamTransport? jamNearby;

String _randomId([int len = 12]) {
  final r = Random.secure();
  return List.generate(len, (_) => r.nextInt(36).toRadixString(36)).join();
}

// ---- Rede local ----

class _LanLink implements JamLink {
  /// [sub] é a assinatura do socket já aberta no aperto de mão (um WebSocket
  /// só pode ser ouvido uma vez): o link passa a receber por ela.
  _LanLink(this._ws, this._sub,
      {required this.peerId, required this.peerName, this.uploadUrl, List<Map<String, dynamic>> pending = const []}) {
    for (final m in pending) {
      _messages.add(m);
    }
    _sub.onData((d) {
      if (d is! String) return;
      try {
        final m = jsonDecode(d);
        if (m is Map) _messages.add(Map<String, dynamic>.from(m));
      } catch (_) {}
    });
    _sub.onDone(_closed);
    _sub.onError((_) => _closed());
  }

  final WebSocket _ws;
  final StreamSubscription<dynamic> _sub;
  final _messages = StreamController<Map<String, dynamic>>();
  final _files = StreamController<(String, String)>.broadcast();

  /// Endereço de upload no dono (lado do convidado).
  final Uri? uploadUrl;

  @override
  final String peerId;
  @override
  final String peerName;
  @override
  String get via => 'wifi';
  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Stream<(String, String)> get files => _files.stream;

  void _closed() {
    if (!_messages.isClosed) _messages.close();
    if (!_files.isClosed) _files.close();
  }

  void fileArrived(String id, String path) {
    if (!_files.isClosed) _files.add((id, path));
  }

  @override
  void send(Map<String, dynamic> m) {
    if (_ws.readyState == WebSocket.open) _ws.add(jsonEncode(m));
  }

  @override
  Future<void> sendFile(String path, String fileId, {void Function(double)? onProgress}) async {
    final url = uploadUrl;
    if (url == null) throw StateError('sem upload');
    final file = File(path);
    final total = await file.length();
    final client = HttpClient();
    try {
      final req = await client.postUrl(url.replace(queryParameters: {...url.queryParameters, 'f': fileId}));
      req.contentLength = total;
      var sent = 0;
      await req.addStream(file.openRead().map((chunk) {
        sent += chunk.length;
        onProgress?.call(total == 0 ? 1 : sent / total);
        return chunk;
      }));
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode != 200) throw HttpException('upload: HTTP ${res.statusCode}');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    try {
      await _ws.close();
    } catch (_) {}
    _closed();
  }
}

/// Entra numa Jam da rede local.
Future<JamLink> joinLan(LanJamOffer offer, String myId, String myName) async {
  final ws = await WebSocket.connect('ws://${offer.host}:${offer.port}/jam').timeout(const Duration(seconds: 6));
  ws.pingInterval = const Duration(seconds: 8);
  ws.add(jsonEncode({'t': 'hello', 'id': myId, 'n': myName}));
  // Espera o dono decidir (pode demorar: ele precisa tocar em "Aceitar").
  final first = Completer<Map<String, dynamic>>();
  final early = <Map<String, dynamic>>[];
  late StreamSubscription<dynamic> sub;
  sub = ws.listen((d) {
    if (d is! String) return;
    final m = Map<String, dynamic>.from(jsonDecode(d) as Map);
    if (!first.isCompleted) {
      first.complete(m);
    } else {
      early.add(m);
    }
  }, onDone: () {
    if (!first.isCompleted) first.completeError(const JamRejected());
  }, onError: (_) {
    if (!first.isCompleted) first.completeError(const JamRejected());
  });
  final Map<String, dynamic> m;
  try {
    m = await first.future.timeout(const Duration(minutes: 3));
  } catch (_) {
    await sub.cancel();
    await ws.close();
    rethrow;
  }
  if (m['t'] != 'welcome') {
    await sub.cancel();
    await ws.close();
    throw const JamRejected();
  }
  // O link continua na mesma assinatura; o que já chegou vai junto.
  final upload = Uri(
    scheme: 'http',
    host: offer.host,
    port: offer.port,
    path: '/jam/upload',
    queryParameters: {'t': m['token'] as String? ?? ''},
  );
  return _LanLink(ws, sub,
      peerId: offer.deviceId, peerName: m['n'] as String? ?? offer.name, uploadUrl: upload, pending: [m, ...early]);
}

// ---- Lista de aceitos automaticamente ----

class JamAllowed {
  const JamAllowed(this.id, this.name);
  final String id;
  final String name;
}

class JamAllowlistNotifier extends Notifier<List<JamAllowed>> {
  static const _key = 'jamAllowlist';

  @override
  List<JamAllowed> build() {
    final raw = ref.watch(prefsProvider).getStringList(_key) ?? const [];
    return [
      for (final e in raw)
        if (jsonDecode(e) case {'id': final String id, 'n': final String n}) JamAllowed(id, n),
    ];
  }

  bool allows(String id) => state.any((a) => a.id == id);

  void add(String id, String name) {
    state = [...state.where((a) => a.id != id), JamAllowed(id, name)];
    _save();
  }

  void remove(String id) {
    state = state.where((a) => a.id != id).toList();
    _save();
  }

  void _save() =>
      ref.read(prefsProvider).setStringList(_key, [for (final a in state) jsonEncode({'id': a.id, 'n': a.name})]);
}

final jamAllowlistProvider = NotifierProvider<JamAllowlistNotifier, List<JamAllowed>>(JamAllowlistNotifier.new);

String _myId(Ref ref) => deviceIdFor(ref.read(prefsProvider));

Future<String> _myName(Ref ref) async {
  final custom = ref.read(settingsProvider).deviceName;
  return (custom == null || custom.trim().isEmpty) ? await systemDeviceName() : custom.trim();
}

/// Capa pequena (para mandar pela Jam): PNG de até 160 px.
Future<Uint8List?> _thumb(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

// ---- Dono da Jam ----

class JamParticipant {
  const JamParticipant({required this.link, required this.id, required this.name, required this.via});
  final JamLink link;
  final String id;
  final String name;
  final String via;
}

class JamHostState {
  const JamHostState({this.active = false, this.jamId, this.participants = const [], this.pending = const []});
  final bool active;
  final String? jamId;
  final List<JamParticipant> participants;

  /// Pedidos esperando o dono aceitar ou recusar.
  final List<JamJoinRequest> pending;

  JamHostState copyWith({List<JamParticipant>? participants, List<JamJoinRequest>? pending}) => JamHostState(
        active: active,
        jamId: jamId,
        participants: participants ?? this.participants,
        pending: pending ?? this.pending,
      );
}

class JamHostNotifier extends Notifier<JamHostState> implements JamLanRoutes {
  String _name = '';
  final _tokens = <String, _LanLink>{};
  final _addedBy = <String, String>{};

  /// Músicas daqui mostradas aos convidados (id → música com o arquivo, se
  /// local): o "adicionar" usa estas, nunca o que o convidado manda de volta.
  final _shown = <String, Song>{};
  Timer? _announce;
  Timer? _statePush;
  bool _pushQueued = false;

  @override
  JamHostState build() {
    ref.listen(playerProvider, (_, _) => _schedulePush());
    ref.onDispose(_shutdown);
    return const JamHostState();
  }

  @override
  String get jamId => state.jamId ?? '';
  @override
  String get jamName => _name;

  /// Quem adicionou cada música (uid da fila → nome).
  Map<String, String> get addedBy => _addedBy;

  Directory get _dir => Directory(p.join(ref.read(cacheDirProvider).path, 'jam'));

  Future<void> start() async {
    if (state.active) return;
    _name = await _myName(ref);
    final id = _randomId();
    state = JamHostState(active: true, jamId: id);
    await _dir.create(recursive: true);
    final connect = ref.read(connectProvider.notifier);
    connect.jamRoutes = this;
    await connect.announceJam();
    _announce = Timer.periodic(const Duration(seconds: 5), (_) => connect.announceJam());
    final nearby = jamNearby;
    if (nearby != null && nearby.available) {
      try {
        await nearby.startHosting(
          hostName: _name,
          hostId: _myId(ref),
          jamId: id,
          onRequest: _decide,
          onJoined: (link) => _attach(link),
        );
      } catch (e) {
        debugPrint('Jam por Bluetooth indisponível: $e');
      }
    }
  }

  Future<void> stop() async {
    if (!state.active) return;
    for (final pa in state.participants) {
      pa.link.send({'t': 'bye'});
      await pa.link.close();
    }
    for (final r in state.pending) {
      if (!r.decision.isCompleted) r.decision.complete(false);
    }
    _shutdown();
    state = const JamHostState();
  }

  void _shutdown() {
    _announce?.cancel();
    _statePush?.cancel();
    _tokens.clear();
    try {
      final connect = ref.read(connectProvider.notifier);
      if (identical(connect.jamRoutes, this)) connect.jamRoutes = null;
    } catch (_) {}
    jamNearby?.stopHosting();
  }

  /// Decide um pedido: aceito automaticamente se a pessoa está na lista;
  /// senão espera o dono (acceptRequest/rejectRequest).
  Future<bool> _decide(JamJoinRequest req) {
    if (ref.read(jamAllowlistProvider.notifier).allows(req.guestId)) {
      req.decision.complete(true);
      return req.decision.future;
    }
    state = state.copyWith(pending: [...state.pending, req]);
    // Sem resposta em 2 minutos: recusa.
    Timer(const Duration(minutes: 2), () {
      if (!req.decision.isCompleted) respond(req, accept: false);
    });
    return req.decision.future;
  }

  void respond(JamJoinRequest req, {required bool accept, bool always = false}) {
    if (accept && always) ref.read(jamAllowlistProvider.notifier).add(req.guestId, req.guestName);
    state = state.copyWith(pending: state.pending.where((r) => r != req).toList());
    if (!req.decision.isCompleted) req.decision.complete(accept);
  }

  // Rede local: o convidado abre um WebSocket em /jam e se apresenta.
  @override
  void handleSocket(WebSocket ws, String remoteIp) async {
    ws.pingInterval = const Duration(seconds: 8);
    final hello = Completer<Map<String, dynamic>?>();
    late StreamSubscription<dynamic> sub;
    sub = ws.listen((d) {
      if (hello.isCompleted || d is! String) return;
      try {
        hello.complete(Map<String, dynamic>.from(jsonDecode(d) as Map));
      } catch (_) {
        hello.complete(null);
      }
    }, onDone: () {
      if (!hello.isCompleted) hello.complete(null);
    });
    final m = await hello.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (m == null || m['t'] != 'hello' || m['id'] is! String || !state.active) {
      await sub.cancel();
      await ws.close();
      return;
    }
    final req = JamJoinRequest(guestId: m['id'] as String, guestName: m['n'] as String? ?? remoteIp, via: 'wifi');
    final ok = await _decide(req);
    if (!ok || !state.active) {
      try {
        ws.add(jsonEncode({'t': 'rejected'}));
        await sub.cancel();
        await ws.close();
      } catch (_) {}
      return;
    }
    final token = _randomId(20);
    final link = _LanLink(ws, sub, peerId: req.guestId, peerName: req.guestName);
    _tokens[token] = link;
    link.send({'t': 'welcome', 'n': _name, 'jid': jamId, 'token': token});
    _attach(link);
  }

  @override
  Future<void> handleUpload(HttpRequest req) async {
    final link = _tokens[req.uri.queryParameters['t']];
    final fid = req.uri.queryParameters['f'];
    if (link == null || fid == null || !RegExp(r'^[a-z0-9]{6,32}$').hasMatch(fid)) {
      req.response.statusCode = 403;
      await req.response.close();
      return;
    }
    final out = File(p.join(_dir.path, fid));
    final sink = out.openWrite();
    var size = 0;
    try {
      await for (final chunk in req) {
        size += chunk.length;
        if (size > 200 * 1024 * 1024) throw const FileSystemException('arquivo grande demais');
        sink.add(chunk);
      }
      await sink.close();
      req.response.statusCode = 200;
      await req.response.close();
      link.fileArrived(fid, out.path);
    } catch (_) {
      await sink.close();
      try {
        await out.delete();
      } catch (_) {}
      req.response.statusCode = 400;
      await req.response.close();
    }
  }

  void _attach(JamLink link) {
    final pa = JamParticipant(link: link, id: link.peerId, name: link.peerName, via: link.via);
    state = state.copyWith(participants: [...state.participants.where((x) => x.id != pa.id), pa]);
    if (link.via != 'wifi') link.send({'t': 'welcome', 'n': _name, 'jid': jamId});
    link.send(_stateMessage());
    final offers = <String, Map<String, dynamic>>{};
    link.files.listen((f) => _fileReceived(pa, offers.remove(f.$1), f.$1, f.$2));
    link.messages.listen(
      (m) => _onGuest(pa, m, offers),
      onDone: () {
        state = state.copyWith(participants: state.participants.where((x) => x.link != link).toList());
      },
    );
  }

  /// Tira um participante da Jam.
  Future<void> kick(JamParticipant pa) async {
    pa.link.send({'t': 'bye'});
    await pa.link.close();
    state = state.copyWith(participants: state.participants.where((x) => x != pa).toList());
  }

  Future<void> _onGuest(JamParticipant pa, Map<String, dynamic> m, Map<String, Map<String, dynamic>> offers) async {
    final player = ref.read(playerProvider.notifier);
    switch (m['t']) {
      case 'search':
        final q = '${m['q'] ?? ''}'.trim();
        List<Song> songs;
        try {
          final provider = ref.read(musicProvider);
          songs = q.isEmpty ? await provider.randomSongs(size: 30) : (await provider.search(q, artistCount: 0, albumCount: 0, songCount: 40)).songs;
        } catch (_) {
          songs = const [];
        }
        if (_shown.length > 3000) _shown.clear();
        for (final s in songs) {
          _shown[s.id] = s;
        }
        pa.link.send({'t': 'results', 'req': m['req'], 'songs': [for (final s in songs) _songJson(s)]});
      case 'add':
        final local = ref.read(sessionProvider).value?.isLocal ?? false;
        final songs = <Song>[];
        for (final e in (m['songs'] as List? ?? const [])) {
          if (e is! Map) continue;
          final known = _shown[e['id']];
          if (known != null) {
            songs.add(known);
          } else if (!local && e['id'] is String) {
            // Do servidor: a música é identificada pelo id (sem caminho de arquivo).
            songs.add(Song.fromJson(Map<String, dynamic>.from(e)..remove('path')));
          }
        }
        final uids = player.jamInsert(songs);
        for (final u in uids) {
          _addedBy[u] = pa.name;
        }
      case 'cmd':
        switch (m['c']) {
          case 'toggle':
            player.toggle();
          case 'next':
            player.next();
          case 'previous':
            player.previous();
          case 'seek':
            player.seek(Duration(milliseconds: (m['ms'] as num?)?.toInt() ?? 0));
        }
      case 'offer':
        final fid = m['fid'];
        if (fid is! String || !RegExp(r'^[a-z0-9]{6,32}$').hasMatch(fid)) return;
        offers[fid] = m;
        pa.link.send({'t': 'accept', 'fid': fid});
      case 'cover':
        final id = m['id'];
        if (id is! String) return;
        final bytes = await _coverBytes(id);
        if (bytes != null) pa.link.send({'t': 'cover', 'id': id, 'b64': base64Encode(bytes)});
      case 'bye':
        await pa.link.close();
    }
  }

  Future<void> _fileReceived(JamParticipant pa, Map<String, dynamic>? offer, String fid, String path) async {
    if (offer == null) return;
    final j = Map<String, dynamic>.from(offer['song'] as Map? ?? const {});
    // Formato pela extensão do nome original (o arquivo chega sem extensão).
    final ext = (j['suffix'] as String?)?.replaceAll(RegExp(r'[^a-z0-9]'), '') ?? 'mp3';
    final target = '$path.$ext';
    await File(path).rename(target);
    String? cover;
    final b64 = offer['cover'];
    if (b64 is String && b64.isNotEmpty) {
      try {
        final c = File('$path.cover.png');
        await c.writeAsBytes(base64Decode(b64));
        cover = c.path;
      } catch (_) {}
    }
    final song = Song(
      id: 'jam:$fid',
      title: j['title'] as String? ?? 'Música de ${pa.name}',
      artist: j['artist'] as String?,
      album: j['album'] as String?,
      duration: j['duration'] is int ? Duration(milliseconds: j['duration'] as int) : null,
      suffix: ext,
      coverArt: cover,
      path: target,
    );
    final uids = ref.read(playerProvider.notifier).jamInsert([song]);
    for (final u in uids) {
      _addedBy[u] = pa.name;
    }
    pa.link.send({'t': 'queued', 'fid': fid, 'title': song.title});
  }

  Future<Uint8List?> _coverBytes(String id) async {
    try {
      Uint8List bytes;
      if (isFileCover(id)) {
        bytes = await File(id).readAsBytes();
      } else {
        final provider = ref.read(musicProvider);
        final uri = provider.coverUri(id, size: 150);
        final key = provider.coverCacheKey(id, size: 150);
        if (uri == null || key == null) return null;
        final dir = p.join(ref.read(cacheDirProvider).path, 'ui_covers');
        bytes = await (await CoverImageProvider.fetchFile(url: uri.toString(), cacheKey: key, cacheDir: dir)).readAsBytes();
      }
      return bytes.length <= 40 * 1024 ? bytes : await _thumb(bytes);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _songJson(Song s, [String? uid]) => {
        ...s.toJson()..remove('path'),
        'uid': ?uid,
        'by': ?_addedBy[uid],
      };

  Map<String, dynamic> _stateMessage() {
    final s = ref.read(playerProvider);
    final cur = s.current;
    return {
      't': 'state',
      'playing': s.playing,
      'pos': s.position.inMilliseconds,
      'dur': s.duration.inMilliseconds,
      'cur': cur == null ? null : _songJson(cur.song, cur.uid),
      'next': [for (final q in s.queue.skip(s.index + 1).take(30)) _songJson(q.song, q.uid)],
      'people': state.participants.length,
    };
  }

  // Estado para os convidados: no máximo ~2 por segundo.
  void _schedulePush() {
    if (!state.active || state.participants.isEmpty) return;
    if (_statePush?.isActive ?? false) {
      _pushQueued = true;
      return;
    }
    _push();
    _statePush = Timer(const Duration(milliseconds: 500), () {
      if (_pushQueued) {
        _pushQueued = false;
        _push();
      }
    });
  }

  void _push() {
    final msg = _stateMessage();
    for (final pa in state.participants) {
      pa.link.send(msg);
    }
  }
}

final jamHostProvider = NotifierProvider<JamHostNotifier, JamHostState>(JamHostNotifier.new);

// ---- Convidado ----

enum JamPhase { idle, waiting, joined, rejected, ended }

class JamTransfer {
  const JamTransfer({required this.title, required this.progress, this.done = false, this.error});
  final String title;
  final double progress;
  final bool done;
  final String? error;
}

class JamGuestState {
  const JamGuestState({
    this.phase = JamPhase.idle,
    this.offers = const [],
    this.hostName,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.current,
    this.next = const [],
    this.transfers = const {},
  });
  final JamPhase phase;
  final List<JamOffer> offers;
  final String? hostName;
  final bool playing;
  final Duration position;
  final Duration duration;

  /// Tocando no dono (JSON da música + 'uid' e 'by').
  final Map<String, dynamic>? current;
  final List<Map<String, dynamic>> next;

  /// Músicas sendo mandadas daqui (id → progresso).
  final Map<String, JamTransfer> transfers;

  JamGuestState copyWith({
    JamPhase? phase,
    List<JamOffer>? offers,
    String? hostName,
    bool? playing,
    Duration? position,
    Duration? duration,
    Map<String, dynamic>? current,
    bool clearCurrent = false,
    List<Map<String, dynamic>>? next,
    Map<String, JamTransfer>? transfers,
  }) =>
      JamGuestState(
        phase: phase ?? this.phase,
        offers: offers ?? this.offers,
        hostName: hostName ?? this.hostName,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        current: clearCurrent ? null : (current ?? this.current),
        next: next ?? this.next,
        transfers: transfers ?? this.transfers,
      );
}

class JamGuestNotifier extends Notifier<JamGuestState> {
  JamLink? _link;
  StreamSubscription<List<JamOffer>>? _nearbySub;
  List<JamOffer> _nearbyOffers = const [];
  VoidCallback? _lanListener;
  int _req = 0;
  final _results = <int, Completer<List<Song>>>{};
  final _accepts = <String, Completer<void>>{};

  /// Capas pedidas ao dono (id → PNG).
  final covers = <String, Uint8List>{};
  final _coverWaiting = <String>{};
  final coverVersion = ValueNotifier(0);

  @override
  JamGuestState build() {
    ref.onDispose(() {
      _stopSearch();
      _link?.close();
    });
    return const JamGuestState();
  }

  bool get inJam => _link != null;

  /// Procura Jams por perto (rede local e, no Android, Bluetooth).
  Future<void> search() async {
    final connect = ref.read(connectProvider.notifier);
    _lanListener ??= () => _mergeOffers();
    connect.jamOffers.addListener(_lanListener!);
    await connect.refresh();
    final nearby = jamNearby;
    if (nearby != null && nearby.available && _nearbySub == null) {
      try {
        _nearbySub = nearby.discover(myId: _myId(ref), myName: await _myName(ref)).listen((o) {
          _nearbyOffers = o;
          _mergeOffers();
        });
      } catch (e) {
        debugPrint('busca por Bluetooth indisponível: $e');
      }
    }
    _mergeOffers();
  }

  void _mergeOffers() {
    final lan = ref.read(connectProvider.notifier).jamOffers.value;
    final offers = <JamOffer>[
      for (final o in lan)
        JamOffer(key: 'wifi:${o.deviceId}', hostName: o.name, via: 'wifi', join: (id, name) => joinLan(o, id, name)),
      ..._nearbyOffers,
    ];
    state = state.copyWith(offers: offers);
  }

  void _stopSearch() {
    final l = _lanListener;
    if (l != null) {
      try {
        ref.read(connectProvider.notifier).jamOffers.removeListener(l);
      } catch (_) {}
    }
    _nearbySub?.cancel();
    _nearbySub = null;
    jamNearby?.stopDiscovery();
  }

  Future<void> join(JamOffer offer) async {
    state = state.copyWith(phase: JamPhase.waiting, hostName: offer.hostName);
    try {
      final link = await offer.join(_myId(ref), await _myName(ref));
      _stopSearch();
      _link = link;
      state = state.copyWith(phase: JamPhase.joined);
      link.messages.listen(_onHost, onDone: () {
        if (_link == link) {
          _link = null;
          state = state.copyWith(phase: JamPhase.ended);
        }
      });
    } on JamRejected {
      state = state.copyWith(phase: JamPhase.rejected);
    } catch (_) {
      state = state.copyWith(phase: JamPhase.rejected);
    }
  }

  Future<void> leave() async {
    final l = _link;
    _link = null;
    l?.send({'t': 'bye'});
    await l?.close();
    state = const JamGuestState();
  }

  void reset() => state = JamGuestState(offers: state.offers);

  void _onHost(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'welcome':
        state = state.copyWith(hostName: m['n'] as String?);
      case 'state':
        state = state.copyWith(
          playing: m['playing'] == true,
          position: Duration(milliseconds: (m['pos'] as num?)?.toInt() ?? 0),
          duration: Duration(milliseconds: (m['dur'] as num?)?.toInt() ?? 0),
          current: m['cur'] is Map ? Map<String, dynamic>.from(m['cur'] as Map) : null,
          clearCurrent: m['cur'] == null,
          next: [for (final e in (m['next'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)],
        );
      case 'results':
        final c = _results.remove(m['req']);
        c?.complete([
          for (final e in (m['songs'] as List? ?? const [])) if (e is Map) Song.fromJson(Map<String, dynamic>.from(e)),
        ]);
      case 'accept':
        _accepts.remove(m['fid'])?.complete();
      case 'queued':
        final t = Map.of(state.transfers);
        final cur = t[m['fid']];
        if (cur != null) t[m['fid'] as String] = JamTransfer(title: cur.title, progress: 1, done: true);
        state = state.copyWith(transfers: t);
      case 'cover':
        final id = m['id'], b64 = m['b64'];
        if (id is String && b64 is String) {
          covers[id] = base64Decode(b64);
          _coverWaiting.remove(id);
          coverVersion.value++;
        }
      case 'bye':
        _link?.close();
    }
  }

  /// Capa de uma música do dono (pede na primeira vez).
  Uint8List? cover(String? id) {
    if (id == null) return null;
    final c = covers[id];
    if (c == null && _coverWaiting.add(id)) _link?.send({'t': 'cover', 'id': id});
    return c;
  }

  Future<List<Song>> searchHost(String q) async {
    final l = _link;
    if (l == null) return const [];
    final id = ++_req;
    final c = Completer<List<Song>>();
    _results[id] = c;
    l.send({'t': 'search', 'req': id, 'q': q});
    return c.future.timeout(const Duration(seconds: 20), onTimeout: () => const []);
  }

  void addFromHost(Song song) => _link?.send({'t': 'add', 'songs': [song.toJson()]});

  void control(String c, {int? ms}) => _link?.send({'t': 'cmd', 'c': c, 'ms': ?ms});

  /// Manda uma música daqui para a Jam: arquivo do aparelho ou baixada do
  /// servidor deste convidado.
  Future<void> sendSong(Song song) async {
    final l = _link;
    if (l == null) return;
    final fid = _randomId(16);
    void progress(double v, {String? error}) {
      state = state.copyWith(transfers: {...state.transfers, fid: JamTransfer(title: song.title, progress: v, error: error)});
    }

    progress(0);
    String? tmp;
    try {
      var path = song.path;
      var suffix = song.suffix ?? 'mp3';
      if (path == null) {
        // Do servidor deste convidado: MP3 320 (o arquivo original pode ser enorme).
        final provider = ref.read(musicProvider);
        final url = provider.streamUri(song, format: 'mp3', maxBitRate: 320);
        tmp = p.join(ref.read(cacheDirProvider).path, 'jam_out_$fid.mp3');
        await _download(url, tmp, (v) => progress(v * 0.4));
        path = tmp;
        suffix = 'mp3';
      }
      Uint8List? cover;
      final c = song.coverArt;
      if (c != null) {
        try {
          final bytes = isFileCover(c)
              ? await File(c).readAsBytes()
              : await _ownCover(c);
          if (bytes != null) cover = bytes.length <= 40 * 1024 ? bytes : await _thumb(bytes);
        } catch (_) {}
      }
      final accepted = Completer<void>();
      _accepts[fid] = accepted;
      l.send({
        't': 'offer',
        'fid': fid,
        'size': await File(path).length(),
        'song': {...song.toJson()..remove('path')..remove('coverArt')..remove('id'), 'suffix': suffix},
        if (cover != null) 'cover': base64Encode(cover),
      });
      await accepted.future.timeout(const Duration(seconds: 30));
      final base = tmp == null ? 0.0 : 0.4;
      await l.sendFile(path, fid, onProgress: (v) => progress(base + v * (0.99 - base)));
    } catch (e) {
      progress(0, error: '$e');
    } finally {
      if (tmp != null) {
        try {
          await File(tmp).delete();
        } catch (_) {}
      }
    }
  }

  Future<Uint8List?> _ownCover(String id) async {
    final provider = ref.read(musicProvider);
    final uri = provider.coverUri(id, size: 150);
    final key = provider.coverCacheKey(id, size: 150);
    if (uri == null || key == null) return null;
    final dir = p.join(ref.read(cacheDirProvider).path, 'ui_covers');
    return (await CoverImageProvider.fetchFile(url: uri.toString(), cacheKey: key, cacheDir: dir)).readAsBytes();
  }

  static Future<void> _download(Uri url, String out, void Function(double) onProgress) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(url)).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      final sink = File(out).openWrite();
      await for (final chunk in res) {
        got += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }
}

final jamGuestProvider = NotifierProvider<JamGuestNotifier, JamGuestState>(JamGuestNotifier.new);

