import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../domain/models.dart';
import '../domain/music_provider.dart';
import 'subsonic/subsonic_client.dart';

/// Um aleatório smart salvo: o estilo que ele tinha aprendido, com um nome,
/// para voltar a ele pela aba "Aleatórios smart" (pedido do usuário,
/// 07/11/2026).
///
/// O que se guarda é o que puxava e o que afastava na hora de salvar — os
/// ímãs com a força de cada um (já descontado o tempo e o que cada um
/// acertou) e as puladas que ainda valiam. Ao voltar, o modo recomeça dali e
/// continua aprendendo (ver `SmartSession.restore`). As marcas dos botões "+"
/// e "−" ficam de fora: elas valem em todo aleatório smart.
///
/// **No servidor** (para valer em todo aparelho da conta): uma playlist
/// privada por salvo, com os ímãs como músicas, na ordem, e o resto no
/// comentário, depois de [marker] — ver [remoteComment] e [fromPlaylist].
/// O [id] vai junto e é o mesmo em todo aparelho; [remote] é o id da
/// playlist.
@immutable
class SavedSmart {
  const SavedSmart({
    required this.id,
    required this.name,
    required this.liked,
    this.avoid = const [],
    required this.saved,
    this.played,
    this.remote,
    this.remoteChanged,
  });

  final String id;
  final String name;

  /// Os ímãs, do mais forte para o mais fraco.
  final List<(Song, double)> liked;

  /// As puladas que ainda afastavam.
  final List<Song> avoid;

  /// Quando foi salvo (ou atualizado).
  final DateTime saved;

  /// Quando foi tocado pela última vez.
  final DateTime? played;

  /// A playlist que o guarda no servidor (nulo = ainda não subiu).
  final String? remote;

  /// O "alterado em" da playlist quando foi lida: igual ao do servidor, não
  /// precisa ler de novo. Nulo depois que este aparelho mexeu nela.
  final DateTime? remoteChanged;

  /// Marca no comentário da playlist: é por ela que se reconhece um salvo.
  static const marker = 'bk-smart/1 ';

  /// No nome da playlist, para quem a vê em outro app ou no Navidrome.
  static const namePrefix = 'Aleatório smart: ';

  /// Puladas que vão para o servidor: o comentário vai na URL.
  static const maxRemoteAvoid = 40;

  /// Até quatro capas diferentes dos ímãs, para o mosaico da lista.
  List<String> get covers {
    final out = <String>[];
    for (final (s, _) in liked) {
      final c = s.coverArt;
      if (c != null && !out.contains(c)) out.add(c);
      if (out.length == 4) break;
    }
    return out;
  }

  /// Os primeiros [n] artistas dos ímãs, sem repetir.
  List<String> artists(int n) {
    final out = <String>[];
    for (final (s, _) in liked) {
      final a = s.displayArtist.trim();
      if (a.isNotEmpty && !out.contains(a)) out.add(a);
      if (out.length == n) break;
    }
    return out;
  }

  /// Nome sugerido: os artistas que mais puxam.
  static String suggestName(List<(Song, double)> liked) =>
      SavedSmart(id: '', name: '', liked: liked, saved: DateTime(2000)).artists(3).join(', ');

  SavedSmart copyWith({String? name, DateTime? played, String? remote, DateTime? remoteChanged, bool mexeu = false}) =>
      SavedSmart(
        id: id,
        name: name ?? this.name,
        liked: liked,
        avoid: avoid,
        saved: saved,
        played: played ?? this.played,
        remote: remote ?? this.remote,
        remoteChanged: mexeu ? null : (remoteChanged ?? this.remoteChanged),
      );

