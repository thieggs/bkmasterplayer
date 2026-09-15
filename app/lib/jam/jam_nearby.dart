import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'jam_core.dart';

/// Jam por Bluetooth/Wi-Fi Direct no Android (Nearby Connections, lado nativo
/// em JamNearby.kt). Mensagens vão como bytes (divididas em pedaços: o limite
/// é 32 KB) e as músicas como arquivo, pelo meio mais rápido que o Google
/// negociar.
class NearbyJam implements JamTransport {
  NearbyJam._() {
    _m.setMethodCallHandler(_onNative);
    _ev.receiveBroadcastStream().listen((e) => _onEvent(Map<String, dynamic>.from(e as Map)), onError: (_) {});
  }

  static const _m = MethodChannel('bkplayer/nearby');
  static const _ev = EventChannel('bkplayer/nearby/events');

  /// null se o aparelho não tem o Google Play Services (ou não é Android).
  static Future<NearbyJam?> create() async {
    if (!Platform.isAndroid) return null;
    // O canal nativo é registrado pela activity, que pode ligar ao motor
    // depois de o Dart começar: tenta de novo por alguns segundos.
    for (var i = 0; i < 10; i++) {
      try {
        return (await _m.invokeMethod<bool>('available') ?? false) ? NearbyJam._() : null;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  bool get available => true;

  final links = <String, _NearbyLink>{};
  bool _hosting = false;
  Future<bool> Function(JamJoinRequest req)? _onRequest;
  void Function(JamLink link)? _onJoined;
  final _accepted = <String, (String, String)>{};
  final _found = <String, (String, Map<String, dynamic>)>{};
  StreamController<List<JamOffer>>? _offers;
  final _joining = <String, Completer<JamLink>>{};

  static Uint8List _info(Map<String, dynamic> m) {
    // O Nearby aceita pouco espaço aqui (~130 bytes): encurta o nome até caber.
    var n = '${m['n'] ?? ''}';
    if (n.length > 40) n = n.substring(0, 40);
    while (true) {
      final b = utf8.encode(jsonEncode({...m, 'n': n}));
      if (b.length <= 128 || n.isEmpty) return Uint8List.fromList(b);
      n = n.substring(0, n.length - 1);
    }
  }

  static Map<String, dynamic>? _parse(dynamic s) {
    try {
      final j = jsonDecode('$s');
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _onNative(MethodCall call) async {
    if (call.method == 'jamDecision') {
      final a = Map<String, dynamic>.from(call.arguments as Map);
      jamDecisionSink?.call('${a['key']}', '${a['what']}');
    }
  }

  // ---- Dono ----

  @override
  Future<void> startHosting({
    required String hostName,
    required String hostId,
    required String jamId,
    required Future<bool> Function(JamJoinRequest req) onRequest,
    required void Function(JamLink link) onJoined,
  }) async {
    _hosting = true;
    _onRequest = onRequest;
    _onJoined = onJoined;
    await _m.invokeMethod('setHosting', {'on': true});
    try {
      await _m.invokeMethod('startBeacon');
    } catch (e) {
      debugPrint('beacon: $e');
    }
    await _m.invokeMethod('startAdvertising', {'info': _info({'i': hostId, 'n': hostName, 'j': jamId})});
  }

  @override
  Future<void> stopHosting() async {
    if (!_hosting) return;
    _hosting = false;
    for (final l in links.values.toList()) {
      await l.close();
    }
    try {
      await _m.invokeMethod('stopAdvertising');
      await _m.invokeMethod('stopBeacon');
      await _m.invokeMethod('setHosting', {'on': false});
    } catch (_) {}
  }

  // ---- Convidado ----

  @override
  Stream<List<JamOffer>> discover({required String myId, required String myName}) {
    _offers?.close();
    _found.clear();
    final c = StreamController<List<JamOffer>>.broadcast();
    _offers = c;
    _m.invokeMethod('startDiscovery').catchError((Object e) {
      if (!c.isClosed) c.addError(e);
    });
    return c.stream;
  }

  @override
  Future<void> stopDiscovery() async {
    try {
      await _m.invokeMethod('stopDiscovery');
    } catch (_) {}
  }

  void _emitOffers() {
    _offers?.add([
      for (final e in _found.entries)
        JamOffer(
          key: 'bt:${e.key}',
          hostId: '${e.value.$2['i'] ?? e.key}',
          hostName: e.value.$1,
          via: 'bluetooth',
          join: (id, name, pass) => _join(e.key, id, name, pass),
        ),
    ]);
  }

  Future<JamLink> _join(String endpointId, String myId, String myName, String? pass) async {
    final c = Completer<JamLink>();
    _joining[endpointId] = c;
    await _m.invokeMethod('requestConnection', {'id': endpointId, 'info': _info({'i': myId, 'n': myName, 'k': ?pass})});
    return c.future.timeout(const Duration(minutes: 3), onTimeout: () {
      _joining.remove(endpointId);
      throw const JamRejected();
    });
  }

  Future<void> _onEvent(Map<String, dynamic> e) async {
    final id = e['id'] as String?;
    if (id == null) return;
    switch (e['e']) {
      case 'found':
        final info = _parse(e['info']);
        if (info != null && info['j'] != null) {
          _found[id] = ('${info['n'] ?? '?'}', info);
          _emitOffers();
        }
      case 'lost':
        _found.remove(id);
        _emitOffers();
      case 'initiated':
        if (e['incoming'] == true && _hosting) {
          final info = _parse(e['info']) ?? const {};
          final req = JamJoinRequest(
            guestId: '${info['i'] ?? id}',
            guestName: '${info['n'] ?? '?'}',
            via: 'bluetooth',
            pass: info['k'] is String ? info['k'] as String : null,
          );
          final ok = await (_onRequest?.call(req) ?? Future.value(false));
          try {
            if (ok) {
              _accepted[id] = (req.guestId, req.guestName);
              await _m.invokeMethod('accept', {'id': id});
            } else {
              await _m.invokeMethod('reject', {'id': id});
            }
          } catch (_) {}
        } else if (e['incoming'] != true && _joining.containsKey(id)) {
          // O convidado aceita a própria conexão; quem decide é o dono.
          try {
            await _m.invokeMethod('accept', {'id': id});
          } catch (_) {}
        }
      case 'connected':
        final acc = _accepted.remove(id);
        if (acc != null) {
          final link = _NearbyLink(this, id, acc.$1, acc.$2);
          links[id] = link;
          _onJoined?.call(link);
        }
        final j = _joining.remove(id);
        if (j != null) {
          final host = _found[id];
          final link = _NearbyLink(this, id, '${host?.$2['i'] ?? id}', host?.$1 ?? '?');
          links[id] = link;
          j.complete(link);
        }
      case 'rejected':
        _accepted.remove(id);
        _joining.remove(id)?.completeError(const JamRejected());
      case 'disconnected':
        links.remove(id)?._closed();
      case 'bytes':
        links[id]?._onBytes(e['data'] as Uint8List);
      case 'progress':
        links[id]?._onProgress((e['payloadId'] as num).toInt(), (e['pct'] as num).toInt());
      case 'sent':
        links[id]?._onSent((e['payloadId'] as num).toInt());
      case 'file':
        links[id]?._onFile((e['payloadId'] as num).toInt(), e['path'] as String);
      case 'fileFailed':
        links[id]?._onFileFailed((e['payloadId'] as num).toInt());
    }
  }

  // ---- Avisos do sistema ----

  /// Scan em segundo plano do beacon (aviso de Jam por perto).
  static Future<void> setBeaconScan(bool on) async {
    try {
      await _m.invokeMethod('setBeaconScan', {'on': on});
    } catch (_) {}
  }

  static Future<void> showRequest(JamJoinRequest req) async {
    final pt = Platform.localeName.startsWith('pt');
    try {
      await _m.invokeMethod('showJoinRequest', {
        'key': req.key,
        'name': req.guestName,
        'title': pt ? '${req.guestName} quer entrar na sua Jam' : '${req.guestName} wants to join your Jam',
        'accept': pt ? 'Aceitar' : 'Accept',
        'reject': pt ? 'Recusar' : 'Decline',
        'always': pt ? 'Sempre' : 'Always',
      });
    } catch (_) {}
  }

  static Future<void> hideRequest(JamJoinRequest req) async {
    try {
      await _m.invokeMethod('cancelJoinRequest', {'key': req.key});
    } catch (_) {}
  }
}

class _NearbyLink implements JamLink {
  _NearbyLink(this._t, this.endpointId, this.peerId, this.peerName);

  final NearbyJam _t;
  final String endpointId;
  @override
  final String peerId;
  @override
  final String peerName;
  @override
  String get via => 'bluetooth';

  final _messages = StreamController<Map<String, dynamic>>();
  final _files = StreamController<(String, String)>.broadcast();
  final _chunks = <int, List<Uint8List?>>{};
  final _rnd = Random();

  // Arquivos: o id da Jam chega numa mensagem; o arquivo, num evento à parte.
  final _fidOf = <int, String>{};
  final _pathOf = <int, String>{};
  final _sending = <int, (Completer<void>, void Function(double)?)>{};

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Stream<(String, String)> get files => _files.stream;

  static const _max = 30000;

  @override
  void send(Map<String, dynamic> m) {
    final data = Uint8List.fromList(utf8.encode(jsonEncode(m)));
    if (data.length <= _max) {
      _raw(Uint8List.fromList([0, ...data]));
      return;
    }
    final msgId = _rnd.nextInt(1 << 31);
    final count = (data.length / _max).ceil();
    for (var i = 0; i < count; i++) {
      final part = data.sublist(i * _max, min(data.length, (i + 1) * _max));
      final head = ByteData(9)
        ..setUint8(0, 1)
        ..setUint32(1, msgId)
        ..setUint16(5, i)
        ..setUint16(7, count);
      _raw(Uint8List.fromList([...head.buffer.asUint8List(), ...part]));
    }
  }

  void _raw(Uint8List data) {
    NearbyJam._m.invokeMethod('sendBytes', {'id': endpointId, 'data': data}).catchError((_) => null);
  }

  void _onBytes(Uint8List data) {
    if (data.isEmpty) return;
    Uint8List? whole;
    if (data[0] == 0) {
      whole = data.sublist(1);
    } else if (data[0] == 1 && data.length > 9) {
      final h = ByteData.sublistView(data, 0, 9);
      final msgId = h.getUint32(1), idx = h.getUint16(5), count = h.getUint16(7);
      final parts = _chunks.putIfAbsent(msgId, () => List<Uint8List?>.filled(count, null));
      if (idx < parts.length) parts[idx] = data.sublist(9);
      if (parts.every((x) => x != null)) {
        _chunks.remove(msgId);
        whole = Uint8List.fromList([for (final x in parts) ...x!]);
      }
    }
    if (whole == null) return;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(utf8.decode(whole)) as Map);
      if (m['t'] == '_file') {
        final pid = (m['pid'] as num).toInt();
        _fidOf[pid] = '${m['fid']}';
        _maybeFile(pid);
        return;
      }
      if (!_messages.isClosed) _messages.add(m);
    } catch (_) {}
  }

  void _onFile(int pid, String path) {
    _pathOf[pid] = path;
    _maybeFile(pid);
  }

  void _maybeFile(int pid) {
    final fid = _fidOf[pid], path = _pathOf[pid];
    if (fid == null || path == null) return;
    _fidOf.remove(pid);
    _pathOf.remove(pid);
    if (!_files.isClosed) _files.add((fid, path));
  }

  void _onProgress(int pid, int pct) => _sending[pid]?.$2?.call(pct / 100);

  void _onSent(int pid) => _sending.remove(pid)?.$1.complete();

  void _onFileFailed(int pid) => _sending.remove(pid)?.$1.completeError(StateError('transferência falhou'));

  @override
  Future<void> sendFile(String path, String fileId, {void Function(double progress)? onProgress}) async {
    final pid = await NearbyJam._m.invokeMethod<int>('sendFile', {'id': endpointId, 'path': path});
    if (pid == null) throw StateError('sem transferência');
    final done = Completer<void>();
    _sending[pid] = (done, onProgress);
    send({'t': '_file', 'fid': fileId, 'pid': pid});
    await done.future.timeout(const Duration(minutes: 10));
  }

  void _closed() {
    if (!_messages.isClosed) _messages.close();
    if (!_files.isClosed) _files.close();
    for (final s in _sending.values) {
      if (!s.$1.isCompleted) s.$1.completeError(StateError('desconectado'));
    }
    _sending.clear();
  }

  @override
  Future<void> close() async {
    _t.links.remove(endpointId);
    try {
      await NearbyJam._m.invokeMethod('disconnect', {'id': endpointId});
    } catch (_) {}
    _closed();
  }
}
