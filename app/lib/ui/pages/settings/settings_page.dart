import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../data/local/local_provider.dart';
import '../../../data/settings.dart';
import '../../../l10n/l10n.dart';
import 'common.dart';

/// Ajustes: uma lista de categorias; cada uma abre a própria tela.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider).value;
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

    String rg(ReplayGainMode m) => switch (m) {
          ReplayGainMode.off => l10n.rgOff,
          ReplayGainMode.track => l10n.rgTrack,
          ReplayGainMode.album => l10n.rgAlbum,
          ReplayGainMode.auto => l10n.rgAuto,
        };

    final account = session == null
        ? ''
        : session.isLocal
            ? '${l10n.useLocalMusic} • ${l10n.localSongCount((session.provider as LocalProvider).songCount)}'
            : '${session.account.name} • ${session.account.username}';

    Widget item(String id, IconData icon, String title, String subtitle) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings/$id'),
        );

    return SettingsScaffold(
      title: l10n.settings,
      back: null,
      children: [
        item('account', Icons.dns_outlined, l10n.settingsAccount, account),
        item('look', Icons.palette_outlined, l10n.settingsLook, l10n.settingsLookHint),
        item('playback', Icons.play_circle_outline, l10n.playback,
            '${l10n.crossfade}: ${s.crossfadeSeconds == 0 ? l10n.off : l10n.seconds(s.crossfadeSeconds)} • ${l10n.equalizer}: ${s.eqEnabled ? l10n.on : l10n.off} • ReplayGain: ${rg(s.replayGainMode)}'),
        item('automix', Icons.auto_awesome, l10n.automix, s.automixEnabled ? l10n.on : l10n.off),
        item('storage', Icons.storage_outlined, l10n.settingsStorage,
            '${l10n.cache}: ${(s.cacheLimitMb / 1024).toStringAsFixed(1)} GB'),
        item('sources', Icons.lyrics_outlined, l10n.settingsSources,
            'Last.fm: ${s.lastFmApiKey == null ? l10n.off : l10n.on} • ${l10n.onlineLyrics}: ${s.onlineLyrics ? l10n.on : l10n.off}'),
        item('devices', Icons.devices_outlined, l10n.settingsDevices, 'Connect: ${s.connectEnabled ? l10n.on : l10n.off} • ${l10n.party}'),
        item('commands', Icons.bolt_outlined, l10n.commands,
            '${l10n.pauseOnVolumeZero}: ${s.pauseOnVolumeZero ? l10n.on : l10n.off}'),
        item('behavior', Icons.touch_app_outlined, l10n.behavior,
            '${l10n.language}: ${switch (s.locale) { 'pt' => 'Português', 'en' => 'English', _ => l10n.languageSystem }}'),
        if (isDesktop)
          item('desktop', Icons.computer_outlined, l10n.desktop,
              '${l10n.trayIcon}: ${s.trayIcon ? l10n.on : l10n.off} • ${l10n.trackNotifications}: ${s.notifications ? l10n.on : l10n.off}'),
        item('about', Icons.info_outline, l10n.about, l10n.appTitle),
      ],
    );
  }
}
