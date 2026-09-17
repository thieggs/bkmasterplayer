import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../connect/connect_service.dart';
import '../../../connect/devices_sheet.dart';
import '../../../src/rust/api/portal.dart' as rust;
import '../../../core/providers.dart';
import '../../../data/lastfm.dart';
import '../../../data/local/local_provider.dart';
import '../../../data/local/local_setup.dart';
import '../../../data/settings.dart';
import '../../../jam/jam_core.dart';
import '../../../jam/jam_permissions.dart';
import '../../../l10n/l10n.dart';
import '../../../src/rust/api/engine.dart' as engine;
import '../../actions.dart';
import '../../widgets/bk_logo.dart';
import '../../widgets/download_manager.dart';
import '../automix_settings.dart';
import 'common.dart';
import 'diagnostics_page.dart';

final outputDevicesProvider = FutureProvider.autoDispose<List<engine.OutputDevice>>((ref) => engine.playerOutputDevices());
final cacheSizeProvider = FutureProvider.autoDispose<int>((ref) => engine.playerCacheSize());

bool get _isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

/// Qualidades do streaming (kbps, MP3; 0 = original). Só MP3: é o que o motor
/// decodifica (Opus, por exemplo, não).
const _qualities = [0, 320, 256, 192, 128];
const _mobileQualities = [0, 256, 192, 128, 96];

/// Tela de uma categoria dos ajustes (`/settings/<id>`).
Widget settingsSectionPage(String id) => switch (id) {
      'account' => const AccountSettingsPage(),
      'playback' => const PlaybackSettingsPage(),
      'automix' => const _AutomixSettingsPage(),
      'storage' => const StorageSettingsPage(),
      'sources' => const SourcesSettingsPage(),
      'devices' => const DevicesSettingsPage(),
      'behavior' => const BehaviorSettingsPage(),
      'desktop' => const DesktopSettingsPage(),
      'diagnostics' => const DiagnosticsPage(),
      _ => const AboutSettingsPage(),
    };

// ---- Conta e servidor ----

