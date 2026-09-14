import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers.dart';
import '../data/settings.dart';
import '../domain/models.dart';
import '../player/player_controller.dart';

/// BKplayer Connect: escolher em qual aparelho tocar e controlá-lo (estilo
/// Spotify Connect), entre aparelhos logados na mesma conta.
///
/// - Descoberta: cada aparelho se anuncia na rede local por UDP a cada 15 s e
///   responde a buscas. O anúncio leva só id, nome, plataforma, porta e um hash
///   do usuário (para ignorar aparelhos de outras contas).
/// - Controle: WebSocket (TCP). Só entra quem apresenta credenciais que o
///   servidor deste aparelho aceita, ou seja, o login da mesma conta; daí recebe
///   o estado do player e manda comandos.
/// - Fora da rede local (ex.: pelo Tailscale), dá para adicionar pelo endereço.
const connectTcpPort = 47800;
const connectUdpPort = 47801;
const _deviceTtl = Duration(seconds: 50);

class ConnectDevice {
  const ConnectDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
    required this.seen,
    this.manual = false,
  });

  final String id;
  final String name;

  /// linux, windows, macos, android, ios.
  final String platform;
  final String host;
  final int port;
  final DateTime seen;

  /// Adicionado pelo endereço (fica na lista mesmo fora de alcance).
  final bool manual;

  bool get online => DateTime.now().difference(seen) < _deviceTtl;

  String get address => '$host:$port';

  ConnectDevice copyWith({String? name, String? platform, String? host, int? port, DateTime? seen, bool? manual}) =>
      ConnectDevice(
        id: id,
        name: name ?? this.name,
        platform: platform ?? this.platform,
        host: host ?? this.host,
        port: port ?? this.port,
        seen: seen ?? this.seen,
        manual: manual ?? this.manual,
      );
}

/// O que um aparelho está tocando (para a lista).
class DeviceStatus {
  const DeviceStatus({required this.playing, this.title, this.artist});
  final bool playing;
  final String? title;
  final String? artist;
  bool get hasTrack => title != null;
}

/// Este aparelho.
class ConnectInfo {
  const ConnectInfo({required this.id, required this.name, required this.platform});
  final String id;
  final String name;
  final String platform;
}

String _systemName = '';

/// Nome do aparelho no sistema ("Galaxy M35 5G", "thieggs-pc").
Future<String> systemDeviceName() async {
  if (_systemName.isNotEmpty) return _systemName;
  if (Platform.isAndroid) {
    // O canal é registrado pela activity, que pode ainda não ter se ligado ao motor.
    for (var i = 0; i < 5 && _systemName.isEmpty; i++) {
      try {
        _systemName = await const MethodChannel('bkplayer/system').invokeMethod<String>('deviceName') ?? '';
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (_systemName.isEmpty) _systemName = 'Android';
  } else {
    _systemName = Platform.localHostname;
  }
  return _systemName;
}

String _userHash(String username) =>
    sha256.convert(utf8.encode('bkplayer-connect|${username.trim().toLowerCase()}')).toString().substring(0, 16);

String _deviceId(SharedPreferences prefs) {
  var id = prefs.getString('connectDeviceId');
  if (id == null) {
    final rnd = Random.secure();
    id = List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
    prefs.setString('connectDeviceId', id);
  }
  return id;
}

/// Conexão de controle com outro aparelho (lado de quem controla).
class ConnectLink {
  ConnectLink._(this.device, this._ws) {
    _ws.listen(
      (data) {
        if (data is! String) return;
        try {
          final m = jsonDecode(data);
          if (m is Map) _messages.add(Map<String, dynamic>.from(m));
        } catch (_) {}
      },
      onDone: _messages.close,
      onError: (_) => _messages.close(),
      cancelOnError: true,
    );
  }

  final ConnectDevice device;
  final WebSocket _ws;
  // Guarda as mensagens até alguém ouvir: a fila e o estado chegam logo que
  // conecta, antes de o player assinar.
  final _messages = StreamController<Map<String, dynamic>>();

  /// Estado e fila do outro aparelho; fecha quando a conexão cai.
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  static Future<ConnectLink> open(ConnectDevice d, {required Map<String, String> auth, required ConnectInfo me}) async {
    final uri = Uri(
      scheme: 'ws',
      host: d.host,
      port: d.port,
      path: '/connect',
      queryParameters: {...auth, 'cid': me.id, 'cn': me.name},
    );
    final ws = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 6));
    ws.pingInterval = const Duration(seconds: 8);
    return ConnectLink._(d, ws);
  }

  void cmd(String c, [Map<String, dynamic> args = const {}]) {
    if (_ws.readyState == WebSocket.open) _ws.add(jsonEncode({'t': 'cmd', 'c': c, ...args}));
  }

  Future<void> close() async {
    try {
      await _ws.close();
    } catch (_) {}
  }
}

