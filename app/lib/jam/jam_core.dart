import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../connect/connect_auth.dart';
import '../connect/connect_service.dart';
import 'jam_bonjour.dart';
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
  JamJoinRequest({required this.guestId, required this.guestName, required this.via, this.pass}) : key = _randomId(10);
  final String key;
  final String guestId;
  final String guestName;
  final String via;

  /// Passe que o dono deu a este convidado ao pô-lo em "aceitar sempre". O id
  /// sozinho não basta: ele aparece nos anúncios da rede.
  final String? pass;
  final decision = Completer<bool>();
  final at = DateTime.now();
}

/// Jam encontrada por perto (lado do convidado).
class JamOffer {
  const JamOffer({required this.key, required this.hostId, required this.hostName, required this.via, required this.join});
  final String key;
  final String hostId;
  final String hostName;
  final String via;

  /// [pass]: o passe que este dono deu para entrar sem pedir (se houver).
  final Future<JamLink> Function(String myId, String myName, String? pass) join;
}

/// Limites do que um convidado manda: tamanho de cada música, total da Festa
/// e ofertas esperando o arquivo.
const jamMaxUpload = 200 * 1024 * 1024;
const jamMaxTotal = 2 * 1024 * 1024 * 1024;
const _jamMaxPendingOffers = 20;
const _jamMaxCoverB64 = 700 * 1024;

/// Versão do protocolo da Festa que este app fala. A 2 trouxe play/pause,
/// pular para uma música da fila, "no fim da fila", músicas pelo id ('want')
/// e capa grande. O dono manda a dele na entrada; dono antigo não manda nada.
const jamProtocol = 2;

/// Até quantas músicas um "tocar" do convidado manda de uma vez.
const jamMaxSongsPerAdd = 50;

/// Músicas do dono vistas pelo convidado: o id leva este prefixo, para o
/// player daqui não confundir com as da própria biblioteca.
const jamHostPrefix = 'jamhost:';

/// Bytes de uma imagem de verdade (JPEG, PNG, GIF, WebP, BMP)? Capa de arquivo
/// só sai do aparelho se for imagem.
bool looksLikeImage(List<int> b) {
  bool at(int i, List<int> sig) {
    if (b.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (b[i + k] != sig[k]) return false;
    }
    return true;
  }

  return at(0, [0xFF, 0xD8, 0xFF]) ||
      at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) ||
      at(0, 'GIF8'.codeUnits) ||
      (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) ||
      at(0, 'BM'.codeUnits);
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

/// Bluetooth sem o Google Play Services (Android; null no desktop). Só liga
/// com a chave da tela da Festa ([jamBluetoothModeProvider]).
JamTransport? jamBluetooth;

/// Passe guardado para entrar direto na Festa deste dono (id do dono → passe).
String? Function(String hostId)? jamPassFor;

/// Chave "Bluetooth sem Google Play Services" da tela da Festa. Não fica
/// guardada: o app sempre abre com ela desligada.
class JamBluetoothMode extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool on) => state = on;
}

final jamBluetoothModeProvider = NotifierProvider<JamBluetoothMode, bool>(JamBluetoothMode.new);

/// Avisos do sistema para pedidos de entrada (Android: notificação com
/// Aceitar/Recusar/Sempre). A decisão volta por [jamDecisionSink].
void Function(JamJoinRequest req)? jamShowRequest;
void Function(JamJoinRequest req)? jamHideRequest;
void Function(String key, String what)? jamDecisionSink;

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

  /// Lado do dono: arquivos oferecidos e aceitos (id → tamanho anunciado).
  /// Upload sem oferta é recusado.
  final expectedUploads = <String, int>{};

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
/// Lê "192.168.1.10", "192.168.1.10:47802" ou "ws://192.168.1.10:47802".
///
/// Devolve null se não der para entender. Sem porta, usa a padrão da Jam.
LanJamOffer? offerFromText(String texto, {required int portaPadrao}) {
  var s = texto.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^(ws|wss|http|https)://'), '').split('/').first;
  final partes = s.split(':');
  final host = partes.first.trim();
  if (host.isEmpty) return null;
  final porta = partes.length > 1 ? int.tryParse(partes[1].trim()) : portaPadrao;
  if (porta == null || porta < 1 || porta > 65535) return null;
  return LanJamOffer.byAddress(host, porta);
}

Future<JamLink> joinLan(LanJamOffer offer, String myId, String myName, String? pass) async {
  // Pelo Uri: um endereço IPv6 precisa dos colchetes.
  final url = Uri(scheme: 'ws', host: offer.host, port: offer.port, path: '/jam');
  final ws = await WebSocket.connect(url.toString()).timeout(const Duration(seconds: 6));
  ws.pingInterval = const Duration(seconds: 8);
  ws.add(jsonEncode({'t': 'hello', 'id': myId, 'n': myName, 'k': ?pass}));
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
  const JamAllowed(this.id, this.name, [this.pass]);
  final String id;
  final String name;

  /// Passe entregue ao convidado (null = entrada antiga, de antes do passe:
  /// o dono confirma uma vez e o passe é entregue).
  final String? pass;
}