class AccountSettingsPage extends ConsumerWidget {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider).value;
    final info = session?.info;
    final local = session != null && session.isLocal;

    return SettingsScaffold(
      title: l10n.settingsAccount,
      children: [
        if (local) ...[
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(l10n.useLocalMusic),
            subtitle: Text(l10n.localSongCount((session.provider as LocalProvider).songCount)),
            trailing: TextButton(
              onPressed: () => ref.read(sessionProvider.notifier).logout(),
              child: Text(l10n.logout),
            ),
          ),
          for (final f in s.localFolders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(f),
              trailing: IconButton(
                tooltip: l10n.remove,
                icon: const Icon(Icons.close),
                onPressed: s.localFolders.length <= 1
                    ? null
                    : () => _setFolders(context, ref, s.localFolders.where((x) => x != f).toList()),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text(l10n.addFolder),
            onTap: () async {
              final picked = await pickFolder(l10n.musicFolder);
              if (picked != null && !s.localFolders.contains(picked) && context.mounted) {
                await _setFolders(context, ref, [...s.localFolders, picked]);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(l10n.rescanLibrary),
            onTap: () => _setFolders(context, ref, s.localFolders),
          ),
        ],
        if (session != null && !local) ...[
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(session.account.name),
            subtitle: Text([
              session.account.baseUrl,
              session.account.username,
              if (info != null) '${info.type} ${info.version}',
            ].join(' • ')),
            trailing: TextButton(
              onPressed: () => ref.read(sessionProvider.notifier).logout(),
              child: Text(l10n.logout),
            ),
          ),
          Consumer(builder: (context, ref, _) {
            final onLocal = ref.watch(endpointProvider);
            final home = session.account.localUrl;
            return ListTile(
              leading: Icon(Icons.home_outlined, color: onLocal ? theme.colorScheme.primary : null),
              title: Text(l10n.localAddress),
              subtitle: Text(home == null
                  ? l10n.localAddressNone
                  : '$home • ${onLocal ? l10n.localAddressInUse : l10n.localAddressAway}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editLocalAddress(context, ref, home),
            );
          }),
          if (session.account.portalUrl != null) ...[
            ListTile(
              leading: const Icon(Icons.travel_explore_outlined),
              title: Text(l10n.portal),
              subtitle: Text('${session.account.portalUrl} • ${l10n.portalHint}'),
            ),
            if (session.account.portalKey != null)
              ListTile(
                leading: const SizedBox(),
                title: Text(l10n.portalFingerprint),
                // Embaixo, não ao lado: são 39 caracteres, e no `trailing`
                // espremiam o título até ele quebrar letra por letra.
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      // Mesmo cálculo do `bk-portal link`, para os dois
                      // textos baterem quando a pessoa confere de viva voz.
                      rust.portalFingerprint(key: session.account.portalKey!),
                      style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 2),
                    Text(l10n.portalFingerprintHint),
                  ],
                ),
              ),
          ],
          if (info != null)
            ListTile(
              leading: Icon(Icons.graphic_eq, color: info.sonicSimilarity ? theme.colorScheme.primary : null),
              title: Text(l10n.audioMuse),
              subtitle: Text(info.sonicSimilarity ? l10n.audioMuseActive : l10n.audioMuseInactive),
            ),
          if (info != null && info.extensions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in info.extensions.entries)
                    Chip(label: Text('${e.key} v${e.value.join(',')}'), visualDensity: VisualDensity.compact),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

Future<void> _editLocalAddress(BuildContext context, WidgetRef ref, String? current) async {
  final l10n = context.l10n;
  final text = await askText(
    context,
    title: l10n.localAddress,
    initial: current,
    hint: 'http://192.168.1.10:4533',
    helper: l10n.localAddressHint,
    canRemove: current != null,
  );
  if (text == null) return;
  final url = text.trim().isEmpty ? null : text.trim();
  final reachable = await ref.read(sessionProvider.notifier).setLocalUrl(url);
  if (url != null && context.mounted) showSnack(context, reachable ? l10n.localAddressOk : l10n.localAddressNotNow);
}

/// Troca as pastas das músicas do aparelho e varre de novo.
Future<void> _setFolders(BuildContext context, WidgetRef ref, List<String> folders) async {
  final session = ref.read(sessionProvider).value;
  final local = session?.provider;
  if (local is! LocalProvider) return;
  ref.read(settingsProvider.notifier).update((x) => x.copyWith(localFolders: folders));
  local.folders = folders;
  final n = await runWithScanProgress(context, local.rescan);
  refreshLibrary(ref);
  if (context.mounted) showSnack(context, context.l10n.localSongCount(n));
}

// ---- Reprodução ----

class PlaybackSettingsPage extends ConsumerWidget {
  const PlaybackSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final local = ref.watch(sessionProvider).value?.isLocal ?? false;

    return SettingsScaffold(
      title: l10n.playback,
      children: [
        ListTile(
          leading: const Icon(Icons.compare_arrows),
          title: Text(l10n.crossfade),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.crossfadeSeconds == 0 ? l10n.crossfadeOff : l10n.seconds(s.crossfadeSeconds)),
              Slider(
                value: s.crossfadeSeconds.toDouble(),
                max: 12,
                divisions: 12,
                label: l10n.seconds(s.crossfadeSeconds),
                onChanged: (v) => set((x) => x.copyWith(crossfadeSeconds: v.round())),
              ),
              Text(s.automixEnabled ? '${l10n.crossfadeHint} ${l10n.crossfadeAutomixNote}' : l10n.crossfadeHint,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.equalizer),
          title: Text(l10n.replayGain),
          trailing: DropdownButton<ReplayGainMode>(
            value: s.replayGainMode,
            underline: const SizedBox(),
            items: [
              DropdownMenuItem(value: ReplayGainMode.off, child: Text(l10n.rgOff)),
              DropdownMenuItem(value: ReplayGainMode.track, child: Text(l10n.rgTrack)),
              DropdownMenuItem(value: ReplayGainMode.album, child: Text(l10n.rgAlbum)),
              DropdownMenuItem(value: ReplayGainMode.auto, child: Text(l10n.rgAuto)),
            ],
            onChanged: (v) => v == null ? null : set((x) => x.copyWith(replayGainMode: v)),
          ),
        ),
        if (s.replayGainMode != ReplayGainMode.off)
          ListTile(
            leading: const SizedBox(),
            title: Text(l10n.preamp),
            subtitle: Slider(
              value: s.replayGainPreampDb,
              min: -12,
              max: 12,
              divisions: 24,
              label: '${s.replayGainPreampDb > 0 ? '+' : ''}${s.replayGainPreampDb.round()} dB',
              onChanged: (v) => set((x) => x.copyWith(replayGainPreampDb: v)),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: Text(l10n.equalizer),
          subtitle: Text(s.eqEnabled ? l10n.on : l10n.off),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/equalizer'),
        ),
        // No celular o sistema escolhe a saída (fone, Bluetooth, alto-falante).
        if (_isDesktop)
          Consumer(builder: (context, ref, _) {
            final devices = ref.watch(outputDevicesProvider).value ?? const [];
            final ids = devices.map((d) => d.id).toSet();
            return ListTile(
              leading: const Icon(Icons.speaker_outlined),
              title: Text(l10n.outputDevice),
              trailing: DropdownButton<String?>(
                value: ids.contains(s.outputDeviceId) ? s.outputDeviceId : null,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.systemDefault)),
                  for (final d in devices)
                    DropdownMenuItem(
                      value: d.id,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(d.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ],
                onChanged: (v) async {
                  try {
                    await ref.read(settingsProvider.notifier).setOutputDevice(v);
                  } catch (e) {
                    if (context.mounted) showSnack(context, l10n.outputDeviceFailed);
                  }
                  ref.invalidate(outputDevicesProvider);
                },
              ),
            );
          }),
        SwitchListTile(
          secondary: const Icon(Icons.sync),
          title: Text(l10n.syncQueue),
          subtitle: Text(l10n.syncQueueHint),
          value: s.syncQueue,
          onChanged: (v) => set((x) => x.copyWith(syncQueue: v)),
        ),
        if (!local)
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: Text(l10n.streamQuality),
            trailing: DropdownButton<int>(
              value: _qualities.contains(s.maxBitRate) ? s.maxBitRate : 0,
              underline: const SizedBox(),
              items: [
                for (final q in _qualities) DropdownMenuItem(value: q, child: Text(q == 0 ? l10n.qualityOriginal : 'MP3 $q kbps')),
              ],
              onChanged: (v) {
                if (v == null) return;
                set((x) => v == 0 ? x.copyWith(clearTranscode: true, maxBitRate: 0) : x.copyWith(transcodeFormat: 'mp3', maxBitRate: v));
              },
            ),
          ),
        if (!local && !_isDesktop)
          ListTile(
            leading: const Icon(Icons.signal_cellular_alt),
            title: Text(l10n.mobileQuality),
            subtitle: Text(l10n.mobileQualityHint),
            trailing: DropdownButton<int>(
              value: _mobileQualities.contains(s.mobileMaxBitRate) ? s.mobileMaxBitRate : 0,
              underline: const SizedBox(),
              items: [
                for (final q in _mobileQualities) DropdownMenuItem(value: q, child: Text(q == 0 ? l10n.sameAsWifi : 'MP3 $q kbps')),
              ],
              onChanged: (v) => v == null ? null : set((x) => x.copyWith(mobileMaxBitRate: v)),
            ),
          ),
      ],
    );
  }
}