class _Controller {
  _Controller(this.ws, this.name);
  final WebSocket ws;
  final String name;
  void send(Map<String, dynamic> m) {
    if (ws.readyState == WebSocket.open) ws.add(jsonEncode(m));
  }
}

/// Aparelhos da mesma conta encontrados (e o servidor que deixa este ser controlado).
class ConnectNotifier extends Notifier<List<ConnectDevice>> {
  RawDatagramSocket? _udp; // porta fixa: anúncios e buscas por broadcast
  RawDatagramSocket? _udpQuery; // porta própria: respostas às nossas buscas
  HttpServer? _http;
  Timer? _timer;
  int _gen = 0;
  String _uh = '';
  String _username = '';
  ConnectInfo? _me;
  final _controllers = <_Controller>{};
  final _validated = <String, DateTime>{};
  final _failures = <String, List<DateTime>>{};
  int _queueVersion = 0;
  List<InternetAddress>? _broadcasts;
  DateTime _broadcastsAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _kManual = 'connectManualDevices';

  /// Este aparelho (disponível depois que o Connect liga).
  ConnectInfo? get me => _me;

  @override
  List<ConnectDevice> build() {
    final session = ref.watch(sessionProvider).value;
    final enabled = ref.watch(settingsProvider.select((s) => s.connectEnabled));
    final customName = ref.watch(settingsProvider.select((s) => s.deviceName));
    final gen = ++_gen;
    ref.onDispose(_stop);
    if (session == null || !enabled) return const [];
    _username = session.account.username;
    _uh = _userHash(_username);
    ref.listen(playerProvider, _pushState);
    Future.microtask(() => _start(gen, customName));
    return _manualDevices();
  }

