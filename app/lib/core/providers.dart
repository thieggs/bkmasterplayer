import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../connect/connect_auth.dart';
import '../data/accounts.dart';
import '../data/lastfm.dart';
import '../data/local/local_provider.dart';
import '../data/online_meta.dart';
import '../data/portal.dart';
import '../data/settings.dart';
import '../data/theme_library.dart';
import '../data/ui_prefs.dart';
import '../data/subsonic/subsonic_client.dart';
import '../data/subsonic/subsonic_provider.dart';
import '../domain/models.dart';
import '../domain/music_provider.dart';
import '../player/automix.dart';
import '../src/rust/api/engine.dart' as engine;

/// Sobrescritos no `main` com as instâncias reais.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final cacheDirProvider = Provider<Directory>((ref) => throw UnimplementedError());
final supportDirProvider = Provider<Directory>((ref) => throw UnimplementedError());

final accountStoreProvider = Provider<AccountStore>((ref) => AccountStore(ref.watch(prefsProvider)));

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.watch(prefsProvider));

  /// Troca a saída de áudio; só salva se o motor conseguir abrir o dispositivo.
  Future<void> setOutputDevice(String? id) async {
    await engine.playerSetOutputDevice(deviceId: id);
    update((s) => id == null ? s.copyWith(clearOutputDevice: true) : s.copyWith(outputDeviceId: id));
  }

  void update(AppSettings Function(AppSettings s) change) {
    final old = state;
    state = change(state);
    state.save(ref.read(prefsProvider));
    _apply(old, state);
  }

  void _apply(AppSettings old, AppSettings s) {
    if (old.notifications != s.notifications) {
      engine.playerSetNotifications(enabled: s.notifications);
    }
    if (old.cacheLimitMb != s.cacheLimitMb) {
      engine.playerSetCacheLimit(limitMb: s.cacheLimitMb);
    }
    if (old.downloadParallel != s.downloadParallel) {
      engine.playerOfflineSetParallel(parallel: s.downloadParallel);
    }
    final automixChanged = old.automixStyle != s.automixStyle ||
        old.automixMaxTempo != s.automixMaxTempo ||
        old.automixBars != s.automixBars ||
        old.automixMaxSeconds != s.automixMaxSeconds ||
        old.automixUnclearSeconds != s.automixUnclearSeconds ||
        old.automixHarmonic != s.automixHarmonic ||
        old.automixRampBars != s.automixRampBars ||
        old.automixTrimSilence != s.automixTrimSilence ||
        old.analysisModel != s.analysisModel;
    if (automixChanged) applyAutomix(s);
    if (old.eqEnabled != s.eqEnabled || old.eqPreamp != s.eqPreamp || old.eqGains != s.eqGains) applyEq(s);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class UiPrefsNotifier extends Notifier<UiPrefs> {
  @override
  UiPrefs build() => UiPrefs.load(ref.watch(prefsProvider));

  void update(UiPrefs Function(UiPrefs p) change) {
    state = change(state);
    state.save(ref.read(prefsProvider));
  }

  /// Perfil visual completo (aparência + estrutura) como texto.
  String exportProfile() =>
      const JsonEncoder.withIndent('  ').convert({'app': 'player_musica', 'version': 2, 'ui': state.toJson()});

  /// Importa um perfil em texto (lança FormatException se inválido); lê
  /// também os da versão 1.
  void importProfile(String text) {
    final j = jsonDecode(text);
    if (j is! Map || j['ui'] is! Map) throw const FormatException('perfil inválido');
    final ui = Map<String, dynamic>.from(j['ui'] as Map);
    update((_) => UiPrefs.fromJson(j['theme'] is Map ? UiPrefs.mergeLegacy(ui, j['theme'] as Map) : ui));
  }
}

final uiPrefsProvider = NotifierProvider<UiPrefsNotifier, UiPrefs>(UiPrefsNotifier.new);

/// Galeria de temas (prontos + do usuário) e os arquivos/backups deles.
class ThemesNotifier extends AsyncNotifier<List<BkTheme>> {
  late ThemeLibrary lib;

  @override
  Future<List<BkTheme>> build() async {
    lib = ThemeLibrary(ref.watch(supportDirProvider).path);
    await lib.load();
    return lib.all;
  }

  Future<T> _run<T>(Future<T> Function() f) async {
    final r = await f();
    state = AsyncData(lib.all);
    return r;
  }

  /// Aplica um tema. Se o visual atual não está salvo em nenhum tema (foi
  /// mexido à mão), guarda um backup automático antes de trocar.
  Future<void> apply(BkTheme t) async {
    await backupIfUnsaved();
    ref.read(uiPrefsProvider.notifier).update((p) => p.withTheme(t.theme, id: t.id));
  }

  Future<void> backupIfUnsaved() async {
    final ui = ref.read(uiPrefsProvider);
    if (!lib.all.any((t) => ui.sameTheme(t.theme))) await lib.autoBackup(ui);
  }

  /// Salva o visual atual como tema novo (e passa a usá-lo).
  Future<BkTheme> saveCurrent(String name) async {
    final t = await _run(() => lib.add(name, ref.read(uiPrefsProvider).themeJson()));
    ref.read(uiPrefsProvider.notifier).update((p) => p.copyWith(themeId: t.id));
    return t;
  }

  Future<void> overwriteWithCurrent(String id) => _run(() => lib.overwrite(id, ref.read(uiPrefsProvider).themeJson()));
  Future<void> rename(String id, String name) => _run(() => lib.rename(id, name));
  Future<void> delete(String id) => _run(() => lib.delete(id));
  Future<BkTheme> duplicate(BkTheme t, String name) => _run(() => lib.duplicate(t, name));

  /// Importa um arquivo de tema e aplica.
  Future<BkTheme> importAndApply(String text) async {
    final t = await _run(() => lib.importTheme(text));
    await apply(t);
    return t;
  }

  /// Restaura um backup (guarda o estado de agora antes).
  Future<void> restore(String text) async {
    await lib.autoBackup(ref.read(uiPrefsProvider));
    final (theme, id) = await _run(() => lib.restoreBackup(text));
    ref.read(uiPrefsProvider.notifier).update((p) => p.withTheme(theme, id: id));
  }
}

final themesProvider = AsyncNotifierProvider<ThemesNotifier, List<BkTheme>>(ThemesNotifier.new);

/// Last.fm configurado (null = sem chave).
final lastFmProvider = Provider<LastFm?>((ref) {
  final key = ref.watch(settingsProvider.select((s) => s.lastFmApiKey));
  return (key == null || key.trim().isEmpty) ? null : LastFm(key.trim());
});

class Session {
  const Session({required this.account, required this.provider, this.offlineReason});

  /// Músicas do aparelho, sem servidor.
  bool get isLocal => provider is LocalProvider;
  final ServerAccount account;
  final MusicProvider provider;

  /// Preenchido quando não deu pra falar com o servidor (mas a conta existe).
  final String? offlineReason;

  ServerInfo? get info => provider.serverInfo;
}

class SessionNotifier extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final store = ref.watch(accountStoreProvider);
    final account = store.active;
    if (account == null) return null;
    if (account.baseUrl == localBaseUrl) {
      final local = LocalProvider(
        supportDir: ref.read(supportDirProvider).path,
        folders: ref.read(settingsProvider).localFolders,
        lastFm: ref.read(lastFmProvider),
      );
      ref.listen(lastFmProvider, (_, fm) => local.lastFm = fm);
      _watchLocalCovers(local);
      await local.connect();
      if (ref.read(settingsProvider).onlineCovers) unawaited(local.fillMissingCovers());
      return Session(account: account, provider: local);
    }
    final auth = await store.auth(account.id);
    if (auth == null) return null;
    final client = SubsonicClient(baseUrl: account.baseUrl, localUrl: account.localUrl, auth: auth);
    _wirePortal(client, account);
    final provider = SubsonicProvider(accountId: account.id, client: client);
    try {
      // Em casa, já começa pelo endereço local (teste de ~1,5 s no máximo).
      if (provider.hasLocalAddress) await provider.checkLocalAddress();
      await provider.connect();
      if (account.portalUrl == null) unawaited(_discoverPortal(client, account));
      return Session(account: account, provider: provider);
    } on SubsonicException catch (e) {
      if (e.isAuthError) return null;
      return Session(account: account, provider: provider, offlineReason: e.message);
    }
  }

  /// Liga o cliente ao portal da conta, se ela tiver um.
  ///
  /// Quando o endereço principal para de responder, o cliente chama isto; o
  /// portal diz onde o servidor está agora e a conta é atualizada, para o
  /// app já abrir no lugar certo da próxima vez.
  void _wirePortal(SubsonicClient client, ServerAccount account) {
    final portal = account.portalUrl;
    if (portal == null) return;
    client.onPortalLookup = () async {
      final notice = await Portal.fetch(portal, pinnedKey: account.portalKey);
      // Sem passar o cliente: é ele que troca o endereço ao receber a
      // resposta, e só refaz o pedido se perceber a troca.
      await _applyNotice(account, notice);
      return notice.music;
    };
  }

  /// Leva para a conta, para a análise e (se vier) para o cliente o que o
  /// anúncio diz.
  Future<void> _applyNotice(ServerAccount account, PortalNotice notice, {SubsonicClient? client}) async {
    final store = ref.read(accountStoreProvider);
    final saved = store.list().where((x) => x.id == account.id).firstOrNull ?? account;
    if (notice.music != saved.baseUrl) {
      await store.update(saved.copyWith(baseUrl: notice.music));
    }
    client?.useRemote(notice.music);
    _adoptAnalysisServer(notice, previous: saved.baseUrl, portal: saved.portalUrl);
  }

  DateTime _lastPortalRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  /// Pergunta ao portal onde o servidor está, mesmo sem nada ter falhado.
  ///
  /// O cliente de música só pergunta quando falha — e em casa ele usa o
  /// endereço local, que nunca falha. Então, quando o túnel trocava, o
  /// endereço da análise (que passa por ele) ficava velho; o motor desistia
  /// do servidor e o celular voltava a analisar sozinho, que é o que pesa.
  Future<void> refreshPortal({bool force = false}) async {
    final session = state.value;
    final account = session?.account;
    final provider = session?.provider;
    final portal = account?.portalUrl;
    if (account == null || portal == null || provider is! SubsonicProvider) return;
    if (!force && DateTime.now().difference(_lastPortalRefresh) < const Duration(seconds: 30)) return;
    _lastPortalRefresh = DateTime.now();
    try {
      final notice = await Portal.fetch(portal, pinnedKey: account.portalKey);
      await _applyNotice(account, notice, client: provider.client);
    } catch (e) {
      debugPrint('portal: não deu para atualizar: $e');
    }
  }

  /// Aponta a análise do AutoMix para o portal também, para ela funcionar
  /// fora de casa. Regra em [Portal.canReplaceAnalysis]: não passa por cima
  /// de outro servidor público que a pessoa escolheu à mão.
  void _adoptAnalysisServer(PortalNotice notice, {String? previous, String? portal}) {
    final analysis = notice.analysis;
    if (analysis == null) return;
    final current = ref.read(settingsProvider).analysisServer;
    if (current == analysis) return;
    if (current == null || Portal.canReplaceAnalysis(current, previousMusic: previous, portal: portal)) {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(analysisServer: analysis));
    }
  }

  /// Passa a conta a seguir o portal em [portalUrl].
  ///
  /// Antes confere que a conta entra no servidor que o portal indica: se não
  /// entra, é outro servidor, e trocar deixaria a pessoa sem música. Devolve
  /// se adotou.
  Future<bool> _adoptPortal(SubsonicClient client, ServerAccount account, String portalUrl, PortalNotice notice) async {
    if (!await client.answersAt(notice.music)) return false;
    final store = ref.read(accountStoreProvider);
    final saved = store.list().where((x) => x.id == account.id).firstOrNull ?? account;
    final portal = Portal.normalize(portalUrl);
    final updated = saved.copyWith(baseUrl: notice.music, portalUrl: portal, portalKey: notice.key);
    await store.update(updated);
    client.useRemote(notice.music);
    _wirePortal(client, updated);
    _adoptAnalysisServer(notice, previous: saved.baseUrl, portal: portal);
    return true;
  }

  /// Conta salva sem portal: pergunta ao próprio endereço dela se ele é um.
  ///
  /// Quem entrava pelo link do Tailscale antes de o portal existir tem, na
  /// conta, exatamente o endereço do portal — só que o app nunca perguntou.
  /// A chave fica fixada agora, na primeira resposta; a confiança é a mesma
  /// que o endereço já tinha, porque é para ele que a senha vai.
  Future<void> _discoverPortal(SubsonicClient client, ServerAccount account) async {
    try {
      final notice = await Portal.probe(account.baseUrl);
      if (notice == null) return;
      await _adoptPortal(client, account, account.baseUrl, notice);
    } catch (e) {
      debugPrint('portal: não deu para descobrir em ${account.baseUrl}: $e');
    }
  }

  /// A pessoa colou o link de um portal no campo do servidor de análise.
  ///
  /// Usa a análise que ele indica e, se a conta for do mesmo servidor, passa
  /// a conta inteira a seguir o portal. Devolve o anúncio (`null` se o
  /// endereço não é um portal); lança [PortalException] se a chave mudou.
  Future<PortalNotice?> usePortalLink(String url) async {
    final session = state.value;
    final account = session?.account;
    final notice = await Portal.probe(url, pinnedKey: account?.portalKey);
    if (notice == null || notice.analysis == null) return notice;
    final provider = session?.provider;
    if (provider is SubsonicProvider && account != null && account.portalUrl == null) {
      if (await _adoptPortal(provider.client, account, url, notice)) return notice;
    }
    // Outra conta, ou sem conta de servidor: só a análise.
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(analysisServer: notice.analysis));
    return notice;
  }

  /// Faz login. Lança [SubsonicException] se falhar. Sem http(s):// no
  /// endereço, tenta HTTPS primeiro e cai para HTTP se não houver resposta.
  Future<void> login({
    required String url,
    required String username,
    required String password,
    String? name,
    String? localUrl,
  }) async {
    // Chave do Connect: lenta de propósito (PBKDF2), fora da thread da interface.
    final connectKey = await compute(deriveConnectKeyInIsolate, [username, password]);
    final auth = SubsonicAuth.fromPassword(username, password, connectKey: connectKey);
    final raw = url.trim();
    // O endereço colado pode ser um portal (um link fixo que diz onde o
    // servidor está hoje) em vez do servidor em si. Se for, é dele que sai
    // o endereço de verdade — e a chave que o app fixa para não aceitar,
    // depois, um anúncio de outra pessoa.
    final notice = await Portal.probe(raw);
    final candidates = notice != null
        ? [notice.music]
        : raw.contains('://')
            ? [raw]
            : ['https://$raw', 'http://$raw'];
    SubsonicException? error;
    for (final candidate in candidates) {
      final client = SubsonicClient(baseUrl: candidate, localUrl: localUrl, auth: auth);
      final id = '${client.baseUrl}|$username'.hashCode.toUnsigned(32).toRadixString(16);
      final provider = SubsonicProvider(accountId: id, client: client);
      final ServerInfo info;
      try {
        info = await provider.connect();
      } on SubsonicException catch (e) {
        // Um servidor Subsonic respondeu (senha errada etc.): trocar o esquema não adianta.
        if (e.code != null && e.code != 404) rethrow;
        error ??= e;
        continue;
      }
      final account = ServerAccount(
        id: id,
        name: (name == null || name.trim().isEmpty)
            ? (notice?.name.isNotEmpty ?? false ? notice!.name : '${info.type} — ${Uri.parse(client.baseUrl).host}')
            : name.trim(),
        baseUrl: client.remoteUrl,
        username: username,
        localUrl: client.localUrl,
        portalUrl: notice != null ? Portal.normalize(raw) : null,
        portalKey: notice?.key,
      );
      await ref.read(accountStoreProvider).save(account, auth);
      if (notice != null) {
        _wirePortal(client, account);
        _adoptAnalysisServer(notice, portal: account.portalUrl);
      }
      if (provider.hasLocalAddress) unawaited(provider.checkLocalAddress());
      state = AsyncData(Session(account: account, provider: provider));
      return;
    }
    throw error!;
  }

  static const localBaseUrl = 'local:';

  /// Ativa o Connect protegido numa conta que entrou antes dele: confere a
  /// senha pelo token guardado (md5(senha + salt), sem ir ao servidor), deriva
  /// a chave e grava. Não reconecta nem para a música. false = senha errada.
  Future<bool> enableConnect(String password) async {
    final session = state.value;
    final provider = session?.provider;
    if (session == null || provider is! SubsonicProvider) return false;
    final store = ref.read(accountStoreProvider);
    final auth = await store.auth(session.account.id);
    final (user, token, salt) = (auth?.username, auth?.token, auth?.salt);
    if (auth == null || user == null || token == null || salt == null || !auth.matchesPassword(password)) return false;
    final key = await compute(deriveConnectKeyInIsolate, [user, password]);
    await store.save(session.account, SubsonicAuth.token(username: user, token: token, salt: salt, connectKey: key));
    provider.connectKey = key;
    return true;
  }

  /// Capas achadas na internet: recarrega as telas da biblioteca.
  void _watchLocalCovers(LocalProvider local) {
    local.onChanged = () {
      ref.invalidate(albumListProvider);
      ref.invalidate(albumProvider);
      ref.invalidate(artistsProvider);
      ref.invalidate(artistProvider);
      ref.invalidate(searchProvider);
      ref.invalidate(starredSongsProvider);
    };
  }

  /// Entra sem servidor, com as músicas das [folders] do aparelho. Devolve
  /// quantas músicas encontrou.
  Future<int> loginLocal(List<String> folders) async {
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(localFolders: folders));
    final local = LocalProvider(
      supportDir: ref.read(supportDirProvider).path,
      folders: folders,
      lastFm: ref.read(lastFmProvider),
    );
    _watchLocalCovers(local);
    await local.connect();
    final count = await local.rescan();
    if (ref.read(settingsProvider).onlineCovers) unawaited(local.fillMissingCovers());
    const account = ServerAccount(id: LocalProvider.accountIdValue, name: '', baseUrl: localBaseUrl, username: '');
    await ref.read(accountStoreProvider).saveLocal(account);
    state = AsyncData(Session(account: account, provider: local));
    return count;
  }

  /// Define o endereço da rede de casa (null = não usar). Devolve se ele
  /// respondeu agora.
  Future<bool> setLocalUrl(String? url) async {
    final s = state.value;
    if (s == null) return false;
    s.provider.localAddress = url;
    final clean = (url == null || url.trim().isEmpty) ? null : SubsonicClient.normalizeBaseUrl(url);
    final account = s.account.withLocalUrl(clean);
    await ref.read(accountStoreProvider).update(account);
    state = AsyncData(Session(account: account, provider: s.provider, offlineReason: s.offlineReason));
    return clean != null && await s.provider.checkLocalAddress();
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> logout() async {
    final s = state.value;
    if (s != null) await ref.read(accountStoreProvider).remove(s.account.id);
    engine.playerStop();
    state = const AsyncData(null);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

/// Provedor de música da sessão atual (lança se não houver login).
///
/// Só para quem já sabe que há sessão (ações, player). Numa tela que carrega
/// dados, usar [musicaDaSessao]: entrar leva um tempo, e ler daqui nesse
/// intervalo faz a tela mostrar erro em vez de "carregando".
final musicProvider = Provider<MusicProvider>((ref) {
  final s = ref.watch(sessionProvider).value;
  if (s == null) throw StateError('sem sessão');
  return s.provider;
});

/// O provedor de música, esperando a sessão terminar de entrar.
Future<MusicProvider> musicaDaSessao(Ref ref) async {
  final s = await ref.watch(sessionProvider.future);
  if (s == null) throw StateError('sem sessão');
  return s.provider;
}

final serverInfoProvider = Provider<ServerInfo?>((ref) => ref.watch(sessionProvider).value?.info);

/// Usando o endereço da rede de casa agora. Testa de novo quando a rede muda
/// (Wi-Fi/dados), quando o app volta a ficar visível e, fora de casa, de
/// tempos em tempos (para voltar ao local ao chegar).
class EndpointNotifier extends Notifier<bool> {
  @override
  bool build() {
    final p = ref.watch(sessionProvider).value?.provider;
    if (p == null || !p.hasLocalAddress) return false;
    final subs = <StreamSubscription<dynamic>>[
      p.endpointChanges.listen((local) => state = local),
      Connectivity().onConnectivityChanged.listen((_) => p.checkLocalAddress(), onError: (_) {}),
    ];
    final life = AppLifecycleListener(onResume: () => p.checkLocalAddress());
    final timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!p.onLocalAddress) p.checkLocalAddress();
    });
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      life.dispose();
      timer.cancel();
    });
    return p.onLocalAddress;
  }
}