// ---- AutoMix ----

class _AutomixSettingsPage extends StatelessWidget {
  const _AutomixSettingsPage();

  @override
  Widget build(BuildContext context) =>
      SettingsScaffold(title: context.l10n.automix, children: const [AutomixSettingsSection()]);
}

// ---- Downloads e cache ----

class StorageSettingsPage extends ConsumerWidget {
  const StorageSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final size = ref.watch(cacheSizeProvider).value ?? 0;
    final local = ref.watch(sessionProvider).value?.isLocal ?? false;

    return SettingsScaffold(
      title: l10n.settingsStorage,
      children: [
        if (!local)
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.openDownloads),
            subtitle: Text(l10n.openDownloadsHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/offline'),
          ),
        if (!local)
          ListTile(
            leading: const Icon(Icons.downloading_outlined),
            title: Text(l10n.dlParallelSetting),
            subtitle: Text(l10n.dlParallelHint),
            trailing: const DownloadParallelStepper(),
          ),
        if (!local && !_isDesktop)
          Consumer(builder: (context, ref, _) {
            final on = ref.watch(settingsProvider.select((s) => s.downloadWifiOnly));
            return SwitchListTile(
              secondary: const Icon(Icons.wifi),
              title: Text(l10n.dlWifiOnly),
              subtitle: Text(l10n.dlWifiOnlyHint),
              value: on,
              onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(downloadWifiOnly: v)),
            );
          }),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: Text(l10n.cache),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.cacheUsage((size / (1024 * 1024)).toStringAsFixed(0), s.cacheLimitMb)),
              Slider(
                value: s.cacheLimitMb.toDouble().clamp(512, 32768),
                min: 512,
                max: 32768,
                divisions: 63,
                label: '${(s.cacheLimitMb / 1024).toStringAsFixed(1)} GB',
                onChanged: (v) => set((x) => x.copyWith(cacheLimitMb: (v / 512).round() * 512)),
              ),
            ],
          ),
          trailing: TextButton(
            onPressed: () async {
              await engine.playerClearCache();
              ref.invalidate(cacheSizeProvider);
            },
            child: Text(l10n.clear),
          ),
        ),
      ],
    );
  }
}