  /// Mesmo conteúdo (o que sobe para o servidor), sem olhar onde está.
  bool sameContent(SavedSmart o) =>
      name == o.name &&
      saved == o.saved &&
      played == o.played &&
      identical(liked, o.liked) &&
      identical(avoid, o.avoid);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'liked': [
          for (final (s, w) in liked) {'s': s.toJson(), 'w': w},
        ],
        'avoid': [for (final s in avoid) s.toJson()],
        'saved': saved.millisecondsSinceEpoch,
        if (played != null) 'played': played!.millisecondsSinceEpoch,
        if (remote != null) 'remote': remote,
        if (remoteChanged != null) 'remoteChanged': remoteChanged!.millisecondsSinceEpoch,
      };

  static SavedSmart? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], saved = j['saved'];
    if (id is! String || name is! String || saved is! int) return null;
    final liked = <(Song, double)>[];
    for (final x in (j['liked'] is List ? j['liked'] as List : const [])) {
      if (x is Map && x['s'] is Map && x['w'] is num) {
        liked.add((Song.fromJson(Map<String, dynamic>.from(x['s'] as Map)), (x['w'] as num).toDouble()));
      }
    }
    if (liked.isEmpty) return null;
    final played = j['played'], remote = j['remote'], rc = j['remoteChanged'];
    return SavedSmart(
      id: id,
      name: name,
      liked: liked,
      avoid: [
        for (final x in (j['avoid'] is List ? j['avoid'] as List : const []))
          if (x is Map) Song.fromJson(Map<String, dynamic>.from(x)),
      ],
      saved: DateTime.fromMillisecondsSinceEpoch(saved),
      played: played is int ? DateTime.fromMillisecondsSinceEpoch(played) : null,
      remote: remote is String ? remote : null,
      remoteChanged: rc is int ? DateTime.fromMillisecondsSinceEpoch(rc) : null,
    );
  }

  // ---------------------------------------------------------------- servidor

  /// O nome da playlist no servidor.
  String get remoteName => '$namePrefix$name';

  /// As músicas da playlist: os ímãs, na ordem.
  List<String> get remoteSongs => [for (final (s, _) in liked) s.id];

  /// O comentário da playlist: um aviso para quem a vê em outro app e, depois
  /// de [marker], o que não cabe nas músicas — a força de cada ímã e as
  /// puladas (só o que a sessão usa delas).
  String get remoteComment => 'Salvo pelo BKmasterplayer. Não edite este comentário. $marker${jsonEncode({
        'id': id,
        'w': {for (final (s, w) in liked) s.id: double.parse(w.toStringAsFixed(3))},
        'av': [
          for (final s in avoid.take(maxRemoteAvoid))
            {
              'i': s.id,
              't': s.title,
              if (s.artist != null) 'a': s.artist,
              if (s.artistId != null) 'ai': s.artistId,
              if (s.coverArt != null) 'c': s.coverArt,
            },
        ],
        's': saved.millisecondsSinceEpoch,
        if (played != null) 'p': played!.millisecondsSinceEpoch,
      })}';

  /// A playlist [pl] é um salvo (pelo comentário).
  static bool isRemote(Playlist pl) => pl.comment?.contains(marker) ?? false;

  /// Lê o salvo guardado na playlist [pl], já com as músicas. Ímã que saiu da
  /// playlist (mexeram nela em outro app) sai junto; música posta lá entra
  /// com força 1.
  static SavedSmart? fromPlaylist(Playlist pl) {
    final c = pl.comment;
    final at = c?.indexOf(marker) ?? -1;
    if (c == null || at < 0) return null;
    try {
      final j = jsonDecode(c.substring(at + marker.length));
      if (j is! Map) return null;
      final id = j['id'], s = j['s'], p = j['p'];
      if (id is! String || s is! int) return null;
      final w = j['w'] is Map ? j['w'] as Map : const {};
      final vistos = <String>{};
      final liked = <(Song, double)>[
        for (final song in pl.songs)
          if (vistos.add(song.id)) (song, w[song.id] is num ? (w[song.id] as num).toDouble() : 1.0),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      if (liked.isEmpty) return null;
      final name = pl.name.startsWith(namePrefix) ? pl.name.substring(namePrefix.length) : pl.name;
      return SavedSmart(
        id: id,
        name: name.trim().isEmpty ? suggestName(liked) : name,
        liked: liked,
        avoid: [
          for (final x in (j['av'] is List ? j['av'] as List : const []))
            if (x is Map && x['i'] is String && x['t'] is String)
              Song(
                id: x['i'] as String,
                title: x['t'] as String,
                artist: x['a'] as String?,
                artistId: x['ai'] as String?,
                coverArt: x['c'] as String?,
              ),
        ],
        saved: DateTime.fromMillisecondsSinceEpoch(s),
        played: p is int ? DateTime.fromMillisecondsSinceEpoch(p) : null,
        remote: pl.id,
        remoteChanged: pl.changed,
      );
    } catch (e) {
      debugPrint('aleatório smart salvo na playlist ${pl.id}: $e');
      return null;
    }
  }
}

/// Os aleatórios smart salvos desta conta (os ids das músicas são de cada
/// servidor), do usado por último para o mais antigo.
///
/// **Sincroniza** entre os aparelhos da mesma conta pelo servidor (pedido do
/// usuário, 07/11/2026): cada salvo é uma playlist privada (ver
/// [SavedSmart]). A lista daqui é a cópia do aparelho — abre na hora e
/// funciona sem rede; o que muda aqui sobe logo ([_push]) e, se não deu, na
/// próxima [sync]. Quem apagou em outro aparelho some daqui na [sync].
///
/// **Patente** (ver `player/smart_session.dart`): a lista é só do que a pessoa
/// salvou, na ordem em que usou. Nunca ordenar, filtrar nem sugerir estes
/// itens pela parecença com o gosto dela — isso viraria "várias sementes
/// escolhidas pelo perfil para a pessoa escolher uma" (regra 1).
class SavedSmartNotifier extends Notifier<List<SavedSmart>> {
  /// Teto da lista: com mais que isso sai o usado há mais tempo.
  static const max = 100;