class JamAllowlistNotifier extends Notifier<List<JamAllowed>> {
  static const _key = 'jamAllowlist';

  @override
  List<JamAllowed> build() {
    final raw = ref.watch(prefsProvider).getStringList(_key) ?? const [];
    return [
      for (final e in raw)
        if (jsonDecode(e) case {'id': final String id, 'n': final String n} && final m) JamAllowed(id, n, m['k'] is String ? m['k'] as String : null),
    ];
  }

  /// Entra sem pedir: está na lista e mostrou o passe que recebeu.
  bool allows(String id, String? pass) =>
      pass != null && state.any((a) => a.id == id && a.pass != null && sameDigest(a.pass!, pass));

  bool contains(String id) => state.any((a) => a.id == id);

  /// Põe (ou mantém) na lista e devolve o passe a entregar ao convidado.
  String add(String id, String name) {
    final pass = _randomId(24);
    state = [...state.where((a) => a.id != id), JamAllowed(id, name, pass)];
    _save();
    return pass;
  }

  void remove(String id) {
    state = state.where((a) => a.id != id).toList();
    _save();
  }

  void _save() =>
      ref.read(prefsProvider).setStringList(_key, [for (final a in state) jsonEncode({'id': a.id, 'n': a.name, 'k': ?a.pass})]);
}

final jamAllowlistProvider = NotifierProvider<JamAllowlistNotifier, List<JamAllowed>>(JamAllowlistNotifier.new);

String _myId(Ref ref) => deviceIdFor(ref.read(prefsProvider));

Future<String> _myName(Ref ref) async {
  final custom = ref.read(settingsProvider).deviceName;
  return (custom == null || custom.trim().isEmpty) ? await systemDeviceName() : custom.trim();
}