// ---- Letras, capas e Last.fm ----

class SourcesSettingsPage extends ConsumerWidget {
  const SourcesSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;

    return SettingsScaffold(
      title: l10n.settingsSources,
      children: [
        const SettingsSection('Last.fm'),
        ListTile(
          leading: const Icon(Icons.radio_outlined),
          title: Text(l10n.lastFmKey),
          subtitle: Text(s.lastFmApiKey == null ? l10n.lastFmKeyHint : l10n.lastFmKeySet),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editLastFmKey(context, ref, s.lastFmApiKey),
        ),
        ListTile(
          leading: const SizedBox(),
          title: Text(l10n.lastFmCredit),
          subtitle: Text(l10n.lastFmCreditHint),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse('https://www.last.fm'), mode: LaunchMode.externalApplication),
        ),
        SwitchListTile(
          secondary: const SizedBox(),
          title: Text(l10n.lastFmForRadio),
          subtitle: Text(l10n.lastFmForRadioHint),
          value: s.lastFmForRadio && s.lastFmApiKey != null,
          onChanged: s.lastFmApiKey == null ? null : (v) => set((x) => x.copyWith(lastFmForRadio: v)),
        ),
        SettingsSection(l10n.onlineMeta),
        SwitchListTile(
          secondary: const Icon(Icons.lyrics_outlined),
          title: Text(l10n.onlineLyrics),
          subtitle: Text(l10n.onlineLyricsHint),
          value: s.onlineLyrics,
          onChanged: (v) => set((x) => x.copyWith(onlineLyrics: v)),
        ),
        ListTile(
          enabled: s.onlineLyrics,
          leading: const SizedBox(),
          title: Text(l10n.musixmatchKey),
          subtitle: Text(s.musixmatchKey == null ? l10n.musixmatchKeyHint : l10n.lastFmKeySet),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final text = await askText(context,
                title: l10n.musixmatchKey, initial: s.musixmatchKey, helper: l10n.musixmatchKeyHelp, canRemove: s.musixmatchKey != null);
            if (text == null) return;
            set((x) => text.trim().isEmpty ? x.copyWith(clearMusixmatch: true) : x.copyWith(musixmatchKey: text.trim()));
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.image_search_outlined),
          title: Text(l10n.onlineCovers),
          subtitle: Text(l10n.onlineCoversHint),
          value: s.onlineCovers,
          onChanged: (v) {
            set((x) => x.copyWith(onlineCovers: v));
            final local = ref.read(sessionProvider).value?.provider;
            if (v && local is LocalProvider) local.fillMissingCovers();
          },
        ),
      ],
    );
  }
}