  String? _key;

  /// Ids dos salvos que mudaram aqui e ainda não subiram.
  final _pending = <String>{};

  /// Playlists de salvos apagados aqui que ainda não saíram do servidor.
  final _deleted = <String>{};

  /// Cada mudança daqui conta um: a [sync] que leu o servidor antes dela
  /// não pode passar por cima.
  int _gen = 0;

  /// Uma conversa com o servidor por vez.
  Future<void> _queue = Future.value();

  @override
  List<SavedSmart> build() {
    final account = ref.watch(sessionProvider.select((s) => s.value?.provider.accountId));
    _key = account == null ? null : 'smartSaved.$account';
    _pending.clear();
    _deleted.clear();
    if (_key == null) return const [];
    final prefs = ref.watch(prefsProvider);
    _pending.addAll(prefs.getStringList('$_key.pending') ?? const []);
    _deleted.addAll(prefs.getStringList('$_key.deleted') ?? const []);
    final raw = prefs.getString(_key!);
    var list = const <SavedSmart>[];
    if (raw != null) {
      try {
        final j = jsonDecode(raw);
        list = _sorted([
          if (j is List)
            for (final x in j) ?SavedSmart.fromJson(x),
        ]);
      } catch (e) {
        debugPrint('aleatórios smart salvos: $e');
      }
    }
    // Os que ainda não têm playlist sobem (os salvos antes da v1.8.0, e os
    // que o servidor recusou, que tentam de novo a cada vez que o app abre).
    _pending.addAll([for (final s in list) if (s.remote == null) s.id]);
    // Ao abrir (e ao trocar de conta), traz o que mudou nos outros aparelhos.
    _synced = null;
    Future(sync);
    return list;
  }

  SavedSmart? byId(String id) => state.where((s) => s.id == id).firstOrNull;

  /// Guarda [s]; se já existe um com o mesmo id, ele é trocado (na mesma
  /// playlist do servidor — "Atualizar" cria o salvo de novo, sem ela).
  void put(SavedSmart s) {
    final remote = s.remote ?? byId(s.id)?.remote;
    _deleted.remove(remote);
    _change(s.id, [s.copyWith(remote: remote, mexeu: true), ...state.where((x) => x.id != s.id)]);
  }

  void rename(String id, String name) =>
      _change(id, [for (final s in state) s.id == id ? s.copyWith(name: name, mexeu: true) : s]);

  void remove(String id) {
    final s = byId(id);
    if (s?.remote != null) _deleted.add(s!.remote!);
    _change(id, [for (final s in state) if (s.id != id) s], pending: false);
  }

  /// Tocou agora: sobe para o topo da lista (aqui e nos outros aparelhos).
  void touch(String id) =>
      _change(id, [for (final s in state) s.id == id ? s.copyWith(played: DateTime.now(), mexeu: true) : s]);

  /// Datas comparadas pelo instante, em milissegundos: `==` do DateTime
  /// olha também o fuso, e a cópia daqui guarda só milissegundos.
  static int _ms(DateTime? d) => d?.millisecondsSinceEpoch ?? 0;

  static DateTime _when(SavedSmart s) => s.played != null && s.played!.isAfter(s.saved) ? s.played! : s.saved;

  static List<SavedSmart> _sorted(List<SavedSmart> l) => [...l]..sort((a, b) => _when(b).compareTo(_when(a)));

  void _change(String id, List<SavedSmart> list, {bool pending = true}) {
    _gen++;
    pending ? _pending.add(id) : _pending.remove(id);
    _set(list);
    _push();
  }

  void _set(List<SavedSmart> list) {
    state = _sorted(list).take(max).toList();
    final k = _key;
    if (k == null) return;
    final prefs = ref.read(prefsProvider);
    prefs.setString(k, jsonEncode([for (final s in state) s.toJson()]));
    prefs.setStringList('$k.pending', _pending.toList());
    prefs.setStringList('$k.deleted', _deleted.toList());
  }

  /// O servidor da conta, se dá para falar com ele agora.
  MusicProvider? get _server {
    final s = ref.read(sessionProvider).value;
    if (s == null || s.isLocal || s.offlineReason != null) return null;
    return s.provider;
  }

  String? get _user => ref.read(sessionProvider).value?.account.username;

