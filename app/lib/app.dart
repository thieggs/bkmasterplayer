import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'connect/connect_service.dart';
import 'core/providers.dart';
import 'domain/models.dart';
import 'l10n/l10n.dart';
import 'player/player_controller.dart';
import 'ui/pages/album_page.dart';
import 'ui/pages/albums_page.dart';
import 'ui/pages/artists_page.dart';
import 'ui/pages/customize_page.dart';
import 'ui/pages/equalizer_page.dart';
import 'ui/pages/genres_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/library_page.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/offline_page.dart';
import 'ui/pages/playlists_page.dart';
import 'ui/pages/search_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/songs_page.dart';
import 'ui/player/now_playing_page.dart';
import 'ui/shell.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/cover_art.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: ref.read(uiPrefsProvider).startPage,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      if (session.isLoading && !session.hasValue) return null;
      final loggedIn = session.value != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/now-playing',
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: NowPlayingPage(showLyrics: state.uri.queryParameters['lyrics'] == '1'),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomePage()),
          GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
          GoRoute(
            path: '/albums',
            builder: (_, state) => AlbumsPage(
              key: ValueKey(state.uri.toString()),
              initialSort: AlbumListType.values.asNameMap()[state.uri.queryParameters['sort']],
              genre: state.uri.queryParameters['genre'],
            ),
          ),
          GoRoute(path: '/album/:id', builder: (_, state) => AlbumPage(id: state.pathParameters['id']!)),
          GoRoute(path: '/artists', builder: (_, _) => const ArtistsPage()),
          GoRoute(path: '/artist/:id', builder: (_, state) => ArtistPage(id: state.pathParameters['id']!)),
          GoRoute(path: '/playlists', builder: (_, _) => const PlaylistsPage()),
          GoRoute(path: '/playlist/:id', builder: (_, state) => PlaylistPage(id: state.pathParameters['id']!)),
          GoRoute(path: '/songs', builder: (_, _) => const SongsPage()),
          GoRoute(path: '/genres', builder: (_, _) => const GenresPage()),
          GoRoute(
            path: '/genre/:name',
            builder: (_, state) => GenreSongsPage(genre: state.pathParameters['name']!),
          ),
          GoRoute(path: '/favorites', builder: (_, _) => const FavoritesPage()),
          GoRoute(path: '/search', builder: (_, state) => SearchPage(initial: state.uri.queryParameters['q'] ?? '')),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          GoRoute(path: '/equalizer', builder: (_, _) => const EqualizerPage()),
          GoRoute(path: '/customize', builder: (_, _) => const CustomizePage()),
          GoRoute(path: '/offline', builder: (_, _) => const OfflinePage()),
          GoRoute(path: '/offline/:id', builder: (_, state) => OfflineCollectionPage(id: state.pathParameters['id']!)),
        ],
      ),
    ],
  );
});

/// Esquema de cores: fixo pela cor de destaque ou extraído da capa atual.
final _schemeProvider = FutureProvider.family<ColorScheme, Brightness>((ref, brightness) async {
  final s = ref.watch(settingsProvider);
  final custom = ref.watch(uiPrefsProvider.select((p) => p.customColor));
  final fallback = AppTheme.seeded(custom ?? s.seedColor, brightness);
  if (!s.dynamicColorFromCover) return fallback;
  final cover = ref.watch(playerProvider.select((p) => p.current?.song.coverArt));
  if (cover == null) return fallback;
  final session = ref.watch(sessionProvider).value;
  if (session == null) return fallback;
  final uri = session.provider.coverUri(cover, size: 128);
  final key = session.provider.coverCacheKey(cover, size: 128);
  if (uri == null || key == null) return fallback;
  final dir = ref.watch(cacheDirProvider);
  try {
    return await ColorScheme.fromImageProvider(
      provider: CoverImageProvider(url: uri.toString(), cacheKey: key, cacheDir: '${dir.path}/ui_covers'),
      brightness: brightness,
    );
  } catch (_) {
    return fallback;
  }
});

class PlayerApp extends ConsumerWidget {
  const PlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    final settings = ref.watch(settingsProvider);
    // Mantém o controlador vivo desde o início (recebe eventos do motor).
    ref.watch(playerProvider.select((_) => 0));
    // Connect: anuncia este aparelho e aceita controle enquanto o app roda.
    ref.listen(connectProvider, (_, _) {});
    final ui = ref.watch(uiPrefsProvider);
    final seed = ui.customColor ?? settings.seedColor;
    final light = ref.watch(_schemeProvider(Brightness.light)).value ?? AppTheme.seeded(seed, Brightness.light);
    final dark = ref.watch(_schemeProvider(Brightness.dark)).value ?? AppTheme.seeded(seed, Brightness.dark);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: settings.themeMode,
      theme: AppTheme.build(light, prefs: ui),
      darkTheme: AppTheme.build(dark, prefs: ui),
      themeAnimationDuration: const Duration(milliseconds: 600),
      locale: settings.locale == null ? null : Locale(settings.locale!),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(settings.uiScale)),
          child: child!,
        );
      },
    );
  }
}