Future<void> _editLastFmKey(BuildContext context, WidgetRef ref, String? current) async {
  final l10n = context.l10n;
  final text = await askText(
    context,
    title: l10n.lastFmKey,
    initial: current,
    hint: 'abc123…',
    helper: l10n.lastFmKeyHelp,
    canRemove: current != null,
  );
  if (text == null) return;
  final key = text.trim();
  if (key.isEmpty) {
    ref.read(settingsProvider.notifier).update((x) => x.copyWith(clearLastFm: true));
    return;
  }
  final ok = await LastFm(key).check();
  ref.read(settingsProvider.notifier).update((x) => x.copyWith(lastFmApiKey: key));
  if (context.mounted) showSnack(context, ok ? l10n.lastFmKeyOk : l10n.lastFmKeyBad);
}

// ---- Aparelhos e Festa (a "Jam" do código) ----

class DevicesSettingsPage extends ConsumerWidget {
  const DevicesSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final allowed = ref.watch(jamAllowlistProvider);

    return SettingsScaffold(
      title: l10n.settingsDevices,
      children: [
        SettingsSection(l10n.connectSection),
        SwitchListTile(
          secondary: const Icon(Icons.devices_outlined),
          title: Text(l10n.connectEnable),
          subtitle: Text(l10n.connectEnableHint),
          value: s.connectEnabled,
          onChanged: (v) => set((x) => x.copyWith(connectEnabled: v)),
        ),
        ListTile(
          enabled: s.connectEnabled,
          leading: const SizedBox(),
          title: Text(l10n.deviceName),
          subtitle: Text(s.deviceName ?? ref.read(connectProvider.notifier).me?.name ?? ''),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editDeviceName(context, ref, s.deviceName),
        ),
        ListTile(
          enabled: s.connectEnabled,
          leading: const SizedBox(),
          title: Text(l10n.playOn),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showDevicesSheet(context),
        ),
        SettingsSection(l10n.party),
        if (Platform.isAndroid)
          SwitchListTile(
            secondary: const Icon(Icons.bluetooth_searching),
            title: Text(l10n.jamNearbyAlerts),
            subtitle: Text(l10n.jamNearbyAlertsHint),
            value: s.jamNearbyAlerts,
            onChanged: (v) async {
              set((x) => x.copyWith(jamNearbyAlerts: v));
              await setJamNearbyAlerts(v);
            },
          ),
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(l10n.jamAllowlist),
          subtitle: Text(allowed.isEmpty ? l10n.jamAllowlistEmpty : l10n.jamAllowlistHint),
        ),
        for (final a in allowed)
          ListTile(
            leading: const SizedBox(),
            title: Text(a.name),
            trailing: IconButton(
              tooltip: l10n.remove,
              icon: const Icon(Icons.close),
              onPressed: () => ref.read(jamAllowlistProvider.notifier).remove(a.id),
            ),
          ),
      ],
    );
  }
}

