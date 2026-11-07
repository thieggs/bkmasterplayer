import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/core/providers.dart';
import 'package:player_musica/data/accounts.dart';
import 'package:player_musica/data/smart_saved.dart';
import 'package:player_musica/data/subsonic/subsonic_client.dart';
import 'package:player_musica/domain/models.dart';
import 'package:player_musica/domain/music_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aleatórios smart salvos valendo em todo aparelho da conta (pedido do
/// usuário, 07/11/2026): cada salvo é uma playlist privada no servidor.

Song _s(String id) => Song(id: id, title: 'Música $id', artist: 'Artista $id', artistId: 'ar-$id', coverArt: 'c-$id');

class _Pl {
  _Pl(this.id, this.name, this.owner, this.songs, this.changed);
  final String id;
  String name;
  String? comment;
  final String owner;
  List<String> songs;
  DateTime changed;
}

/// Um Navidrome de mentira: playlists com dono, comentário e "alterado em";
/// erro 70 quando a playlist não existe; sem rede, erro sem código.
class _Servidor implements MusicProvider {
  final catalogo = {for (final id in ['a', 'b', 'c', 'd', 'p']) id: _s(id)};
  final pls = <String, _Pl>{};
  var offline = false;
  var leituras = 0;
  var _n = 0;
  var _relogio = DateTime.utc(2026, 11, 7, 12);

  @override
  String get accountId => 'conta';

  void _rede() {
    if (offline) throw SubsonicException('sem rede');
  }

  DateTime _tick() => _relogio = _relogio.add(const Duration(milliseconds: 1500));

  Playlist _pl(_Pl p, {bool songs = false}) => Playlist(
        id: p.id,
        name: p.name,
        comment: p.comment,
        owner: p.owner,
        songCount: p.songs.length,
        changed: p.changed,
        songs: songs ? [for (final id in p.songs) catalogo[id]!] : const [],
      );

  _Pl _get(String id) => pls[id] ?? (throw SubsonicException('não existe', code: 70));

  /// As playlists de salvos guardadas.
  List<_Pl> get salvos => [for (final p in pls.values) if (p.comment?.contains(SavedSmart.marker) ?? false) p];

  @override
  Future<List<Playlist>> playlists() async {
    _rede();
    return [for (final p in pls.values) _pl(p)];
  }

  @override
  Future<Playlist> playlist(String id) async {
    _rede();
    leituras++;
    return _pl(_get(id), songs: true);
  }

  @override
  Future<Playlist> createPlaylist(String name, {List<String> songIds = const []}) async {
    _rede();
    final p = _Pl('pl${++_n}', name, 'eu', [...songIds], _tick());
    pls[p.id] = p;
    return _pl(p);
  }

