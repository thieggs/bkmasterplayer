import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/connect/connect_service.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/jam/jam_core.dart';
import 'package:player_musica/player/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Conexão falsa com o dono: o teste faz o papel dele.
class _FakeLink implements JamLink {
  final sent = <Map<String, dynamic>>[];
  final uploaded = <String>[];
  final _in = StreamController<Map<String, dynamic>>();

  void fromHost(Map<String, dynamic> m) => _in.add(m);

  @override
  String get peerId => 'dono';
  @override
  String get peerName => 'Dono';
  @override
  String get via => 'wifi';
  @override
  Stream<Map<String, dynamic>> get messages => _in.stream;
  @override
  void send(Map<String, dynamic> m) => sent.add(m);
  @override
  Future<void> sendFile(String path, String fileId, {void Function(double progress)? onProgress}) async {
    uploaded.add(fileId);
    onProgress?.call(1);
  }

  @override
  Stream<(String, String)> get files => const Stream.empty();
  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  Iterable<Map<String, dynamic>> of(String t) => sent.where((m) => m['t'] == t);
}

/// Player sem o motor: guarda o que a Festa manda mostrar, como o de verdade.
class _JamPlayer extends PlayerController {
  JamRemote? jam;
  PlayerState? before;

  static const mine = PlayerState(queue: [QueueItem('meu', Song(id: 'local', title: 'Minha'))], index: 0);

  @override
  PlayerState build() => mine;

  @override
  Future<void> enterJam(JamRemote jam, String host) async {
    this.jam = jam;
    before = state;
    state = PlayerState(jamHost: host);
  }

  @override
  void jamMirror({
    required String host,
    required List<QueueItem> queue,
    required bool playing,
    required Duration position,
    required Duration duration,
  }) =>
      state = PlayerState(
        queue: queue,
        index: queue.isEmpty ? -1 : 0,
        playing: playing,
        position: position,
        duration: duration,
        jamHost: host,
      );

  @override
  void leaveJam() {
    jam = null;
    state = before!;
  }
}

class _NoConnect extends ConnectNotifier {
  @override
  List<ConnectDevice> build() => const [];
}

Map<String, dynamic> _song(String id, String uid, {String? by, String? cover}) => {
      'id': id,
      'title': 'Música $id',
      'artist': 'Artista',
      'albumId': 'al-$id',
      'artistId': 'ar-$id',
      'duration': 180000,
      'coverArt': ?cover,
      'uid': uid,
      'by': ?by,
    };