final endpointProvider = NotifierProvider<EndpointNotifier, bool>(EndpointNotifier.new);

/// Mantém a conta em dia com o portal: ao abrir, ao voltar para o app, quando
/// a rede muda e de tempos em tempos. O anúncio é um arquivinho, então
/// perguntar a cada poucos minutos não pesa.
class PortalRefreshNotifier extends Notifier<void> {
  @override
  void build() {
    final account = ref.watch(sessionProvider.select((s) => s.value?.account));
    if (account?.portalUrl == null) return;
    final session = ref.read(sessionProvider.notifier);
    unawaited(session.refreshPortal(force: true));
    final net = Connectivity().onConnectivityChanged.listen((_) => session.refreshPortal(), onError: (_) {});
    final life = AppLifecycleListener(onResume: () => session.refreshPortal());
    final timer = Timer.periodic(const Duration(minutes: 5), (_) => session.refreshPortal());
    ref.onDispose(() {
      net.cancel();
      life.dispose();
      timer.cancel();
    });
  }
}

final portalRefreshProvider = NotifierProvider<PortalRefreshNotifier, void>(PortalRefreshNotifier.new);

// ---- Dados da biblioteca ----

typedef AlbumListQuery = ({AlbumListType type, int size, String? genre});

final albumListProvider = FutureProvider.autoDispose.family<List<Album>, AlbumListQuery>((ref, q) async {
  return (await musicaDaSessao(ref)).albumList(q.type, size: q.size, genre: q.genre);
});