  @override
  Future<void> updatePlaylist(String playlistId, {String? name, String? comment, List<String>? songIds}) async {
    _rede();
    final p = _get(playlistId);
    if (name != null) p.name = name;
    if (comment != null) p.comment = comment;
    if (songIds != null) p.songs = [...songIds];
    p.changed = _tick();
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _rede();
    _get(playlistId);
    pls.remove(playlistId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// As preferências de um aparelho (cada um tem as suas).
class _Prefs implements SharedPreferences {
  final m = <String, Object>{};

  @override
  String? getString(String key) => m[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    m[key] = value;
    return true;
  }

  @override
  List<String>? getStringList(String key) => (m[key] as List?)?.cast<String>();

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    m[key] = [...value];
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sessao extends SessionNotifier {
  _Sessao(this.servidor);
  final _Servidor servidor;

  @override
  Future<Session?> build() async => Session(
        account: const ServerAccount(id: 'conta', name: 'Casa', baseUrl: 'http://casa', username: 'eu'),
        provider: servidor,
      );
}

/// Um aparelho logado na conta, já sincronizado.
Future<(ProviderContainer, SavedSmartNotifier)> _aparelho(_Servidor servidor, {_Prefs? prefs}) async {
  final c = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(prefs ?? _Prefs()),
    sessionProvider.overrideWith(() => _Sessao(servidor)),
  ]);
  addTearDown(c.dispose);
  await c.read(sessionProvider.future);
  c.listen(savedSmartProvider, (_, _) {});
  final n = c.read(savedSmartProvider.notifier);
  await n.sync(force: true);
  return (c, n);
}

SavedSmart _samba({String name = 'Samba de domingo', DateTime? saved}) => SavedSmart(
      id: 'smart-1',
      name: name,
      liked: [(_s('a'), 3.5), (_s('b'), 1.25)],
      avoid: [_s('p')],
      saved: saved ?? DateTime(2026, 11, 7, 10),
      played: DateTime(2026, 11, 7, 11),
    );

void main() {
  test('salvo num aparelho aparece no outro, igual', () async {
    final srv = _Servidor();
    final (_, a) = await _aparelho(srv);
    a.put(_samba());
    await a.sync(force: true);

    expect(srv.salvos, hasLength(1));
    final pl = srv.salvos.single;
    expect(pl.name, 'Aleatório smart: Samba de domingo');
    expect(pl.songs, ['a', 'b'], reason: 'os ímãs são as músicas da playlist, do mais forte ao mais fraco');
    expect(a.state.single.remote, pl.id);

    final (_, b) = await _aparelho(srv);
    final s = b.state.single;
    expect(s.id, 'smart-1', reason: 'o mesmo id em todo aparelho');
    expect(s.name, 'Samba de domingo');
    expect(s.liked.map((x) => (x.$1.id, x.$2)), [('a', 3.5), ('b', 1.25)]);
    expect(s.liked.first.$1.title, 'Música a', reason: 'as músicas vêm completas da playlist');
    expect(s.avoid.map((x) => (x.id, x.title, x.artist, x.artistId, x.coverArt)),
        [('p', 'Música p', 'Artista p', 'ar-p', 'c-p')]);
    expect(s.saved, DateTime(2026, 11, 7, 10));
    expect(s.played, DateTime(2026, 11, 7, 11));
  });

  test('renomear num, tocar no outro e apagar: os dois acompanham', () async {
    final srv = _Servidor();
    final (_, a) = await _aparelho(srv);
    a.put(_samba());
    await a.sync(force: true);
    final (_, b) = await _aparelho(srv);

    b.rename('smart-1', 'Pagode');
    await b.sync(force: true);
    await a.sync(force: true);
    expect(a.state.single.name, 'Pagode');

    a.touch('smart-1');
    await a.sync(force: true);
    await b.sync(force: true);
    expect(b.state.single.played!.isAfter(DateTime(2026, 11, 7, 11)), isTrue);

    a.remove('smart-1');
    await a.sync(force: true);
    expect(srv.salvos, isEmpty);
    await b.sync(force: true);
    expect(b.state, isEmpty, reason: 'apagado no outro aparelho some daqui');
  });

  test('sem mudança no servidor, não busca as músicas de novo', () async {
    final srv = _Servidor();
    final (_, a) = await _aparelho(srv);
    a.put(_samba());
    await a.sync(force: true);
    final (_, b) = await _aparelho(srv);
    final antes = srv.leituras;
    await b.sync(force: true);
    await b.sync(force: true);
    expect(srv.leituras, antes);
  });

  test('sem rede: guarda aqui e sobe (ou apaga) quando a rede volta', () async {
    final srv = _Servidor();
    final (_, a) = await _aparelho(srv);
    srv.offline = true;
    a.put(_samba());
    await a.sync(force: true);
    expect(a.state, hasLength(1));
    expect(srv.salvos, isEmpty);

    srv.offline = false;
    await a.sync(force: true);
    expect(srv.salvos, hasLength(1));

    srv.offline = true;
    a.remove('smart-1');
    await a.sync(force: true);
    expect(srv.salvos, hasLength(1));
    srv.offline = false;
    await a.sync(force: true);
    expect(srv.salvos, isEmpty);
    expect(a.state, isEmpty);
  });

  test('"Atualizar" troca na mesma playlist; desfazer o apagar cria de novo', () async {
    final srv = _Servidor();
    final (_, a) = await _aparelho(srv);
    a.put(_samba());
    await a.sync(force: true);
    final rid = srv.salvos.single.id;

    // O player cria o salvo de novo, com o mesmo id e sem a playlist.
    a.put(SavedSmart(
      id: 'smart-1',
      name: 'Samba novo',
      liked: [(_s('c'), 2.0), (_s('a'), 1.0)],
      saved: DateTime(2026, 11, 7, 15),
    ));
    await a.sync(force: true);
    expect(srv.salvos.map((p) => p.id), [rid], reason: 'sem playlist duplicada');
    expect(srv.salvos.single.songs, ['c', 'a']);

    final velho = a.state.single;
    a.remove('smart-1');
    await a.sync(force: true);
    expect(srv.salvos, isEmpty);
    a.put(velho);
    await a.sync(force: true);
    expect(srv.salvos, hasLength(1));
    expect(a.state.single.remote, srv.salvos.single.id);
  });

  test('salvos de outro usuário e playlists mexidas em outro app', () async {
    final srv = _Servidor();
    final (_, a) = await _aparelho(srv);
    a.put(_samba());
    await a.sync(force: true);
    // Alguém tirou uma música e pôs outra pelo Navidrome.
    srv.salvos.single
      ..songs = ['b', 'd']
      ..changed = DateTime.utc(2026, 11, 8);
    // Um salvo público de outra pessoa não é desta conta.
    srv.pls['alheia'] = _Pl('alheia', 'Aleatório smart: dela', 'outro', ['c'], DateTime.utc(2026, 11, 8))
      ..comment = srv.salvos.single.comment!.replaceFirst('smart-1', 'smart-9');

    final (_, b) = await _aparelho(srv);
    expect(b.state.single.liked.map((x) => (x.$1.id, x.$2)), [('b', 1.25), ('d', 1.0)],
        reason: 'ímã que saiu da playlist sai; música nova entra com força 1');
  });

  test('os salvos de antes da sincronização sobem sozinhos', () async {
    final srv = _Servidor();
    // Como a v1.7.0 deixava: só no aparelho, sem playlist e sem pendência.
    final prefs = _Prefs()..m['smartSaved.conta'] = jsonEncode([_samba().toJson()]);
    final (_, a) = await _aparelho(srv, prefs: prefs);
    expect(srv.salvos, hasLength(1));
    expect(a.state.single.remote, srv.salvos.single.id);
    final (_, b) = await _aparelho(srv);
    expect(b.state.single.name, 'Samba de domingo');
  });

  test('a aba Playlists não mostra as playlists dos salvos', () async {
    final srv = _Servidor();
    final (c, a) = await _aparelho(srv);
    a.put(_samba());
    await a.sync(force: true);
    await srv.createPlaylist('Festa', songIds: ['a']);
    c.listen(playlistsProvider, (_, _) {});
    final lista = await c.read(playlistsProvider.future);
    expect(lista.map((p) => p.name), ['Festa']);
  });
}