/// Capa reduzida (para mandar pela Jam): PNG de até [width] px.
Future<Uint8List?> _thumb(Uint8List bytes, {int width = 160}) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
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
  final _bonjour = JamBonjour();
  String _name = '';
  final _tokens = <String, _LanLink>{};
  final _addedBy = <String, String>{};

  /// Músicas daqui mostradas aos convidados (id → música com o arquivo, se
  /// local): o "adicionar" usa estas, nunca o que o convidado manda de volta.
  final _shown = <String, Song>{};

  /// Passes a entregar na entrada (id do convidado → passe).
  final _passToSend = <String, String>{};

  /// Bytes aceitos de convidados nesta Festa (cota: [jamMaxTotal]).
  int _jamBytes = 0;
  Timer? _announce;
  Timer? _statePush;
  bool _pushQueued = false;

  @override
  JamHostState build() {
    ref.listen(playerProvider, (_, _) => _schedulePush());
    // Botões da notificação do pedido (app em segundo plano).
    jamDecisionSink = (key, what) {
      final req = state.pending.where((r) => r.key == key).firstOrNull;
      if (req != null) respond(req, accept: what != 'reject', always: what == 'always');
    };
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
    // Músicas que convidados mandaram numa Festa anterior não ficam guardadas.
    await clearJamFiles(ref.read(cacheDirProvider).path);
    _jamBytes = 0;
    _passToSend.clear();
    await _dir.create(recursive: true);
    final connect = ref.read(connectProvider.notifier);
    connect.jamRoutes = this;
    await connect.announceJam();
    _announce = Timer.periodic(const Duration(seconds: 5), (_) => connect.announceJam());
    // Bonjour em paralelo ao broadcast: é o que o iPhone aceita, atravessa
    // Wi-Fi que filtra broadcast, e continua de pé quando o Android manda o
    // app para segundo plano (quem responde é o sistema).
    unawaited(_bonjour.advertise(
      deviceId: _myId(ref),
      jamId: id,
      name: _name,
      port: connect.jamPort,
    ));
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
    if (ref.read(jamBluetoothModeProvider)) await setBluetooth(true);
  }

  /// Liga/desliga a Festa por Bluetooth sem Play Services. Devolve false se
  /// não deu para ligar (Bluetooth desligado, sem permissão).
  Future<bool> setBluetooth(bool on) async {
    final bt = jamBluetooth;
    if (bt == null) return false;
    if (!on || !state.active) {
      await bt.stopHosting();
      return true;
    }
    try {
      await bt.startHosting(hostName: _name, hostId: _myId(ref), jamId: jamId, onRequest: _decide, onJoined: _attach);
      return true;
    } catch (e) {
      debugPrint('Festa por Bluetooth (sem Play Services) não abriu: $e');
      return false;
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
    unawaited(_bonjour.stopAdvertising());
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
    jamBluetooth?.stopHosting();
  }

  /// Decide um pedido: aceito automaticamente se a pessoa está na lista;
  /// senão espera o dono (acceptRequest/rejectRequest).
  Future<bool> _decide(JamJoinRequest req) {
    if (ref.read(jamAllowlistProvider.notifier).allows(req.guestId, req.pass)) {
      req.decision.complete(true);
      return req.decision.future;
    }
    state = state.copyWith(pending: [...state.pending, req]);
    jamShowRequest?.call(req);
    // Sem resposta em 2 minutos: recusa.
    Timer(const Duration(minutes: 2), () {
      if (!req.decision.isCompleted) respond(req, accept: false);
    });
    return req.decision.future;
  }

  void respond(JamJoinRequest req, {required bool accept, bool always = false}) {
    final allowlist = ref.read(jamAllowlistProvider.notifier);
    // "Sempre" (ou entrada antiga da lista, sem passe): o convidado recebe um
    // passe novo na entrada e, com ele, entra direto da próxima vez.
    if (accept && (always || allowlist.contains(req.guestId))) _passToSend[req.guestId] = allowlist.add(req.guestId, req.guestName);
    state = state.copyWith(pending: state.pending.where((r) => r != req).toList());
    jamHideRequest?.call(req);
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
    final req = JamJoinRequest(
      guestId: m['id'] as String,
      guestName: m['n'] is String ? m['n'] as String : remoteIp,
      via: 'wifi',
      pass: m['k'] is String ? m['k'] as String : null,
    );
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
    link.send({'t': 'welcome', 'n': _name, 'jid': jamId, 'token': token, 'v': jamProtocol, 'k': ?_passToSend.remove(req.guestId)});
    _attach(link);
  }

  @override
  Future<void> handleUpload(HttpRequest req) async {
    final link = _tokens[req.uri.queryParameters['t']];
    final fid = req.uri.queryParameters['f'];
    // Só o arquivo que o convidado ofereceu e o dono aceitou, até o tamanho anunciado.
    final expected = fid == null ? null : link?.expectedUploads.remove(fid);
    if (link == null || fid == null || expected == null || !RegExp(r'^[a-z0-9]{6,32}$').hasMatch(fid)) {
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
        if (size > expected) throw const FileSystemException('maior do que o anunciado');
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
    if (link.via != 'wifi') link.send({'t': 'welcome', 'n': _name, 'jid': jamId, 'v': jamProtocol, 'k': ?_passToSend.remove(link.peerId)});
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
      case 'want':
        // O convidado pergunta quais músicas dele este aparelho já tem (mesmo
        // servidor): essas vão pelo id, sem mandar o arquivo.
        final ids = [for (final e in (m['ids'] as List? ?? const []).take(jamMaxSongsPerAdd)) if (e is String) e];
        final local = ref.read(sessionProvider).value?.isLocal ?? true;
        var found = const <Song>[];
        if (!local && ids.isNotEmpty) {
          try {
            found = await ref.read(musicProvider).songsByIds(ids);
          } catch (_) {}
        }
        if (_shown.length > 3000) _shown.clear();
        for (final s in found) {
          _shown[s.id] = s;
        }
        pa.link.send({'t': 'have', 'req': m['req'], 'ids': [for (final s in found) s.id]});
      case 'add':
        final local = ref.read(sessionProvider).value?.isLocal ?? false;
        final queue = ref.read(playerProvider).queue;
        final songs = <Song>[];
        for (final e in (m['songs'] as List? ?? const [])) {
          if (e is! Map) continue;
          final known = _shown[e['id']] ?? queue.where((q) => q.song.id == e['id']).firstOrNull?.song;
          if (known != null) {
            songs.add(known);
          } else if (!local && e['id'] is String) {
            // Do servidor: a música é identificada pelo id. Nada de caminho de
            // arquivo daqui (nem como capa: a capa sairia para os convidados).
            final j = Map<String, dynamic>.from(e)..remove('path');
            if (j['coverArt'] is! String || isFileCover(j['coverArt'] as String)) j.remove('coverArt');
            try {
              songs.add(Song.fromJson(j));
            } catch (_) {}
          }
        }
        final uids = player.jamInsert(songs, atEnd: m['end'] == true);
        for (final u in uids) {
          _addedBy[u] = pa.name;
        }
      case 'cmd':
        switch (m['c']) {
          case 'toggle':
            player.toggle();
          case 'play':
            player.play();
          case 'pause':
            player.pause();
          case 'jump':
            if (m['u'] is String) player.jumpToUid(m['u'] as String);
          case 'next':
            player.next();
          case 'previous':
            player.previous();
          case 'seek':
            player.seek(Duration(milliseconds: (m['ms'] as num?)?.toInt() ?? 0));
        }
      case 'offer':
        final fid = m['fid'], size = m['size'];
        if (fid is! String || !RegExp(r'^[a-z0-9]{6,32}$').hasMatch(fid)) return;
        if (size is! int || size <= 0 || size > jamMaxUpload || offers.length >= _jamMaxPendingOffers) return;
        if (_jamBytes + size > jamMaxTotal) return;
        if (m['cover'] is String && (m['cover'] as String).length > _jamMaxCoverB64) m.remove('cover');
        offers[fid] = m;
        _jamBytes += size;
        if (pa.link case final _LanLink l) l.expectedUploads[fid] = size;
        pa.link.send({'t': 'accept', 'fid': fid});
      case 'cover':
        final id = m['id'];
        // Só capa de música que este aparelho mostrou (fila ou buscas): o id
        // pode ser um caminho de arquivo, e o convidado não escolhe qual.
        if (id is! String || !_coverShared(id)) return;
        final big = m['big'] == true;
        final bytes = await _coverBytes(id, big: big);
        if (bytes != null) pa.link.send({'t': 'cover', 'id': id, 'big': big, 'b64': base64Encode(bytes)});
      case 'bye':
        await pa.link.close();
    }
  }

  Future<void> _fileReceived(JamParticipant pa, Map<String, dynamic>? offer, String fid, String path) async {
    if (offer == null || await File(path).length() > jamMaxUpload) {
      try {
        await File(path).delete();
      } catch (_) {}
      return;
    }
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
    final uids = ref.read(playerProvider.notifier).jamInsert([song], atEnd: offer['end'] == true);
    for (final u in uids) {
      _addedBy[u] = pa.name;
    }
    pa.link.send({'t': 'queued', 'fid': fid, 'title': song.title});
  }

  /// Capa de uma música que os convidados já viram (fila ou resultados de busca).
  bool _coverShared(String id) =>
      _shown.values.any((s) => s.coverArt == id) || ref.read(playerProvider).queue.any((q) => q.song.coverArt == id);

  /// Capa para mandar a um convidado: miniatura para listas ou, com [big], a
  /// da tela cheia (até ~120 KB, para não segurar o Bluetooth).
  Future<Uint8List?> _coverBytes(String id, {bool big = false}) async {
    final size = big ? 600 : 150;
    final limit = big ? 120 * 1024 : 40 * 1024;
    try {
      Uint8List bytes;
      if (isFileCover(id)) {
        bytes = await File(id).readAsBytes();
        if (!looksLikeImage(bytes)) return null;
      } else {
        final provider = ref.read(musicProvider);
        final uri = provider.coverUri(id, size: size);
        final key = provider.coverCacheKey(id, size: size);
        if (uri == null || key == null) return null;
        final dir = p.join(ref.read(cacheDirProvider).path, 'ui_covers');
        bytes = await (await CoverImageProvider.fetchFile(url: uri.toString(), cacheKey: key, cacheDir: dir)).readAsBytes();
      }
      if (bytes.length <= limit) return bytes;
      // A reduzida sai em PNG, que numa foto pesa mais que o JPEG do
      // servidor: grande demais, o convidado fica com a miniatura.
      final t = await _thumb(bytes, width: big ? 320 : 160);
      return big && t != null && t.length > 300 * 1024 ? null : t;
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
  const JamTransfer({required this.title, required this.progress, this.done = false, this.waiting = false, this.error});
  final String title;
  final double progress;
  final bool done;

  /// Na fila de envio, esperando as anteriores (vão uma por vez).
  final bool waiting;
  final String? error;
}

class JamGuestState {
  const JamGuestState({
    this.phase = JamPhase.idle,
    this.offers = const [],
    this.hostName,
    this.hostVersion = 1,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.current,
    this.next = const [],
    this.transfers = const {},
    this.bluetooth = JamBluetooth.ok,
    this.plainBtFailed = false,
    this.sentTick = 0,
    this.sentCount = 0,
  });
  final JamPhase phase;
  final List<JamOffer> offers;
  final String? hostName;

  /// Versão do protocolo do dono ([jamProtocol]); 1 = app antigo.
  final int hostVersion;
  final bool playing;
  final Duration position;
  final Duration duration;

  /// Tocando no dono (JSON da música + 'uid' e 'by').
  final Map<String, dynamic>? current;
  final List<Map<String, dynamic>> next;

  /// Músicas sendo mandadas daqui (id → progresso).
  final Map<String, JamTransfer> transfers;

  /// Se a busca por Bluetooth está de pé (para avisar quando não está).
  final JamBluetooth bluetooth;

  /// A busca por Bluetooth sem Play Services não começou.
  final bool plainBtFailed;

  /// Músicas mandadas para a Festa pelo player: o contador muda a cada envio
  /// (o shell avisa), [sentCount] é quantas foram.
  final int sentTick;
  final int sentCount;

  /// Quem pediu cada música da fila do dono (uid → nome).
  Map<String, String> get addedBy => {
        for (final e in [?current, ...next])
          if (e['uid'] is String && e['by'] is String) e['uid'] as String: e['by'] as String,
      };

  JamGuestState copyWith({
    JamPhase? phase,
    List<JamOffer>? offers,
    String? hostName,
    int? hostVersion,
    bool? playing,
    Duration? position,
    Duration? duration,
    Map<String, dynamic>? current,
    bool clearCurrent = false,
    List<Map<String, dynamic>>? next,
    Map<String, JamTransfer>? transfers,
    JamBluetooth? bluetooth,
    bool? plainBtFailed,
    int? sentTick,
    int? sentCount,
  }) =>
      JamGuestState(
        phase: phase ?? this.phase,
        offers: offers ?? this.offers,
        hostName: hostName ?? this.hostName,
        hostVersion: hostVersion ?? this.hostVersion,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        current: clearCurrent ? null : (current ?? this.current),
        next: next ?? this.next,
        transfers: transfers ?? this.transfers,
        bluetooth: bluetooth ?? this.bluetooth,
        plainBtFailed: plainBtFailed ?? this.plainBtFailed,
        sentTick: sentTick ?? this.sentTick,
        sentCount: sentCount ?? this.sentCount,
      );
}

/// Estado da busca por Bluetooth do convidado.
enum JamBluetooth {
  ok,

  /// Sem Google Play Services (LineageOS, Huawei…): só dá pelo Wi-Fi.
  unavailable,

  /// A busca não começou: Bluetooth/localização desligados ou sem permissão.
  failed,
}

class JamGuestNotifier extends Notifier<JamGuestState> implements JamRemote {
  JamLink? _link;
  StreamSubscription<List<JamOffer>>? _nearbySub;
  StreamSubscription<List<JamOffer>>? _btSub;
  List<JamOffer> _btOffers = const [];
  final _bonjour = JamBonjour();
  List<LanJamOffer> _bonjourOffers = const [];
  List<JamOffer> _nearbyOffers = const [];
  VoidCallback? _lanListener;
  int _req = 0;
  final _results = <int, Completer<List<Song>>>{};
  final _wants = <int, Completer<Set<String>>>{};
  final _accepts = <String, Completer<void>>{};

  /// Capas pedidas ao dono, guardadas em arquivo (id → caminho): assim a capa
  /// do player, da notificação e do tema sai pelo caminho de sempre.
  final _covers = <String, String>{};
  final _bigCovers = <String, String>{};
  final _coverWaiting = <String>{};
  final coverVersion = ValueNotifier(0);
  String _coversDir = '';

  /// Último estado mandado pelo dono, e as entradas da fila já montadas
  /// (uid → entrada): reaproveitar a mesma entrada evita que a tela ache que
  /// a música mudou a cada aviso do dono (a letra, por exemplo, recarregava).
  Map<String, dynamic>? _lastState;
  final _mirrored = <String, (String?, QueueItem)>{};

  /// Músicas esperando a vez de ir como arquivo (id do envio, música, no fim).
  final _toSend = <(String, Song, bool)>[];
  bool _sending = false;

  @override
  JamGuestState build() {
    jamPassFor = (hostId) => _passes()[hostId];
    ref.onDispose(() {
      _stopSearch();
      // Sem o link antes de fechar: o fim da conexão não mexe mais em nada.
      final l = _link;
      _link = null;
      l?.close();
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
    unawaited(_bonjour.discover((l) {
      _bonjourOffers = l;
      _mergeOffers();
    }));
    final nearby = jamNearby;
    if (nearby == null || !nearby.available) {
      if (Platform.isAndroid) state = state.copyWith(bluetooth: JamBluetooth.unavailable);
    } else if (_nearbySub == null) {
      state = state.copyWith(bluetooth: JamBluetooth.ok);
      try {
        _nearbySub = nearby
            .discover(myId: _myId(ref), myName: await _myName(ref))
            .listen(
              (o) {
                _nearbyOffers = o;
                _mergeOffers();
              },
              onError: (Object e) {
                // Sem isto a busca morta ficava "de pé" e o atualizar não tentava de novo.
                debugPrint('busca por Bluetooth falhou: $e');
                _nearbySub?.cancel();
                _nearbySub = null;
                state = state.copyWith(bluetooth: JamBluetooth.failed);
              },
            );
      } catch (e) {
        debugPrint('busca por Bluetooth indisponível: $e');
        state = state.copyWith(bluetooth: JamBluetooth.failed);
      }
    }
    if (ref.read(jamBluetoothModeProvider)) await setBluetooth(true);
    _mergeOffers();
  }

  /// Liga/desliga a busca por Bluetooth sem Play Services.
  Future<void> setBluetooth(bool on) async {
    final bt = jamBluetooth;
    if (bt == null) return;
    if (!on) {
      await _btSub?.cancel();
      _btSub = null;
      _btOffers = const [];
      await bt.stopDiscovery();
      state = state.copyWith(plainBtFailed: false);
      _mergeOffers();
      return;
    }
    if (_btSub != null) return;
    state = state.copyWith(plainBtFailed: false);
    _btSub = bt
        .discover(myId: _myId(ref), myName: await _myName(ref))
        .listen(
          (o) {
            _btOffers = o;
            _mergeOffers();
          },
          onError: (Object e) {
            debugPrint('busca por Bluetooth (sem Play Services) falhou: $e');
            _btSub?.cancel();
            _btSub = null;
            state = state.copyWith(plainBtFailed: true);
          },
        );
  }

  void _mergeOffers() {
    // As duas descobertas podem achar a mesma Festa; vale uma vez só, e a do
    // anúncio na rede, cujo endereço é o de onde ele veio de fato.
    final porId = <String, LanJamOffer>{
      for (final o in _bonjourOffers) o.deviceId: o,
      for (final o in ref.read(connectProvider.notifier).jamOffers.value) o.deviceId: o,
    };
    final lan = porId.values;
    final offers = <JamOffer>[
      for (final o in lan)
        JamOffer(key: 'wifi:${o.deviceId}', hostId: o.deviceId, hostName: o.name, via: 'wifi', join: (id, name, pass) => joinLan(o, id, name, pass)),
      ..._nearbyOffers,
      ..._btOffers,
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
    _btSub?.cancel();
    _btSub = null;
    _btOffers = const [];
    jamBluetooth?.stopDiscovery();
    unawaited(_bonjour.stopDiscovery());
    _bonjourOffers = const [];
  }

  static const _kPasses = 'jamPasses';

  Map<String, String> _passes() {
    try {
      final raw = ref.read(prefsProvider).getString(_kPasses);
      return raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  void _savePass(String hostId, String pass) {
    final all = _passes()..remove(hostId);
    final kept = Map.fromEntries([...all.entries].skip(all.length >= 50 ? all.length - 49 : 0));
    ref.read(prefsProvider).setString(_kPasses, jsonEncode({...kept, hostId: pass}));
  }

  /// Entrar numa Festa cujo endereço foi digitado.
  ///
  /// Devolve false quando o texto não dá para entender. O resto (senha,
  /// espera pelo dono aceitar) segue igual a entrar pela lista.
  Future<bool> joinByAddress(String texto) async {
    final lan = offerFromText(texto, portaPadrao: connectTcpPort);
    if (lan == null) return false;
    await join(JamOffer(
      key: 'wifi:${lan.deviceId}',
      hostId: lan.deviceId,
      hostName: lan.name,
      via: 'wifi',
      join: (id, name, pass) => joinLan(lan, id, name, pass),
    ));
    return true;
  }

  Future<void> join(JamOffer offer) async {
    state = state.copyWith(phase: JamPhase.waiting, hostName: offer.hostName);
    try {
      final link = await offer.join(_myId(ref), await _myName(ref), _passes()[offer.hostId]);
      _stopSearch();
      await _clearCovers();
      _link = link;
      // O player daqui passa a ser o da Festa antes de a fase mudar: quem
      // abre o player ao ver "entrou" (sem conta, a rota depende disso) já o
      // encontra pronto. As mensagens esperam na fila do link até lá.
      await ref.read(playerProvider.notifier).enterJam(this, state.hostName ?? offer.hostName);
      state = state.copyWith(phase: JamPhase.joined, hostVersion: 1);
      link.messages.listen(_onHost, onDone: () {
        if (_link == link) {
          _link = null;
          _ended();
          state = state.copyWith(phase: JamPhase.ended);
          _searchAgain();
        }
      });
    } on JamRejected {
      state = state.copyWith(phase: JamPhase.rejected);
      _searchAgain();
    } catch (_) {
      state = state.copyWith(phase: JamPhase.rejected);
      _searchAgain();
    }
  }

  /// Depois de cair, sair ou ser recusado a busca parou (o Bluetooth para o
  /// scan para conectar): recomeça, senão a lista fica velha.
  void _searchAgain() {
    _stopSearch();
    unawaited(search());
  }

  @override
  Future<void> leave() async {
    final l = _link;
    _link = null;
    l?.send({'t': 'bye'});
    await l?.close();
    _ended();
    state = const JamGuestState();
  }

  /// Fim da Festa deste lado: o player volta à fila daqui.
  void _ended() {
    ref.read(playerProvider.notifier).leaveJam();
    _lastState = null;
    _toSend.clear();
    unawaited(_clearCovers());
  }

  Future<void> _clearCovers() async {
    _covers.clear();
    _bigCovers.clear();
    _coverWaiting.clear();
    _mirrored.clear();
    final base = p.join(ref.read(cacheDirProvider).path, 'jam_guest');
    // Pasta nova a cada Festa: o cache de imagens da tela é pelo caminho, e
    // outro dono pode ter outra capa com o mesmo id.
    _coversDir = p.join(base, _randomId(8));
    try {
      final d = Directory(base);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  void _onHost(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'welcome':
        state = state.copyWith(hostName: m['n'] as String?, hostVersion: (m['v'] as num?)?.toInt() ?? 1);
        final pass = m['k'], host = _link?.peerId;
        if (pass is String && host != null) _savePass(host, pass);
        _mirror();
      case 'state':
        _lastState = m;
        state = state.copyWith(
          playing: m['playing'] == true,
          position: Duration(milliseconds: (m['pos'] as num?)?.toInt() ?? 0),
          duration: Duration(milliseconds: (m['dur'] as num?)?.toInt() ?? 0),
          current: m['cur'] is Map ? Map<String, dynamic>.from(m['cur'] as Map) : null,
          clearCurrent: m['cur'] == null,
          next: [for (final e in (m['next'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)],
        );
        _mirror();
      case 'results':
        final c = _results.remove(m['req']);
        c?.complete([
          for (final e in (m['songs'] as List? ?? const [])) if (e is Map) Song.fromJson(Map<String, dynamic>.from(e)),
        ]);
      case 'have':
        _wants.remove(m['req'])?.complete({for (final e in (m['ids'] as List? ?? const [])) if (e is String) e});
      case 'accept':
        _accepts.remove(m['fid'])?.complete();
      case 'queued':
        final t = Map.of(state.transfers);
        final cur = t[m['fid']];
        if (cur != null) t[m['fid'] as String] = JamTransfer(title: cur.title, progress: 1, done: true);
        state = state.copyWith(transfers: t);
      case 'cover':
        final id = m['id'], b64 = m['b64'];
        if (id is String && b64 is String) unawaited(_saveCover(id, b64, big: m['big'] == true));
      case 'bye':
        _link?.close();
    }
  }

  /// O estado do dono vira o do player daqui: a atual e as próximas.
  void _mirror() {
    if (_link == null) return;
    final m = _lastState;
    final cur = m?['cur'] is Map ? Map<String, dynamic>.from(m!['cur'] as Map) : null;
    final items = <QueueItem>[];
    if (cur != null) {
      final next = [for (final e in (m!['next'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
      for (final (i, e) in [cur, ...next].indexed) {
        final item = _hostItem(e, '${e['uid'] ?? 'h$i'}', big: i == 0);
        if (item != null) items.add(item);
      }
    }
    final uids = {for (final q in items) q.uid};
    _mirrored.removeWhere((k, _) => !uids.contains(k));
    Duration ms(Object? v) => Duration(milliseconds: (v as num?)?.toInt() ?? 0);
    ref.read(playerProvider.notifier).jamMirror(
          host: state.hostName ?? '',
          queue: items,
          playing: m?['playing'] == true,
          position: ms(m?['pos']),
          duration: ms(m?['dur']),
        );
  }

  /// Entrada da fila para uma música do dono. O id ganha [jamHostPrefix] e
  /// some o que só vale na biblioteca de lá (álbum, artista, arquivo).
  QueueItem? _hostItem(Map<String, dynamic> e, String uid, {bool big = false}) {
    final id = e['id'];
    if (id is! String) return null;
    final cover = coverFile(e['coverArt'] is String ? e['coverArt'] as String : null, big: big);
    final old = _mirrored[uid];
    if (old != null && old.$1 == cover) return old.$2;
    final j = Map<String, dynamic>.from(e)
      ..remove('uid')
      ..remove('by')
      ..remove('albumId')
      ..remove('artistId')
      ..remove('path')
      ..remove('coverArt');
    j['id'] = '$jamHostPrefix$id';
    if (cover != null) j['coverArt'] = cover;
    try {
      final item = QueueItem(uid, Song.fromJson(j));
      _mirrored[uid] = (cover, item);
      return item;
    } catch (_) {
      return null;
    }
  }

  /// Arquivo da capa [id] do dono; pede na primeira vez. Com [big] (música
  /// atual), pede também a grande e usa a miniatura até ela chegar.
  String? coverFile(String? id, {bool big = false}) {
    if (id == null) return null;
    if (big && state.hostVersion >= 2) {
      final b = _bigCovers[id];
      if (b != null) return b;
      _askCover(id, big: true);
    }
    final small = _covers[id];
    if (small == null) _askCover(id);
    return small;
  }

  void _askCover(String id, {bool big = false}) {
    if (_coverWaiting.add('${big ? 'b' : 's'}|$id')) _link?.send({'t': 'cover', 'id': id, if (big) 'big': true});
  }

  Future<void> _saveCover(String id, String b64, {required bool big}) async {
    try {
      final bytes = base64Decode(b64);
      if (!looksLikeImage(bytes)) return;
      final dir = _coversDir;
      if (dir.isEmpty) return;
      await Directory(dir).create(recursive: true);
      final name = sha1.convert(utf8.encode(id)).toString().substring(0, 24);
      final f = File(p.join(dir, '$name${big ? '_b' : ''}.img'));
      await f.writeAsBytes(bytes);
      if (dir != _coversDir) return; // a Festa acabou enquanto gravava
      (big ? _bigCovers : _covers)[id] = f.path;
      coverVersion.value++;
      _mirror();
    } catch (_) {}
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

  void addFromHost(Song song, {bool atEnd = false}) =>
      _link?.send({'t': 'add', 'songs': [song.toJson()..remove('path')], if (atEnd) 'end': true});

  void control(String c, {int? ms, String? uid}) => _link?.send({'t': 'cmd', 'c': c, 'ms': ?ms, 'u': ?uid});

  /// Comandos do player daqui (barra, tela cheia, notificação, páginas) indo
  /// para o dono. Só vai o que um convidado pode fazer: o resto (volume,
  /// aleatório, repetir, mexer na fila dos outros) a tela nem mostra.
  @override
  void command(String c, Map<String, dynamic> args) {
    final v2 = state.hostVersion >= 2;
    switch (c) {
      case 'toggle' || 'next' || 'previous':
        control(c);
      case 'play' || 'pause':
        if (v2) {
          control(c);
        } else if (state.playing != (c == 'play')) {
          control('toggle');
        }
      case 'seek':
        control('seek', ms: (args['ms'] as num?)?.toInt());
      case 'jump':
        final q = ref.read(playerProvider).queue;
        final i = args['i'];
        if (v2 && i is int && i >= 0 && i < q.length) control('jump', uid: q[i].uid);
      case 'playSongs':
        var songs = _songsArg(args);
        final start = (args['start'] as num?)?.toInt() ?? 0;
        if (start > 0 && start < songs.length) songs = songs.sublist(start);
        if (args['shuffle'] == true) songs.shuffle();
        unawaited(addSongs(songs));
      case 'playNext':
        unawaited(addSongs(_songsArg(args)));
      case 'enqueue':
        unawaited(addSongs(_songsArg(args), atEnd: true));
    }
  }

  static List<Song> _songsArg(Map<String, dynamic> args) => [
        for (final e in (args['songs'] as List? ?? const []))
          if (e is Map) ?_tryParse(e),
      ];

  static Song? _tryParse(Map e) {
    try {
      return Song.fromJson(Map<String, dynamic>.from(e));
    } catch (_) {
      return null;
    }
  }

  /// Músicas daqui para a Festa, na ordem. "Tocar" e "tocar a seguir" entram
  /// como próximas (não cortam a música de ninguém); [atEnd], no fim da fila.
  ///
  /// As que o dono já tem — as dele mesmo ou, no mesmo servidor, as daqui —
  /// vão pelo id, na hora. As outras vão como arquivo, uma por vez: todas
  /// juntas engasgavam o Bluetooth.
  Future<void> addSongs(List<Song> songs, {bool atEnd = false}) async {
    final l = _link;
    if (l == null || songs.isEmpty) return;
    songs = songs.take(jamMaxSongsPerAdd).toList();
    state = state.copyWith(sentTick: state.sentTick + 1, sentCount: songs.length);
    final session = ref.read(sessionProvider).value;
    final mine = [for (final s in songs) if (!s.id.startsWith(jamHostPrefix)) s.id];
    final have = mine.isNotEmpty && state.hostVersion >= 2 && session != null && !session.isLocal
        ? await _askHave(mine)
        : const <String>{};
    final byId = <Map<String, dynamic>>[];
    final files = <Song>[];
    for (final s in songs) {
      if (s.id.startsWith(jamHostPrefix)) {
        byId.add({...s.toJson()..remove('path')..remove('coverArt'), 'id': s.id.substring(jamHostPrefix.length)});
      } else if (have.contains(s.id)) {
        byId.add(s.toJson()..remove('path')..remove('coverArt'));
      } else {
        files.add(s);
      }
    }
    if (byId.isNotEmpty) _link?.send({'t': 'add', 'songs': byId, if (atEnd) 'end': true});
    _queueFiles(files, atEnd);
  }

  /// Pergunta ao dono quais destas músicas ele já tem (mesmo servidor).
  Future<Set<String>> _askHave(List<String> ids) {
    final l = _link;
    if (l == null) return Future.value(const {});
    final id = ++_req;
    final c = Completer<Set<String>>();
    _wants[id] = c;
    l.send({'t': 'want', 'req': id, 'ids': ids});
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _wants.remove(id);
      return const <String>{};
    });
  }

  /// Manda uma música daqui para a Festa como arquivo: do aparelho ou baixada
  /// do servidor deste convidado.
  void sendSong(Song song, {bool atEnd = false}) => _queueFiles([song], atEnd);

  void _queueFiles(List<Song> songs, bool atEnd) {
    if (songs.isEmpty) return;
    // As que já entraram na fila do dono saem da lista.
    final t = Map.of(state.transfers)..removeWhere((_, x) => x.done);
    for (final s in songs) {
      final fid = _randomId(16);
      _toSend.add((fid, s, atEnd));
      t[fid] = JamTransfer(title: s.title, progress: 0, waiting: true);
    }
    state = state.copyWith(transfers: t);
    unawaited(_pumpFiles());
  }

  Future<void> _pumpFiles() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_toSend.isNotEmpty && _link != null) {
        final (fid, song, atEnd) = _toSend.removeAt(0);
        await _sendFile(song, fid, atEnd: atEnd);
      }
    } finally {
      _sending = false;
    }
  }

  /// Tira da lista um envio que deu erro (o convidado tocou nele).
  void dismissTransfer(String fid) => state = state.copyWith(transfers: Map.of(state.transfers)..remove(fid));

  Future<void> _sendFile(Song song, String fid, {required bool atEnd}) async {
    final l = _link;
    if (l == null) return;
    void progress(double v, {String? error}) {
      // O "queued" do dono pode chegar antes do último aviso de progresso
      // (Bluetooth): o que já foi confirmado não volta a ser progresso.
      if (state.transfers[fid]?.done == true) return;
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
        if (atEnd) 'end': true,
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

/// Apaga as músicas que convidados mandaram para tocar na Festa (ficam só
/// enquanto ela dura: não viram cópia no aparelho de quem recebeu).
Future<void> clearJamFiles(String cacheDir) async {
  // 'jam_guest': capas da Festa em que este aparelho entrou.
  for (final name in ['jam', 'jam_guest']) {
    try {
      final dir = Directory(p.join(cacheDir, name));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