/// Espera a condição (gravação de arquivo, mensagens assíncronas).
Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ok(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer c;
  late _FakeLink link;
  late Directory tmp;

  _JamPlayer player() => c.read(playerProvider.notifier) as _JamPlayer;
  PlayerState shown() => c.read(playerProvider);
  JamGuestNotifier guest() => c.read(jamGuestProvider.notifier);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tmp = Directory.systemTemp.createTempSync('festa_');
    c = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
      cacheDirProvider.overrideWithValue(tmp),
      playerProvider.overrideWith(_JamPlayer.new),
      connectProvider.overrideWith(_NoConnect.new),
    ]);
    link = _FakeLink();
    await guest().join(JamOffer(key: 'k', hostId: 'dono', hostName: 'Ana', via: 'wifi', join: (_, _, _) async => link));
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  /// O dono de versão nova manda boas-vindas e o que está tocando.
  Future<void> hostPlaying({int version = jamProtocol}) async {
    link.fromHost({'t': 'welcome', 'n': 'Ana', 'v': version});
    link.fromHost({
      't': 'state',
      'playing': true,
      'pos': 42000,
      'dur': 180000,
      'cur': _song('a', 'u1', cover: 'c-a'),
      'next': [_song('b', 'u2', by: 'Beto'), _song('c', 'u3')],
    });
    await _until(() => shown().queue.length == 3);
  }

  test('entrar na Festa põe o player daqui no modo Festa', () {
    expect(player().jam, isNotNull);
    expect(shown().jamHost, 'Ana');
    expect(shown().elsewhere, isTrue);
  });

  test('o que toca no dono vira a fila do player', () async {
    await hostPlaying();
    final s = shown();
    expect(s.index, 0);
    expect(s.playing, isTrue);
    expect(s.position, const Duration(seconds: 42));
    expect([for (final q in s.queue) q.uid], ['u1', 'u2', 'u3']);
    final cur = s.current!.song;
    // O id é marcado como do dono, e o que só vale na biblioteca de lá some.
    expect(cur.id, '${jamHostPrefix}a');
    expect(cur.albumId, isNull);
    expect(cur.artistId, isNull);
    expect(c.read(jamGuestProvider).addedBy, {'u2': 'Beto'});
  });

  test('a capa do dono chega como arquivo e aparece no player', () async {
    await hostPlaying();
    // A atual pede a miniatura e a grande.
    expect(link.of('cover').map((m) => (m['id'], m['big'] == true)), containsAll([('c-a', false), ('c-a', true)]));
    final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];
    link.fromHost({'t': 'cover', 'id': 'c-a', 'b64': base64Encode(png)});
    await _until(() => shown().current?.song.coverArt != null);
    final small = shown().current!.song.coverArt!;
    expect(File(small).existsSync(), isTrue);
    link.fromHost({'t': 'cover', 'id': 'c-a', 'big': true, 'b64': base64Encode(png)});
    await _until(() => shown().current?.song.coverArt != small);
    expect(shown().current!.song.coverArt, endsWith('_b.img'));
  });

  test('o que não é imagem não vira capa', () async {
    await hostPlaying();
    link.fromHost({'t': 'cover', 'id': 'c-a', 'b64': base64Encode(utf8.encode('<script>'))});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(shown().current!.song.coverArt, isNull);
  });

  test('a mesma entrada não é recriada a cada aviso do dono', () async {
    await hostPlaying();
    final before = shown().current!;
    link.fromHost({'t': 'state', 'playing': true, 'pos': 43000, 'dur': 180000, 'cur': _song('a', 'u1', cover: 'c-a'), 'next': const []});
    await _until(() => shown().position == const Duration(seconds: 43));
    expect(identical(shown().current, before), isTrue);
  });

  test('os botões do player vão para o dono', () async {
    await hostPlaying();
    final j = player().jam!;
    j.command('pause', const {});
    j.command('seek', {'ms': 1000});
    j.command('jump', {'i': 2});
    expect([for (final m in link.of('cmd')) (m['c'], m['ms'], m['u'])], [('pause', null, null), ('seek', 1000, null), ('jump', null, 'u3')]);
  });

  test('com dono antigo, play/pause viram toggle e pular fica de fora', () async {
    await hostPlaying(version: 1);
    final j = player().jam!;
    j.command('play', const {}); // já está tocando: nada a fazer
    j.command('pause', const {});
    j.command('jump', {'i': 1});
    expect([for (final m in link.of('cmd')) m['c']], ['toggle']);
  });

  test('o que o convidado não manda não sai daqui', () async {
    await hostPlaying();
    for (final c in ['vol', 'shuffle', 'repeat', 'radio', 'remove', 'move', 'clearUpcoming', 'stop']) {
      player().jam!.command(c, const {'i': 0, 'v': 0.2});
    }
    expect(link.sent.where((m) => m['t'] == 'cmd' || m['t'] == 'add'), isEmpty);
  });

  test('músicas do próprio dono voltam pelo id: a seguir ou no fim', () async {
    await hostPlaying();
    final song = shown().queue[2].song;
    player().jam!.command('playNext', {'songs': [song.toJson()]});
    player().jam!.command('enqueue', {'songs': [song.toJson()]});
    await _until(() => link.of('add').length == 2);
    final adds = link.of('add').toList();
    expect(adds[0]['songs'][0]['id'], 'c');
    expect(adds[0]['end'], isNull);
    expect(adds[1]['end'], isTrue);
    // Nem o caminho da capa daqui vai junto.
    expect((adds[0]['songs'][0] as Map).containsKey('coverArt'), isFalse);
  });

  test('músicas daqui vão como arquivo, uma por vez, na ordem', () async {
    await hostPlaying();
    final files = [
      for (final n in ['um', 'dois'])
        (File('${tmp.path}/$n.mp3')..writeAsBytesSync(List.filled(1000, 1))).path,
    ];
    final songs = [for (final (i, f) in files.indexed) Song(id: 'file:$f', title: 'Faixa $i', suffix: 'mp3', path: f)];
    player().jam!.command('playSongs', {'songs': [for (final s in songs) s.toJson()], 'start': 0});
    expect(c.read(jamGuestProvider).sentCount, 2);
    await _until(() => link.of('offer').length == 1);
    // A segunda espera a primeira ser aceita e enviada.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(link.of('offer').length, 1);
    final first = link.of('offer').first;
    expect(first['song']['title'], 'Faixa 0');
    expect((first['song'] as Map).containsKey('path'), isFalse);
    link.fromHost({'t': 'accept', 'fid': first['fid']});
    await _until(() => link.of('offer').length == 2);
    expect(link.uploaded, [first['fid']]);
    expect(link.of('offer').last['song']['title'], 'Faixa 1');
  });

  test('sair devolve a fila daqui e avisa o dono', () async {
    await hostPlaying();
    await guest().leave();
    expect(shown().jamHost, isNull);
    expect(shown().current?.song.id, 'local');
    expect(link.of('bye'), isNotEmpty);
  });

  test('se a conexão cai, o player volta sozinho', () async {
    await hostPlaying();
    await link.close();
    await _until(() => shown().jamHost == null);
    expect(shown().current?.song.id, 'local');
    expect(c.read(jamGuestProvider).phase, JamPhase.ended);
  });
}