Future<void> _editDeviceName(BuildContext context, WidgetRef ref, String? current) async {
  final text = await askText(
    context,
    title: context.l10n.deviceName,
    initial: current ?? ref.read(connectProvider.notifier).me?.name,
    canRemove: current != null,
  );
  if (text == null) return;
  final name = text.trim();
  ref.read(settingsProvider.notifier).update((x) => name.isEmpty ? x.copyWith(clearDeviceName: true) : x.copyWith(deviceName: name));
}

// ---- Comportamento ----

class BehaviorSettingsPage extends ConsumerWidget {
  const BehaviorSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ui = ref.watch(uiPrefsProvider);
    final setUi = ref.read(uiPrefsProvider.notifier).update;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));

    return SettingsScaffold(
      title: l10n.behavior,
      children: [
        ChoiceTile<String>(
          title: l10n.songTap,
          icon: Icons.touch_app_outlined,
          value: ui.songTap,
          options: {
            'playFromHere': l10n.tapPlayFromHere,
            'playOne': l10n.tapPlayOne,
            'enqueue': l10n.addToQueue,
          },
          onChanged: (v) => setUi((p) => p.copyWith(songTap: v)),
        ),
        ChoiceTile<String>(
          title: l10n.startPage,
          icon: Icons.home_outlined,
          value: ui.startPage,
          options: {
            '/': l10n.home,
            '/albums': l10n.albums,
            '/artists': l10n.artists,
            '/playlists': l10n.playlists,
            '/search': l10n.search,
          },
          onChanged: (v) => setUi((p) => p.copyWith(startPage: v)),
        ),
        if (_isDesktop)
          SwitchListTile(
            secondary: const Icon(Icons.queue_music),
            title: Text(l10n.showQueueOnStart),
            value: ui.showQueue,
            onChanged: (v) => setUi((p) => p.copyWith(showQueue: v)),
          ),
        ChoiceTile<String?>(
          title: l10n.language,
          icon: Icons.translate,
          value: locale,
          options: {null: l10n.languageSystem, 'pt': 'Português', 'en': 'English'},
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .update((s) => v == null ? s.copyWith(clearLocale: true) : s.copyWith(locale: v)),
        ),
        if (_isDesktop)
          ListTile(
            leading: const Icon(Icons.keyboard_outlined),
            title: Text(l10n.shortcuts),
            subtitle: Text(l10n.shortcutsList),
          ),
      ],
    );
  }
}

// ---- Computador ----

class DesktopSettingsPage extends ConsumerWidget {
  const DesktopSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;

    return SettingsScaffold(
      title: l10n.desktop,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.web_asset),
          title: Text(l10n.trayIcon),
          value: s.trayIcon,
          onChanged: (v) => set((x) => x.copyWith(trayIcon: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.close_fullscreen),
          title: Text(l10n.closeToTray),
          subtitle: Text(l10n.closeToTrayHint),
          value: s.closeToTray,
          onChanged: s.trayIcon ? (v) => set((x) => x.copyWith(closeToTray: v)) : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: Text(l10n.trackNotifications),
          subtitle: Text(l10n.trackNotificationsHint),
          value: s.notifications,
          onChanged: (v) => set((x) => x.copyWith(notifications: v)),
        ),
      ],
    );
  }
}

// ---- Sobre ----

class AboutSettingsPage extends ConsumerWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = ref.watch(appVersionProvider).value;
    return SettingsScaffold(
      title: l10n.about,
      children: [
        ListTile(
          leading: const BkLogo(size: 40),
          title: Text(l10n.appTitle),
          subtitle: Text([if (version != null) l10n.appVersion(version), l10n.aboutText].join('\n')),
        ),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(l10n.diagnostics),
          subtitle: Text(l10n.diagnosticsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/diagnostics'),
        ),
        ListTile(
          leading: const Icon(Icons.font_download_outlined),
          title: Text(l10n.fontCredits),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(l10n.licenses),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(context: context, applicationName: l10n.appTitle, applicationIcon: const BkLogo(size: 48)),
        ),
      ],
    );
  }
}