  Future<void> _start(int gen, String? customName) async {
    final name = (customName == null || customName.trim().isEmpty) ? await systemDeviceName() : customName.trim();
    if (gen != _gen) return;
    _me = ConnectInfo(id: _deviceId(ref.read(prefsProvider)), name: name, platform: Platform.operatingSystem);
    try {
      HttpServer http;
      try {
        http = await HttpServer.bind(InternetAddress.anyIPv4, connectTcpPort);
      } on SocketException {
        // Outra instância no mesmo computador: qualquer porta livre (vai no anúncio).
        http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      RawDatagramSocket udp;
      try {
        udp = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          connectUdpPort,
          reuseAddress: true,
          reusePort: true,
        );
      } catch (_) {
        udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, connectUdpPort, reuseAddress: true);
      }
      final query = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (gen != _gen) {
        await http.close(force: true);
        udp.close();
        query.close();
        return;
      }
      _http = http;
      _udp = udp..broadcastEnabled = true;
      _udpQuery = query..broadcastEnabled = true;
      http.listen(_onRequest, onError: (_) {});
      udp.listen((e) => _onDatagram(udp, e), onError: (_) {});
      query.listen((e) => _onDatagram(query, e), onError: (_) {});
      await _announce();
      await refresh();
      _timer = Timer.periodic(const Duration(seconds: 15), (_) {
        _announce();
        _pollManual();
        _prune();
      });
    } catch (e) {
      debugPrint('Connect indisponível: $e');
    }
  }

  void _stop() {
    _gen++;
    _timer?.cancel();
    _timer = null;
    final udp = _udp;
    if (udp != null && _me != null) {
      _sendBroadcast(udp, {'t': 'b'});
    }
    udp?.close();
    _udpQuery?.close();
    _http?.close(force: true);
    _udp = null;
    _udpQuery = null;
    _http = null;
    for (final c in _controllers) {
      c.ws.close();
    }
    _controllers.clear();
  }

  // ---- Descoberta ----

  Map<String, dynamic> _announcement() => {
    'bk': 1,
    't': 'a',
    'id': _me!.id,
    'n': _me!.name,
    'p': _me!.platform,
    'port': _http?.port ?? connectTcpPort,
    'uh': _uh,
  };

  Future<List<InternetAddress>> _broadcastAddresses() async {
    if (_broadcasts != null && DateTime.now().difference(_broadcastsAt) < const Duration(minutes: 1)) {
      return _broadcasts!;
    }
    final out = <InternetAddress>[InternetAddress('255.255.255.255')];
    try {
      for (final nic in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in nic.addresses) {
          final b = a.rawAddress;
          if (a.isLoopback || a.isLinkLocal || b.length != 4) continue;
          // Sem a máscara no Dart: supõe /24, o comum em casa.
          out.add(InternetAddress.fromRawAddress(Uint8List.fromList([b[0], b[1], b[2], 255])));
        }
      }
    } catch (_) {}
    _broadcastsAt = DateTime.now();
    return _broadcasts = out;
  }

  Future<void> _sendBroadcast(RawDatagramSocket socket, Map<String, dynamic> extra) async {
    final me = _me;
    if (me == null) return;
    final data = utf8.encode(jsonEncode({..._announcement(), ...extra}));
    for (final addr in await _broadcastAddresses()) {
      try {
        socket.send(data, addr, connectUdpPort);
      } catch (_) {}
    }
  }

  Future<void> _announce() async {
    final udp = _udp;
    if (udp != null) await _sendBroadcast(udp, {});
  }

  /// Procura aparelhos agora (abre a lista) e confere os adicionados pelo endereço.
  Future<void> refresh() async {
    final q = _udpQuery;
    if (q != null) await _sendBroadcast(q, {'t': 'q'});
    await _pollManual();
  }

  void _onDatagram(RawDatagramSocket socket, RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    final dg = socket.receive();
    final me = _me;
    if (dg == null || me == null) return;
    Map<String, dynamic> m;
    try {
      final j = jsonDecode(utf8.decode(dg.data));
      if (j is! Map || j['bk'] != 1) return;
      m = Map<String, dynamic>.from(j);
    } catch (_) {
      return;
    }
    if (m['id'] == me.id || m['uh'] != _uh) return;
    switch (m['t']) {
      case 'q':
        // Resposta direta a quem perguntou (na porta de onde veio a busca).
        try {
          _udp?.send(utf8.encode(jsonEncode(_announcement())), dg.address, dg.port);
        } catch (_) {}
        _upsert(m, dg.address.address);
      case 'a':
        _upsert(m, dg.address.address);
      case 'b':
        state = [
          for (final d in state)
            if (d.id != m['id']) d else if (d.manual) d.copyWith(seen: DateTime.fromMillisecondsSinceEpoch(0)),
        ];
    }
  }

  void _upsert(Map<String, dynamic> m, String host) {
    final id = m['id'];
    final port = m['port'];
    if (id is! String || port is! int) return;
    final name = m['n'] is String ? m['n'] as String : '?';
    final platform = m['p'] is String ? m['p'] as String : '';
    final now = DateTime.now();
    final i = state.indexWhere((d) => d.id == id);
    if (i < 0) {
      state = [...state, ConnectDevice(id: id, name: name, platform: platform, host: host, port: port, seen: now)];
    } else {
      final list = List.of(state);
      list[i] = list[i].copyWith(name: name, platform: platform, host: host, port: port, seen: now);
      state = list;
    }
  }

  void _prune() {
    final now = DateTime.now();
    final keep = state.where((d) => d.manual || now.difference(d.seen) < _deviceTtl).toList();
    if (keep.length != state.length) state = keep;
  }

  // ---- Aparelhos adicionados pelo endereço (ex.: Tailscale) ----

  List<ConnectDevice> _manualDevices() {
    final raw = ref.read(prefsProvider).getStringList(_kManual) ?? const [];
    final out = <ConnectDevice>[];
    for (final e in raw) {
      try {
        final j = Map<String, dynamic>.from(jsonDecode(e) as Map);
        out.add(
          ConnectDevice(
            id: j['id'] as String,
            name: j['n'] as String? ?? '?',
            platform: j['p'] as String? ?? '',
            host: j['h'] as String,
            port: j['port'] as int,
            seen: DateTime.fromMillisecondsSinceEpoch(0),
            manual: true,
          ),
        );
      } catch (_) {}
    }
    return out;
  }

  Future<void> _saveManual() => ref.read(prefsProvider).setStringList(_kManual, [
    for (final d in state.where((d) => d.manual))
      jsonEncode({'id': d.id, 'n': d.name, 'p': d.platform, 'h': d.host, 'port': d.port}),
  ]);

  static (String, int)? _parseAddress(String text) {
    var t = text.trim();
    t = t.replaceFirst(RegExp(r'^[a-z]+://'), '');
    t = t.split('/').first;
    if (t.isEmpty) return null;
    final i = t.lastIndexOf(':');
    if (i > 0 && !t.substring(0, i).contains(':')) {
      final port = int.tryParse(t.substring(i + 1));
      if (port == null) return null;
      return (t.substring(0, i), port);
    }
    return (t, connectTcpPort);
  }

  static Future<Map<String, dynamic>?> _info(String host, int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(Uri(scheme: 'http', host: host, port: port, path: '/info'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(await utf8.decodeStream(res));
      return j is Map && j['bk'] == 1 ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Adiciona pelo endereço (host ou host:porta). Devolve o aparelho, ou null
  /// se não achou um BKplayer da mesma conta lá.
  Future<ConnectDevice?> addManual(String text) async {
    final parsed = _parseAddress(text);
    if (parsed == null) return null;
    final (host, port) = parsed;
    final info = await _info(host, port);
    if (info == null || info['uh'] != _uh || info['id'] == _me?.id) return null;
    final d = ConnectDevice(
      id: info['id'] as String,
      name: info['n'] as String? ?? host,
      platform: info['p'] as String? ?? '',
      host: host,
      port: port,
      seen: DateTime.now(),
      manual: true,
    );
    state = [...state.where((x) => x.id != d.id), d];
    await _saveManual();
    return d;
  }

  Future<void> removeManual(String id) async {
    state = state.where((d) => d.id != id).toList();
    await _saveManual();
  }

  Future<void> _pollManual() async {
    for (final d in state.where((d) => d.manual).toList()) {
      final info = await _info(d.host, d.port);
      if (info != null && info['id'] == d.id) {
        final i = state.indexWhere((x) => x.id == d.id);
        if (i >= 0) {
          final list = List.of(state);
          list[i] = list[i].copyWith(name: info['n'] as String?, seen: DateTime.now());
          state = list;
        }
      }
    }
  }

  /// O que [d] está tocando (null = não respondeu).
  Future<DeviceStatus?> status(ConnectDevice d) async {
    final session = ref.read(sessionProvider).value;
    if (session == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final uri = Uri(
        scheme: 'http',
        host: d.host,
        port: d.port,
        path: '/status',
        queryParameters: session.provider.authParams,
      );
      final res = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(await utf8.decodeStream(res));
      if (j is! Map) return null;
      return DeviceStatus(playing: j['playing'] == true, title: j['title'] as String?, artist: j['artist'] as String?);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ---- Servidor: outros aparelhos controlando este ----

  bool _blocked(String ip) {
    final now = DateTime.now();
    final list = _failures[ip]?..removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    return (list?.length ?? 0) >= 8;
  }

  Map<String, String>? _authFrom(Map<String, String> q) {
    if (q['u'] != null && q['t'] != null && q['s'] != null) {
      // Só a mesma conta.
      if (q['u']!.trim().toLowerCase() != _username.trim().toLowerCase()) return null;
      return {'u': q['u']!, 't': q['t']!, 's': q['s']!};
    }
    if (q['apiKey'] != null) return {'apiKey': q['apiKey']!};
    return null;
  }

  Future<bool> _checkAuth(Map<String, String> auth) async {
    final key = sha256.convert(utf8.encode(jsonEncode(auth))).toString();
    final ok = _validated[key];
    if (ok != null && DateTime.now().difference(ok) < const Duration(hours: 12)) return true;
    final session = ref.read(sessionProvider).value;
    if (session == null) return false;
    if (!await session.provider.validateAuth(auth)) return false;
    _validated[key] = DateTime.now();
    return true;
  }

  Future<void> _json(HttpRequest req, Object body, [int status = 200]) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  Future<void> _onRequest(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (_me == null) return _json(req, {'error': 'starting'}, 503);
      if (path == '/info') return _json(req, _announcement());
      final ip = req.connectionInfo?.remoteAddress.address ?? '?';
      if (_blocked(ip)) return _json(req, {'error': 'too many attempts'}, 429);
      final auth = _authFrom(req.uri.queryParameters);
      if (auth == null || !await _checkAuth(auth)) {
        (_failures[ip] ??= []).add(DateTime.now());
        return _json(req, {'error': 'unauthorized'}, 401);
      }
      if (path == '/status') {
        final s = ref.read(playerProvider);
        final song = s.current?.song;
        return _json(req, {'playing': s.playing, 'title': song?.title, 'artist': song?.displayArtist});
      }
      if (path == '/connect' && WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        ws.pingInterval = const Duration(seconds: 8);
        _attach(ws, req.uri.queryParameters['cn'] ?? '?');
        return;
      }
      return _json(req, {'error': 'not found'}, 404);
    } catch (e) {
      try {
        await _json(req, {'error': '$e'}, 500);
      } catch (_) {}
    }
  }

  void _attach(WebSocket ws, String name) {
    final me = _me!;
    final c = _Controller(ws, name);
    _controllers.add(c);
    final s = ref.read(playerProvider);
    c.send({'t': 'hello', 'id': me.id, 'n': me.name, 'p': me.platform});
    c.send(_queueMessage(s));
    c.send(_stateMessage(s));
    ws.listen(
      (data) => _onCommand(data),
      onDone: () => _controllers.remove(c),
      onError: (_) => _controllers.remove(c),
      cancelOnError: true,
    );
  }

  Map<String, dynamic> _queueMessage(PlayerState s) => {
    't': 'queue',
    'qv': _queueVersion,
    'items': [
      for (final q in s.queue) {'u': q.uid, 's': q.song.toJson()},
    ],
  };

  Map<String, dynamic> _stateMessage(PlayerState s) {
    final cur = s.current;
    final ins = cur == null ? null : s.insights[cur.uid];
    final mix = s.mix;
    return {
      't': 'state',
      'qv': _queueVersion,
      'i': s.index,
      'pl': s.playing,
      'bf': s.buffering,
      'pos': s.position.inMilliseconds,
      'dur': s.duration.inMilliseconds,
      'vol': s.volume,
      'rep': s.repeat.name,
      'sh': s.shuffle,
      'rad': s.radio,
      if (mix != null)
        'mix': {'s': mix.summary, 'st': mix.style, 'ms': max(0, mix.until.difference(DateTime.now()).inMilliseconds)},
      if (s.plannedMix != null) 'pm': s.plannedMix,
      'ps': s.plannedSynced,
      if (ins != null) 'ins': {'bpm': ins.bpm, 'key': ins.key, 'cam': ins.camelot, 'rel': ins.reliable},
    };
  }

  void _pushState(PlayerState? prev, PlayerState next) {
    if (!identical(prev?.queue, next.queue)) _queueVersion++;
    if (_controllers.isEmpty) return;
    final queue = !identical(prev?.queue, next.queue) ? jsonEncode(_queueMessage(next)) : null;
    final st = jsonEncode(_stateMessage(next));
    for (final c in _controllers.toList()) {
      if (c.ws.readyState != WebSocket.open) continue;
      if (queue != null) c.ws.add(queue);
      c.ws.add(st);
    }
  }

  void _onCommand(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> m;
    try {
      final j = jsonDecode(data);
      if (j is! Map || j['t'] != 'cmd') return;
      m = Map<String, dynamic>.from(j);
    } catch (_) {
      return;
    }
    final p = ref.read(playerProvider.notifier);
    List<Song> songs() => [
      for (final e in (m['songs'] as List? ?? const []))
        if (e is Map) Song.fromJson(Map<String, dynamic>.from(e)),
    ];
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    switch (m['c']) {
      case 'toggle':
        p.toggle();
      case 'play':
        p.play();
      case 'pause':
        p.pause();
      case 'stop':
        p.stop();
      case 'next':
        p.next();
      case 'previous':
        p.previous();
      case 'seek':
        p.seek(Duration(milliseconds: n('ms')));
      case 'vol':
        p.setVolume((m['v'] as num?)?.toDouble() ?? 1);
      case 'jump':
        p.jumpTo(n('i'));
      case 'remove':
        p.removeAt(n('i'));
      case 'move':
        p.move(n('from'), n('to'));
      case 'clearUpcoming':
        p.clearUpcoming();
      case 'shuffle':
        p.toggleShuffle();
      case 'repeat':
        p.cycleRepeat();
      case 'radio':
        p.setRadio(m['on'] == true);
      case 'playSongs':
        p.playSongs(songs(), start: n('start'), shuffle: m['shuffle'] == true);
      case 'enqueue':
        p.enqueue(songs());
      case 'playNext':
        p.playNext(songs());
      case 'transfer':
        p.adoptQueue(
          songs(),
          index: n('index'),
          position: Duration(milliseconds: n('pos')),
          play: m['play'] == true,
          shuffle: m['shuffle'] == true,
          repeat: LoopMode.values.asNameMap()[m['repeat']] ?? LoopMode.off,
          radio: m['radio'] == true,
        );
    }
  }
}

final connectProvider = NotifierProvider<ConnectNotifier, List<ConnectDevice>>(ConnectNotifier.new);
