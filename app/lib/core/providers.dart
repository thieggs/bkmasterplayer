import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter/material.dart' show ThemeMode;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/accounts.dart';
import '../data/lastfm.dart';
import '../data/local/local_provider.dart';
import '../data/settings.dart';
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

  /// Perfil visual completo (aparência + layout) para exportar.
  String exportProfile() {
    final s = ref.read(settingsProvider);
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'player_musica',
      'version': 1,
      'ui': state.toJson(),
      'theme': {
        'themeMode': s.themeMode.name,
        'seedColor': s.seedColor,
        'dynamicColorFromCover': s.dynamicColorFromCover,
        'uiScale': s.uiScale,
      },
    });
  }

  /// Importa um perfil (lança FormatException se inválido).
  void importProfile(String text) {
    final j = jsonDecode(text);
    if (j is! Map || j['ui'] is! Map) throw const FormatException('perfil inválido');
    update((_) => UiPrefs.fromJson(Map<String, dynamic>.from(j['ui'] as Map)));
    final t = j['theme'];
    if (t is Map) {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(
            themeMode: ThemeMode.values.asNameMap()[t['themeMode']] ?? s.themeMode,
            seedColor: t['seedColor'] is int ? t['seedColor'] as int : s.seedColor,
            dynamicColorFromCover: t['dynamicColorFromCover'] is bool ? t['dynamicColorFromCover'] as bool : s.dynamicColorFromCover,
            uiScale: (t['uiScale'] as num?)?.toDouble().clamp(0.8, 1.5) ?? s.uiScale,
          ));
    }
  }
}

final uiPrefsProvider = NotifierProvider<UiPrefsNotifier, UiPrefs>(UiPrefsNotifier.new);

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
      await local.connect();
      return Session(account: account, provider: local);
    }
    final auth = await store.auth(account.id);
    if (auth == null) return null;
    final provider = SubsonicProvider(
      accountId: account.id,
      client: SubsonicClient(baseUrl: account.baseUrl, localUrl: account.localUrl, auth: auth),
    );
    try {
      // Em casa, já começa pelo endereço local (teste de ~1,5 s no máximo).
      if (provider.hasLocalAddress) await provider.checkLocalAddress();
      await provider.connect();
      return Session(account: account, provider: provider);
    } on SubsonicException catch (e) {
      if (e.isAuthError) return null;
      return Session(account: account, provider: provider, offlineReason: e.message);
    }
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
    final auth = SubsonicAuth.fromPassword(username, password);
    final raw = url.trim();
    final candidates = raw.contains('://') ? [raw] : ['https://$raw', 'http://$raw'];
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
        name: (name == null || name.trim().isEmpty) ? '${info.type} — ${Uri.parse(client.baseUrl).host}' : name.trim(),
        baseUrl: client.remoteUrl,
        username: username,
        localUrl: client.localUrl,
      );
      await ref.read(accountStoreProvider).save(account, auth);
      if (provider.hasLocalAddress) unawaited(provider.checkLocalAddress());
      state = AsyncData(Session(account: account, provider: provider));
      return;
    }
    throw error!;
  }

  static const localBaseUrl = 'local:';

  /// Entra sem servidor, com as músicas das [folders] do aparelho. Devolve
  /// quantas músicas encontrou.
  Future<int> loginLocal(List<String> folders) async {
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(localFolders: folders));
    final local = LocalProvider(
      supportDir: ref.read(supportDirProvider).path,
      folders: folders,
      lastFm: ref.read(lastFmProvider),
    );
    await local.connect();
    final count = await local.rescan();
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
final musicProvider = Provider<MusicProvider>((ref) {
  final s = ref.watch(sessionProvider).value;
  if (s == null) throw StateError('sem sessão');
  return s.provider;
});

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

// ---- Dados da biblioteca ----

typedef AlbumListQuery = ({AlbumListType type, int size, String? genre});

final albumListProvider = FutureProvider.autoDispose.family<List<Album>, AlbumListQuery>((ref, q) {
  return ref.watch(musicProvider).albumList(q.type, size: q.size, genre: q.genre);
});

final albumProvider = FutureProvider.autoDispose.family<Album, String>((ref, id) {
  return ref.watch(musicProvider).album(id);
});

final artistsProvider = FutureProvider.autoDispose<List<Artist>>((ref) {
  return ref.watch(musicProvider).artists();
});

final artistProvider = FutureProvider.autoDispose.family<Artist, String>((ref, id) {
  return ref.watch(musicProvider).artist(id);
});

final artistInfoProvider = FutureProvider.autoDispose.family<ArtistInfo?, String>((ref, id) {
  return ref.watch(musicProvider).artistInfo(id);
});

final topSongsProvider = FutureProvider.autoDispose.family<List<Song>, String>((ref, artistName) {
  return ref.watch(musicProvider).topSongs(artistName);
});

final playlistsProvider = FutureProvider.autoDispose<List<Playlist>>((ref) {
  return ref.watch(musicProvider).playlists();
});

final playlistProvider = FutureProvider.autoDispose.family<Playlist, String>((ref, id) {
  return ref.watch(musicProvider).playlist(id);
});

final genresProvider = FutureProvider.autoDispose<List<Genre>>((ref) {
  return ref.watch(musicProvider).genres();
});

final genreSongsProvider = FutureProvider.autoDispose.family<List<Song>, String>((ref, genre) {
  return ref.watch(musicProvider).songsByGenre(genre, count: 200);
});

final starredSongsProvider = FutureProvider.autoDispose<List<Song>>((ref) {
  return ref.watch(musicProvider).starredSongs();
});

final searchProvider = FutureProvider.autoDispose.family<SearchResult, String>((ref, query) async {
  if (query.trim().isEmpty) return const SearchResult();
  // Pequeno atraso: evita uma busca por tecla digitada.
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (cancelled) return const SearchResult();
  return ref.watch(musicProvider).search(query);
});

final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, Song>((ref, song) {
  return ref.watch(musicProvider).lyrics(song);
});
