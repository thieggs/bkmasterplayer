import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'jam_core.dart';

/// Festa por Bluetooth sem o Google Play Services (lado nativo em
/// JamBluetooth.kt): acha o dono por Bluetooth LE e conecta num canal L2CAP,
/// ou, no modo manual, conecta por RFCOMM num celular já pareado.
///
/// Aperto de mão, antes de a conexão virar um [JamLink]:
/// dono → `hi` (id e nome dele); convidado → `hello` (id, nome e o passe que
/// este dono deu, se deu); dono → `_ok` ou `rejected`.
class BluetoothJam implements JamTransport {
  BluetoothJam._() {
    _ev.receiveBroadcastStream().listen((e) => _onEvent(Map<String, dynamic>.from(e as Map)), onError: (_) {});
  }

  static const _m = MethodChannel('bkplayer/bt');
  static const _ev = EventChannel('bkplayer/bt/events');

  static BluetoothJam? _instance;

  /// null fora do Android.
  static BluetoothJam? get instance => Platform.isAndroid ? (_instance ??= BluetoothJam._()) : null;

  @override
  bool get available => true;

  final _links = <String, _BtLink>{};

  /// O Bluetooth está ligado?
  static Future<bool> isOn() async {
    try {
      final s = await _m.invokeMapMethod<String, dynamic>('state');
      return s?['on'] == true;
    } catch (_) {
      return false;
    }
  }

  // ---- Dono ----

  bool _hosting = false;
  String _hostId = '';
  String _hostName = '';
  Future<bool> Function(JamJoinRequest req)? _onRequest;
  void Function(JamLink link)? _onJoined;

  @override
  Future<void> startHosting({
    required String hostName,
    required String hostId,
    required String jamId,
    required Future<bool> Function(JamJoinRequest req) onRequest,
    required void Function(JamLink link) onJoined,
  }) async {
    _hostId = hostId;
    _hostName = hostName;
    _onRequest = onRequest;
    _onJoined = onJoined;
    await _m.invokeMethod('startHosting', {'name': hostName});
    _hosting = true;
  }

  @override
  Future<void> stopHosting() async {
    _hosting = false;
    try {
      await _m.invokeMethod('stopHosting');
    } catch (_) {}
  }

  Future<void> _incoming(String id) async {
    final link = _BtLink(id);
    _links[id] = link;
    link.send({'t': 'hi', 'id': _hostId, 'n': _hostName});
    final Map<String, dynamic> m;
    try {
      m = await link.first().timeout(const Duration(seconds: 15));
    } catch (_) {
      await link.close();
      return;
    }
    if (m['t'] != 'hello' || m['id'] is! String || !_hosting) {
      await link.close();
      return;
    }
    final req = JamJoinRequest(
      guestId: m['id'] as String,
      guestName: m['n'] is String ? m['n'] as String : '?',
      via: 'bluetooth',
      pass: m['k'] is String ? m['k'] as String : null,
    );
    final ok = await (_onRequest?.call(req) ?? Future.value(false));
    if (!ok || !_hosting) {
      link.send({'t': 'rejected'});
      // Dá tempo de a recusa sair antes de fechar.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await link.close();
      return;
    }
    link
      ..peerId = req.guestId
      ..peerName = req.guestName
      ..send({'t': '_ok'});
    _onJoined?.call(link);
  }

  // ---- Convidado ----

  StreamController<List<JamOffer>>? _offers;
  final _found = <String, ({String name, int psm, DateTime seen})>{};
  Timer? _prune;

  @override
  Stream<List<JamOffer>> discover({required String myId, required String myName}) {
    _offers?.close();
    _found.clear();
    final c = StreamController<List<JamOffer>>.broadcast();
    _offers = c;
    _prune?.cancel();
    // Dono que sumiu do ar some da lista.
    _prune = Timer.periodic(const Duration(seconds: 5), (_) {
      final antes = _found.length;
      _found.removeWhere((_, f) => DateTime.now().difference(f.seen) > const Duration(seconds: 20));
      if (_found.length != antes) _emitOffers();
    });
    _m.invokeMethod('startScan').catchError((Object e) {
      if (!c.isClosed) c.addError(e);
    });
    return c.stream;
  }

  @override
  Future<void> stopDiscovery() async {
    _prune?.cancel();
    _prune = null;
    try {
      await _m.invokeMethod('stopScan');
    } catch (_) {}
  }

  void _emitOffers() {
    final c = _offers;
    if (c == null || c.isClosed) return;
    c.add([for (final e in _found.entries) _offer(e.key, e.value.name, e.value.psm)]);
  }

  JamOffer _offer(String addr, String name, int psm) =>
      JamOffer(key: 'bt:$addr', hostId: 'bt:$addr', hostName: name, via: 'bluetooth', join: (id, myName, _) => _join(addr, psm, id, myName));

  /// Celulares pareados nas configurações do sistema (modo manual).
  Future<List<JamOffer>> paired() async {
    final l = await _m.invokeListMethod<Map<dynamic, dynamic>>('paired') ?? const [];
    return [for (final d in l) _offer('${d['addr']}', '${d['name']}', 0)];
  }

