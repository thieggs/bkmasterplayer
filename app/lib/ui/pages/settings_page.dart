import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../connect/devices_sheet.dart';
import '../../core/providers.dart';
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../../src/rust/api/engine.dart' as engine;
import '../../connect/connect_service.dart';
import '../actions.dart';
import 'automix_settings.dart';

final outputDevicesProvider = FutureProvider.autoDispose<List<engine.OutputDevice>>((ref) => engine.playerOutputDevices());
final cacheSizeProvider = FutureProvider.autoDispose<int>((ref) => engine.playerCacheSize());

const _swatches = [0xFF7C4DFF, 0xFF2196F3, 0xFF00BFA5, 0xFF4CAF50, 0xFFFFC107, 0xFFFF5722, 0xFFE91E63, 0xFF9E9E9E];

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final set = ref.read(settingsProvider.notifier).update;
    final session = ref.watch(sessionProvider).value;
    final info = session?.info;
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    final narrow = MediaQuery.sizeOf(context).width < 600;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Text(l10n.settings, style: theme.textTheme.headlineMedium),
        ),

        // ---- Servidor ----
        section(l10n.server),
        if (session != null)
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
        if (session != null)
          Consumer(builder: (context, ref, _) {
            final onLocal = ref.watch(endpointProvider);
            final local = session.account.localUrl;
            return ListTile(
              leading: Icon(Icons.home_outlined, color: onLocal ? theme.colorScheme.primary : null),
              title: Text(l10n.localAddress),
              subtitle: Text(local == null
                  ? l10n.localAddressNone
                  : '$local • ${onLocal ? l10n.localAddressInUse : l10n.localAddressAway}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editLocalAddress(context, ref, local),
            );
          }),
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

        // ---- Aparência ----
        section(l10n.appearance),
        ListTile(
          leading: const Icon(Icons.brush_outlined),
          title: Text(l10n.customize),
          subtitle: Text(l10n.customizeHint),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/customize'),
        ),
        Builder(builder: (context) {
          final picker = SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem)),
              ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight)),
              ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => set((x) => x.copyWith(themeMode: v.first)),
          );
          // No celular não cabe ao lado do título: vai para baixo.
          return ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(l10n.theme),
            subtitle: narrow ? Padding(padding: const EdgeInsets.only(top: 8), child: picker) : null,
            trailing: narrow ? null : picker,
          );
        }),
        SwitchListTile(
          secondary: const Icon(Icons.palette_outlined),
          title: Text(l10n.dynamicColor),
          subtitle: Text(l10n.dynamicColorHint),
          value: s.dynamicColorFromCover,
          onChanged: (v) => set((x) => x.copyWith(dynamicColorFromCover: v)),
        ),
        ListTile(
          leading: const Icon(Icons.color_lens_outlined),
          title: Text(l10n.accentColor),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final c in _swatches)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => set((x) => x.copyWith(seedColor: c)),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(c),
                      child: s.seedColor == c ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.zoom_in),
          title: Text(l10n.uiScale),
          subtitle: Slider(
            value: s.uiScale,
            min: 0.8,
            max: 1.5,
            divisions: 14,
            label: '${(s.uiScale * 100).round()}%',
            onChanged: (v) => set((x) => x.copyWith(uiScale: v)),
          ),
        ),

        // ---- Reprodução ----
        section(l10n.playback),
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
        if (isDesktop) Consumer(builder: (context, ref, _) {
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

        // ---- AutoMix ----
        section(l10n.automix),
        const AutomixSettingsSection(),

        // ---- Outros aparelhos (Connect) ----
        section(l10n.connectSection),
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

        // ---- Desktop ----
        if (isDesktop) ...[
          section(l10n.desktop),
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

        // ---- Streaming e cache ----
        section(l10n.streaming),
        ListTile(
          leading: const Icon(Icons.high_quality_outlined),
          title: Text(l10n.streamQuality),
          trailing: DropdownButton<String>(
            value: '${s.transcodeFormat ?? 'raw'}:${s.maxBitRate}',
            underline: const SizedBox(),
            items: [
              DropdownMenuItem(value: 'raw:0', child: Text(l10n.qualityOriginal)),
              const DropdownMenuItem(value: 'opus:192', child: Text('Opus 192 kbps')),
              const DropdownMenuItem(value: 'opus:128', child: Text('Opus 128 kbps')),
              const DropdownMenuItem(value: 'mp3:320', child: Text('MP3 320 kbps')),
              const DropdownMenuItem(value: 'mp3:192', child: Text('MP3 192 kbps')),
            ],
            onChanged: (v) {
              if (v == null) return;
              final [fmt, br] = v.split(':');
              set((x) => fmt == 'raw'
                  ? x.copyWith(clearTranscode: true, maxBitRate: 0)
                  : x.copyWith(transcodeFormat: fmt, maxBitRate: int.parse(br)));
            },
          ),
        ),
        Consumer(builder: (context, ref, _) {
          final size = ref.watch(cacheSizeProvider).value ?? 0;
          return ListTile(
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
          );
        }),

        section(l10n.about),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.appTitle),
          subtitle: Text(l10n.aboutText),
        ),
      ],
    );
  }
}

Future<String?> _askText(BuildContext context, {required String title, String? initial, String? hint, String? helper, bool canRemove = false}) {
  final l10n = context.l10n;
  final ctl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        autocorrect: false,
        decoration: InputDecoration(hintText: hint, helperText: helper, helperMaxLines: 3),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        if (canRemove) TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(l10n.remove)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: Text(l10n.save)),
      ],
    ),
  ).whenComplete(ctl.dispose);
}

Future<void> _editLocalAddress(BuildContext context, WidgetRef ref, String? current) async {
  final l10n = context.l10n;
  final text = await _askText(
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

Future<void> _editDeviceName(BuildContext context, WidgetRef ref, String? current) async {
  final text = await _askText(
    context,
    title: context.l10n.deviceName,
    initial: current ?? ref.read(connectProvider.notifier).me?.name,
    canRemove: current != null,
  );
  if (text == null) return;
  final name = text.trim();
  ref.read(settingsProvider.notifier).update((x) => name.isEmpty ? x.copyWith(clearDeviceName: true) : x.copyWith(deviceName: name));
}

