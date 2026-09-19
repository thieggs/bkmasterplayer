import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'connect/connect_service.dart';
import 'core/providers.dart';
import 'domain/models.dart';
import 'jam/jam_page.dart';
import 'l10n/l10n.dart';
import 'player/player_controller.dart';
import 'ui/pages/album_page.dart';
import 'ui/pages/albums_page.dart';
import 'ui/pages/artists_page.dart';
import 'ui/pages/equalizer_page.dart';
import 'ui/pages/genres_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/library_page.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/offline_page.dart';
import 'ui/pages/playlists_page.dart';
import 'ui/pages/search_page.dart';
import 'player/commands.dart';
import 'ui/remote_volume.dart';
import 'ui/pages/settings/look_page.dart';
import 'ui/pages/settings/sections.dart';
import 'ui/pages/settings/settings_page.dart';
import 'ui/pages/songs_page.dart';
import 'ui/player/now_playing_page.dart';
import 'ui/shell.dart';
import 'ui/theme/app_background.dart';
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
      // A Jam funciona sem conta (o convidado usa as músicas do dono).
      if (!loggedIn && state.matchedLocation == '/jam') return null;
      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/jam', builder: (_, _) => const JamPage()),
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
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsPage(),
            routes: [
              GoRoute(
                path: 'look',
                builder: (_, _) => const LookPage(),
                routes: [GoRoute(path: ':part', builder: (_, state) => lookPartPage(state.pathParameters['part']!))],
              ),
              GoRoute(path: ':section', builder: (_, state) => settingsSectionPage(state.pathParameters['section']!)),
            ],
          ),
          GoRoute(path: '/equalizer', builder: (_, _) => const EqualizerPage()),
          GoRoute(path: '/customize', redirect: (_, _) => '/settings/look'),
          GoRoute(path: '/offline', builder: (_, _) => const OfflinePage()),
          GoRoute(path: '/offline/:id', builder: (_, state) => OfflineCollectionPage(id: state.pathParameters['id']!)),
        ],
      ),
    ],
  );
});

/// Esquema de cores: da cor base ou extraído da capa atual, no estilo da
/// personalização gráfica.
final _schemeProvider = FutureProvider.family<ColorScheme, Brightness>((ref, brightness) async {
  // Só as escolhas de cor recalculam a paleta (não os botões, as abas…).
  ref.watch(uiPrefsProvider.select((p) => (p.colorSource, p.seed, p.variant, p.contrast, p.amoled, jsonEncode(p.colors))));
  final ui = ref.read(uiPrefsProvider);
  final fallback = AppTheme.seeded(ui, brightness);
  if (ui.colorSource != 'cover') return fallback;
  final cover = ref.watch(playerProvider.select((p) => p.current?.song.coverArt));
  if (cover == null) return fallback;
  if (isFileCover(cover)) {
    try {
      return await AppTheme.fromImage(ResizeImage(FileImage(File(cover)), width: 128), ui, brightness);
    } catch (_) {
      return fallback;
    }
  }
  final session = ref.watch(sessionProvider).value;
  if (session == null) return fallback;
  final uri = session.provider.coverUri(cover, size: 128);
  final key = session.provider.coverCacheKey(cover, size: 128);
  if (uri == null || key == null) return fallback;
  final dir = ref.watch(cacheDirProvider);
  try {
    return await AppTheme.fromImage(
      CoverImageProvider(url: uri.toString(), cacheKey: key, cacheDir: '${dir.path}/ui_covers'),
      ui,
      brightness,
    );
  } catch (_) {
    return fallback;
  }
});

class PlayerApp extends ConsumerStatefulWidget {
  const PlayerApp({super.key});

  @override
  ConsumerState<PlayerApp> createState() => _PlayerAppState();
}

class _PlayerAppState extends ConsumerState<PlayerApp> {
  static const _system = MethodChannel('bkplayer/system');

  @override
  void initState() {
    super.initState();
    // Notificações do Android abrem uma tela (ex.: a Jam).
    _system.setMethodCallHandler((call) async {
      if (call.method == 'openRoute') ref.read(_routerProvider).push('${call.arguments}');
      // O canal aceita um tratador só, então o volume é repassado daqui.
      DeviceVolume.onNative(call);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final route = await _system.invokeMethod<String>('launchRoute');
        if (route != null) ref.read(_routerProvider).push(route);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(_routerProvider);
    final settings = ref.watch(settingsProvider);
    // Mantém o controlador vivo desde o início (recebe eventos do motor).
    ref.watch(playerProvider.select((_) => 0));
    // Connect: anuncia este aparelho e aceita controle enquanto o app roda.
    ref.listen(connectProvider, (_, _) {});
    // Conta com portal: segue o endereço do túnel mesmo em casa (ver PortalRefreshNotifier).
    ref.listen(portalRefreshProvider, (_, _) {});
    // Comandos automáticos (ex.: volume no mínimo pausa).
    ref.listen(commandsProvider, (_, _) {});
    final ui = ref.watch(uiPrefsProvider);
    final light = ref.watch(_schemeProvider(Brightness.light)).value ?? AppTheme.seeded(ui, Brightness.light);
    final dark = ref.watch(_schemeProvider(Brightness.dark)).value ?? AppTheme.seeded(ui, Brightness.dark);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: ThemeMode.values.asNameMap()[ui.themeMode] ?? ThemeMode.dark,
      theme: AppTheme.build(light, prefs: ui),
      darkTheme: AppTheme.build(dark, prefs: ui),
      themeAnimationDuration: ui.animationDuration,
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
        return AppBackground(
          child: MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(ui.uiScale)),
            child: RemoteVolumeOverlay(child: child!),
          ),
        );
      },
    );
  }
}