  /// Enfileira [job] na conversa com o servidor. Sem rede, fica para a
  /// próxima vez (o que mudou continua anotado em [_pending] e [_deleted]).
  Future<void> _enqueue(Future<void> Function(MusicProvider p) job) {
    final key = _key;
    return _queue = _queue.then((_) async {
      try {
        // Trocou de conta (ou o app fechou) enquanto esperava a vez.
        if (!ref.mounted || key != _key) return;
        final p = _server;
        if (p == null) return;
        await job(p);
      } catch (e) {
        debugPrint('aleatórios smart salvos: sincronizar: $e');
      }
    });
  }

  void _push() => _enqueue(_pushNow);

  DateTime? _synced;

  /// Traz o que mudou nos outros aparelhos e manda o que mudou aqui. A aba
  /// chama ao abrir (no máximo a cada 30 s) e ao puxar para baixo ([force]).
  Future<void> sync({bool force = false}) {
    final agora = DateTime.now();
    if (!force && _synced != null && agora.difference(_synced!) < const Duration(seconds: 30)) {
      return _queue;
    }
    _synced = agora;
    return _enqueue(_syncNow);
  }

  Future<void> _pushNow(MusicProvider p) async {
    for (final rid in [..._deleted]) {
      try {
        await p.deletePlaylist(rid);
      } on SubsonicException catch (e) {
        if (e.code == null) rethrow; // sem rede: tenta depois
      }
      _deleted.remove(rid);
      _set(state);
    }
    for (final id in [..._pending]) {
      final s = byId(id);
      if (s == null) {
        _pending.remove(id);
        continue;
      }
      final String rid;
      try {
        rid = await _upload(p, s);
      } on SubsonicException catch (e) {
        if (e.code == null) rethrow;
        // O servidor recusou este (não a rede): não insistir para sempre.
        debugPrint('aleatório smart salvo "${s.name}": o servidor recusou: $e');
        _pending.remove(id);
        continue;
      }
      // Se mudou de novo enquanto subia, fica para a próxima volta.
      final agora = byId(id);
      if (agora != null && agora.sameContent(s)) _pending.remove(id);
      _set([for (final x in state) x.id == id ? x.copyWith(remote: rid) : x]);
    }
  }

  /// Sobe [s] para a playlist dele (ou uma nova, se ainda não tem ou se
  /// apagaram a dele). Devolve o id da playlist.
  Future<String> _upload(MusicProvider p, SavedSmart s) async {
    final rid = s.remote;
    if (rid != null) {
      try {
        await p.updatePlaylist(rid, name: s.remoteName, comment: s.remoteComment, songIds: s.remoteSongs);
        return rid;
      } on SubsonicException catch (e) {
        if (e.code != 70) rethrow; // 70 = não existe mais: cria outra
      }
    }
    final pl = await p.createPlaylist(s.remoteName, songIds: s.remoteSongs);
    await p.updatePlaylist(pl.id, comment: s.remoteComment);
    return pl.id;
  }

  Future<void> _syncNow(MusicProvider p) async {
    // Até três voltas: se mudou algo aqui enquanto lia, lê de novo.
    for (var volta = 0; volta < 3; volta++) {
      await _pushNow(p);
      final gen = _gen;
      final user = _user;
      // A mais nova primeiro: se o mesmo salvo estiver em duas, fica ela.
      final remotas = [
        for (final pl in await p.playlists())
          if (SavedSmart.isRemote(pl) && (pl.owner == null || user == null || pl.owner == user)) pl,
      ]..sort((a, b) => _ms(b.changed).compareTo(_ms(a.changed)));
      final porRemota = {for (final s in state) if (s.remote != null) s.remote!: s};
      final out = <SavedSmart>[];
      final ids = <String>{};
      for (final pl in remotas) {
        final local = porRemota[pl.id];
        // Não mudou desde que leu: não precisa buscar as músicas de novo.
        var s = local != null && local.remoteChanged != null && _ms(local.remoteChanged) == _ms(pl.changed)
            ? local
            : SavedSmart.fromPlaylist(await p.playlist(pl.id));
        if (s == null) continue;
        // O mesmo salvo em duas playlists (subiu duas vezes): fica uma só.
        if (!ids.add(s.id)) {
          _deleted.add(pl.id);
          continue;
        }
        if (s.remote != pl.id) s = s.copyWith(remote: pl.id);
        out.add(s);
      }
      if (gen != _gen) continue;
      // Os que tinham playlist e ela sumiu foram apagados em outro aparelho.
      // Os que nunca subiram (o servidor recusou) ficam só aqui.
      for (final s in state) {
        if (s.remote == null && ids.add(s.id)) out.add(s);
      }
      _set(out);
      if (_deleted.isNotEmpty) await _pushNow(p);
      return;
    }
  }
}

final savedSmartProvider = NotifierProvider<SavedSmartNotifier, List<SavedSmart>>(SavedSmartNotifier.new);
