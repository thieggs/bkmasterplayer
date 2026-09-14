import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../player/player_controller.dart';
import '../ui/actions.dart';
import 'connect_service.dart';

IconData deviceIcon(String platform) => switch (platform) {
  'android' || 'ios' => Icons.smartphone,
  'macos' || 'windows' || 'linux' => Icons.computer,
  _ => Icons.speaker,
};

/// Botão "Aparelhos": escolher em qual aparelho tocar. Aceso quando o som
/// está saindo de outro aparelho.
class DevicesButton extends ConsumerWidget {
  const DevicesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(playerProvider.select((s) => s.remoteDevice));
    final l10n = context.l10n;
    return IconButton(
      tooltip: remote == null ? l10n.devices : l10n.playingOn(remote),
      icon: Icon(remote == null ? Icons.devices_outlined : Icons.cast_connected),
      color: remote == null ? null : Theme.of(context).colorScheme.primary,
      onPressed: () => showDevicesSheet(context),
    );
  }
}

/// "Tocando em (aparelho)", só no modo remoto.
class RemoteLabel extends ConsumerWidget {
  const RemoteLabel({super.key, this.style});
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(playerProvider.select((s) => s.remoteDevice));
    if (remote == null) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cast_connected, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            context.l10n.playingOn(remote),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (style ?? Theme.of(context).textTheme.labelSmall)?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

Future<void> showDevicesSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _DevicesSheet(),
);

class _DevicesSheet extends ConsumerStatefulWidget {
  const _DevicesSheet();

  @override
  ConsumerState<_DevicesSheet> createState() => _DevicesSheetState();
}

class _DevicesSheetState extends ConsumerState<_DevicesSheet> {
  final _status = <String, DeviceStatus?>{};
  String? _connecting;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final connect = ref.read(connectProvider.notifier);
    await connect.refresh();
    await _loadStatus();
    // Respostas à busca chegam em seguida.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) await _loadStatus();
  }

  Future<void> _loadStatus() async {
    final connect = ref.read(connectProvider.notifier);
    final devices = ref.read(connectProvider).where((d) => d.online).toList();
    final results = await Future.wait(devices.map(connect.status));
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < devices.length; i++) {
        _status[devices[i].id] = results[i];
      }
    });
  }

  Future<void> _select(ConnectDevice d) async {
    final player = ref.read(playerProvider.notifier);
    final s = ref.read(playerProvider);
    if (s.remoteDeviceId == d.id) {
      Navigator.pop(context);
      return;
    }
    setState(() => _connecting = d.id);
    // Se lá já está tocando, só controla; senão a música daqui vai para lá.
    final busy = _status[d.id]?.playing ?? false;
    final transfer = !busy && s.current != null;
    try {
      await player.connectTo(d, transfer: transfer);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _connecting = null);
      showSnack(context, context.l10n.connectFailed(d.name));
    }
  }

  Future<void> _addByAddress() async {
    final l10n = context.l10n;
    final ctl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addDeviceByAddress),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(hintText: '100.64.0.1', helperText: l10n.addDeviceHint, helperMaxLines: 2),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: Text(l10n.ok)),
        ],
      ),
    );
    ctl.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    final d = await ref.read(connectProvider.notifier).addManual(text);
    if (!mounted) return;
    if (d == null) {
      showSnack(context, l10n.deviceNotFound);
    } else {
      await _loadStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final devices = ref.watch(connectProvider);
    final remoteId = ref.watch(playerProvider.select((s) => s.remoteDeviceId));
    final online = devices.where((d) => d.online).toList();
    final offline = devices.where((d) => !d.online && d.manual).toList();
    final me = ref.read(connectProvider.notifier).me;

    Widget check(bool on) =>
        on ? Icon(Icons.check_circle, color: theme.colorScheme.primary) : const SizedBox(width: 24);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(l10n.playOn, style: theme.textTheme.titleLarge),
            ),
            ListTile(
              leading: Icon(deviceIcon(Platform.operatingSystem)),
              title: Text(l10n.thisDevice),
              subtitle: me == null ? null : Text(me.name),
              trailing: check(remoteId == null),
              onTap: () async {
                Navigator.pop(context);
                if (remoteId != null) await ref.read(playerProvider.notifier).playHere();
              },
            ),
            for (final d in online)
              ListTile(
                leading: Icon(deviceIcon(d.platform), color: remoteId == d.id ? theme.colorScheme.primary : null),
                title: Text(d.name),
                subtitle: Text(
                  remoteId == d.id
                      ? l10n.deviceControlling
                      : switch (_status[d.id]) {
                          DeviceStatus(:final title?, :final artist, :final playing) => (playing
                              ? l10n.devicePlaying
                              : l10n.devicePaused)([title, if (artist != null && artist.isNotEmpty) artist].join(' — ')),
                          _ => l10n.deviceIdle,
                        },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _connecting == d.id
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : check(remoteId == d.id),
                onTap: _connecting == null ? () => _select(d) : null,
              ),
            for (final d in offline)
              ListTile(
                enabled: false,
                leading: Icon(deviceIcon(d.platform)),
                title: Text(d.name),
                subtitle: Text('${l10n.deviceOffline} • ${d.address}'),
                trailing: IconButton(
                  tooltip: l10n.remove,
                  icon: const Icon(Icons.close),
                  onPressed: () => ref.read(connectProvider.notifier).removeManual(d.id),
                ),
              ),
            if (online.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(l10n.noDevicesFound, style: theme.textTheme.bodySmall),
              ),
            const Divider(),
            ListTile(leading: const Icon(Icons.add_link), title: Text(l10n.addDeviceByAddress), onTap: _addByAddress),
          ],
        ),
      ),
    );
  }
}