  Future<JamLink> _join(String addr, int psm, String myId, String myName) async {
    final String id;
    try {
      id = (await _m.invokeMethod<String>('connect', {'addr': addr, 'psm': psm}))!;
    } catch (e) {
      debugPrint('Bluetooth: não conectou em $addr: $e');
      throw const JamRejected();
    }
    final link = _BtLink(id);
    _links[id] = link;
    try {
      final hi = await link.first().timeout(const Duration(seconds: 10));
      if (hi['t'] != 'hi' || hi['id'] is! String) throw const JamRejected();
      link
        ..peerId = hi['id'] as String
        ..peerName = hi['n'] is String ? hi['n'] as String : '?';
      link.send({'t': 'hello', 'id': myId, 'n': myName, 'k': ?jamPassFor?.call(link.peerId)});
      // O dono tem até 2 minutos para aceitar.
      final r = await link.first().timeout(const Duration(minutes: 3));
      if (r['t'] != '_ok') throw const JamRejected();
      if (psm > 0) unawaited(_m.invokeMethod('boost', {'id': id}).catchError((_) => null));
      return link;
    } catch (_) {
      await link.close();
      throw const JamRejected();
    }
  }

  // ---- Eventos do nativo ----

  void _onEvent(Map<String, dynamic> e) {
    final id = e['id'] as String?;
    switch (e['e']) {
      case 'found':
        final addr = '${e['addr']}';
        final old = _found[addr];
        final psm = (e['psm'] as num?)?.toInt() ?? old?.psm;
        if (psm == null) return;
        final name = e['name'] as String? ?? old?.name ?? 'Festa';
        // O Android troca o endereço BLE aleatório de tempos em tempos: o mesmo
        // dono (nome e canal iguais) com endereço novo substitui o antigo.
        final antes = _found.length;
        _found.removeWhere((a, f) => a != addr && f.name == name && f.psm == psm);
        _found[addr] = (name: name, psm: psm, seen: DateTime.now());
        if (old == null || old.name != name || _found.length != antes) _emitOffers();
      case 'scanFailed':
        _offers?.addError(StateError('scan ${e['code']}'));
      case 'advertiseFailed':
        debugPrint('Bluetooth: anúncio falhou (${e['code']})');
      case 'incoming':
        if (id != null && _hosting) unawaited(_incoming(id));
      case 'msg':
        _links[id]?._onData(e['data'] as Uint8List);
      case 'file':
        _links[id]?._files.add(('${e['fid']}', '${e['path']}'));
      case 'progress':
        _links[id]?._sending['${e['fid']}']?.$2?.call((e['pct'] as num) / 100);
      case 'sent':
        _links[id]?._sending.remove('${e['fid']}')?.$1.complete();
      case 'fileFailed':
        _links[id]?._sending.remove('${e['fid']}')?.$1.completeError(StateError('transferência falhou'));
      case 'closed':
        _links.remove(id)?._closed();
    }
  }
}

class _BtLink implements JamLink {
  _BtLink(this.id);

  final String id;
  @override
  String peerId = '';
  @override
  String peerName = '?';
  @override
  String get via => 'bluetooth';

  final _messages = StreamController<Map<String, dynamic>>();
  final _files = StreamController<(String, String)>.broadcast();
  final _sending = <String, (Completer<void>, void Function(double)?)>{};

  /// Aperto de mão: a próxima mensagem vai para cá, não para [messages].
  Completer<Map<String, dynamic>>? _waiter;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Stream<(String, String)> get files => _files.stream;

  Future<Map<String, dynamic>> first() => (_waiter = Completer()).future;

  void _onData(Uint8List data) {
    final Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(utf8.decode(data)) as Map);
    } catch (_) {
      return;
    }
    final w = _waiter;
    if (w != null) {
      _waiter = null;
      w.complete(m);
    } else if (!_messages.isClosed) {
      _messages.add(m);
    }
  }

  @override
  void send(Map<String, dynamic> m) {
    BluetoothJam._m.invokeMethod('send', {'id': id, 'data': Uint8List.fromList(utf8.encode(jsonEncode(m)))}).catchError((_) => null);
  }

  @override
  Future<void> sendFile(String path, String fileId, {void Function(double progress)? onProgress}) async {
    final done = Completer<void>();
    _sending[fileId] = (done, onProgress);
    try {
      await BluetoothJam._m.invokeMethod('sendFile', {'id': id, 'path': path, 'fid': fileId});
    } catch (e) {
      _sending.remove(fileId);
      rethrow;
    }
    // Bluetooth é lento: uma música grande leva minutos.
    await done.future.timeout(const Duration(minutes: 20));
  }

  void _closed() {
    _waiter?.completeError(StateError('desconectado'));
    _waiter = null;
    if (!_messages.isClosed) _messages.close();
    if (!_files.isClosed) _files.close();
    for (final s in _sending.values) {
      if (!s.$1.isCompleted) s.$1.completeError(StateError('desconectado'));
    }
    _sending.clear();
  }

  @override
  Future<void> close() async {
    try {
      await BluetoothJam._m.invokeMethod('close', {'id': id});
    } catch (_) {}
    _closed();
  }
}