final albumProvider = FutureProvider.autoDispose.family<Album, String>((ref, id) async {
  return (await musicaDaSessao(ref)).album(id);
});

final artistsProvider = FutureProvider.autoDispose<List<Artist>>((ref) async {
  return (await musicaDaSessao(ref)).artists();
});

final artistProvider = FutureProvider.autoDispose.family<Artist, String>((ref, id) async {
  return (await musicaDaSessao(ref)).artist(id);
});

final artistInfoProvider = FutureProvider.autoDispose.family<ArtistInfo?, String>((ref, id) async {
  return (await musicaDaSessao(ref)).artistInfo(id);
});

final topSongsProvider = FutureProvider.autoDispose.family<List<Song>, String>((ref, artistName) async {
  return (await musicaDaSessao(ref)).topSongs(artistName);
});

final playlistsProvider = FutureProvider.autoDispose<List<Playlist>>((ref) async {
  return (await musicaDaSessao(ref)).playlists();
});

final playlistProvider = FutureProvider.autoDispose.family<Playlist, String>((ref, id) async {
  return (await musicaDaSessao(ref)).playlist(id);
});

final genresProvider = FutureProvider.autoDispose<List<Genre>>((ref) async {
  return (await musicaDaSessao(ref)).genres();
});

final genreSongsProvider = FutureProvider.autoDispose.family<List<Song>, String>((ref, genre) async {
  return (await musicaDaSessao(ref)).songsByGenre(genre, count: 200);
});

final starredSongsProvider = FutureProvider.autoDispose<List<Song>>((ref) async {
  return (await musicaDaSessao(ref)).starredSongs();
});

final searchProvider = FutureProvider.autoDispose.family<SearchResult, String>((ref, query) async {
  if (query.trim().isEmpty) return const SearchResult();
  // Pequeno atraso: evita uma busca por tecla digitada.
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (cancelled) return const SearchResult();
  return (await musicaDaSessao(ref)).search(query);
});

/// Letra: do servidor (ou .lrc ao lado do arquivo); se faltar, da internet.
final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, Song>((ref, song) async {
  Lyrics? own;
  try {
    own = await (await musicaDaSessao(ref)).lyrics(song);
  } catch (_) {}
  if (own != null && own.lines.isNotEmpty) return own;
  final s = ref.read(settingsProvider);
  if (!s.onlineLyrics) return own;
  return OnlineLyrics(cacheDir: ref.read(supportDirProvider).path, musixmatchKey: s.musixmatchKey).fetch(song);
});
