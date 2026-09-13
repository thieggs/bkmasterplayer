import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/accounts.dart';
import '../data/settings.dart';
import '../data/subsonic/subsonic_client.dart';
import '../data/subsonic/subsonic_provider.dart';
import '../domain/models.dart';
import '../domain/music_provider.dart';
import '../src/rust/api/engine.dart' as engine;

/// Sobrescritos no `main` com as instâncias reais.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final cacheDirProvider = Provider<Directory>((ref) => throw UnimplementedError());

final accountStoreProvider = Provider<AccountStore>((ref) => AccountStore(ref.watch(prefsProvider)));

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.watch(prefsProvider));

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
    if (old.outputDeviceId != s.outputDeviceId) {
      engine.playerSetOutputDevice(deviceId: s.outputDeviceId);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class Session {
  const Session({required this.account, required this.provider, this.offlineReason});
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
    final auth = await store.auth(account.id);
    if (auth == null) return null;
    final provider = SubsonicProvider(
      accountId: account.id,
      client: SubsonicClient(baseUrl: account.baseUrl, auth: auth),
    );
    try {
      await provider.connect();
      return Session(account: account, provider: provider);
    } on SubsonicException catch (e) {
      if (e.isAuthError) return null;
      return Session(account: account, provider: provider, offlineReason: e.message);
    }
  }

  /// Faz login. Lança [SubsonicException] se falhar.
  Future<void> login({required String url, required String username, required String password, String? name}) async {
    final auth = SubsonicAuth.fromPassword(username, password);
    final client = SubsonicClient(baseUrl: url, auth: auth);
    final id = '${client.baseUrl}|$username'.hashCode.toUnsigned(32).toRadixString(16);
    final provider = SubsonicProvider(accountId: id, client: client);
    final info = await provider.connect();
    final account = ServerAccount(
      id: id,
      name: (name == null || name.trim().isEmpty) ? '${info.type} — ${Uri.parse(client.baseUrl).host}' : name.trim(),
      baseUrl: client.baseUrl,
      username: username,
    );
    await ref.read(accountStoreProvider).save(account, auth);
    state = AsyncData(Session(account: account, provider: provider));
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
