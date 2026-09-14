import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../core/providers.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../player/player_controller.dart';
import '../src/rust/api/library.dart' as lib;
import '../ui/actions.dart';
import '../ui/widgets/cover_art.dart';
import 'jam_core.dart';
import 'jam_permissions.dart';

/// Pedidos para entrar na Jam: aparece em qualquer tela (o shell chama).
void listenJamRequests(WidgetRef ref, BuildContext context) {
  ref.listen(jamHostProvider.select((s) => s.pending), (prev, next) {
    final shown = prev ?? const [];
    for (final req in next.where((r) => !shown.contains(r))) {
      showJamRequestDialog(context, ref, req);
    }
  });
}

Future<void> showJamRequestDialog(BuildContext context, WidgetRef ref, JamJoinRequest req) async {
  final l10n = context.l10n;
  var always = false;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: const Icon(Icons.groups),
        title: Text(l10n.jamRequestTitle(req.guestName)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.jamRequestBody(req.via == 'wifi' ? l10n.viaWifi : l10n.viaBluetooth)),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: always,
              onChanged: (v) => setState(() => always = v ?? false),
              title: Text(l10n.jamAlwaysAccept),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.reject)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.accept)),
        ],
      ),
    ),
  );
  // Se já foi decidido (tempo esgotado), respond ignora.
  ref.read(jamHostProvider.notifier).respond(req, accept: result ?? false, always: always && (result ?? false));
}

class JamPage extends ConsumerStatefulWidget {
  const JamPage({super.key});

  @override
  ConsumerState<JamPage> createState() => _JamPageState();
}

class _JamPageState extends ConsumerState<JamPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final guest = ref.read(jamGuestProvider);
      if (!ref.read(jamHostProvider).active && guest.phase != JamPhase.joined) {
        await ensureJamPermissions();
        if (ref.read(settingsProvider).jamNearbyAlerts) await setJamNearbyAlerts(true);
        await ref.read(jamGuestProvider.notifier).search();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final host = ref.watch(jamHostProvider);
    final guest = ref.watch(jamGuestProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.party)),
      body: SafeArea(
        child: host.active
            ? const _HostView()
            : switch (guest.phase) {
                JamPhase.joined => const _GuestView(),
                JamPhase.waiting => _Centered(
                    icon: Icons.hourglass_top,
                    text: l10n.jamWaiting(guest.hostName ?? ''),
                    action: TextButton(onPressed: () => ref.read(jamGuestProvider.notifier).leave(), child: Text(l10n.cancel)),
                  ),
                _ => const _OffersView(),
              },
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      );
}

// ---- Procurar / começar ----

class _OffersView extends ConsumerWidget {
  const _OffersView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final guest = ref.watch(jamGuestProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.startJam, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(l10n.startJamHint, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.groups),
                  label: Text(l10n.startJam),
                  onPressed: () async {
                    await ensureJamPermissions();
                    await ref.read(jamHostProvider.notifier).start();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (guest.phase == JamPhase.rejected)
          ListTile(leading: const Icon(Icons.block), title: Text(l10n.jamRejected)),
        if (guest.phase == JamPhase.ended) ListTile(leading: const Icon(Icons.stop_circle_outlined), title: Text(l10n.jamEnded)),
        Row(
          children: [
            Expanded(child: Text(l10n.jamsNearby, style: theme.textTheme.titleMedium)),
            IconButton(
              tooltip: l10n.search,
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(jamGuestProvider.notifier).search(),
            ),
          ],
        ),
        if (guest.offers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Row(
              children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 16),
                Expanded(child: Text(l10n.jamSearching, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        for (final o in guest.offers)
          ListTile(
            leading: Icon(o.via == 'wifi' ? Icons.wifi : Icons.bluetooth),
            title: Text(l10n.jamOf(o.hostName)),
            subtitle: Text(o.via == 'wifi' ? l10n.viaWifi : l10n.viaBluetooth),
            trailing: FilledButton.tonal(
              onPressed: () => ref.read(jamGuestProvider.notifier).join(o),
              child: Text(l10n.join),
            ),
          ),
      ],
    );
  }
}

// ---- Dono ----

class _HostView extends ConsumerWidget {
  const _HostView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final host = ref.watch(jamHostProvider);
    final notifier = ref.read(jamHostProvider.notifier);
    final current = ref.watch(playerProvider.select((s) => s.current));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.groups, color: theme.colorScheme.primary),
            title: Text(l10n.jamOpen),
            subtitle: Text(l10n.jamOpenHint(notifier.jamName)),
            trailing: TextButton(onPressed: notifier.stop, child: Text(l10n.endJam)),
          ),
        ),
        if (current != null)
          ListTile(
            leading: CoverArt(coverArtId: current.song.coverArt, size: 44),
            title: Text(current.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(current.song.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        for (final r in host.pending)
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.person_add),
              title: Text(l10n.jamRequestTitle(r.guestName)),
              trailing: Wrap(spacing: 4, children: [
                IconButton(tooltip: l10n.reject, icon: const Icon(Icons.close), onPressed: () => notifier.respond(r, accept: false)),
                IconButton(tooltip: l10n.accept, icon: const Icon(Icons.check), onPressed: () => notifier.respond(r, accept: true)),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(l10n.jamPeople(host.participants.length), style: theme.textTheme.titleSmall),
        ),
        if (host.participants.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(l10n.jamNobodyYet, style: theme.textTheme.bodySmall),
          ),
        for (final pa in host.participants)
          ListTile(
            leading: Icon(pa.via == 'wifi' ? Icons.wifi : Icons.bluetooth),
            title: Text(pa.name),
            trailing: IconButton(tooltip: l10n.remove, icon: const Icon(Icons.person_remove_outlined), onPressed: () => notifier.kick(pa)),
          ),
      ],
    );
  }
}

// ---- Convidado ----

class _GuestView extends ConsumerWidget {
  const _GuestView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final g = ref.watch(jamGuestProvider);
    final notifier = ref.read(jamGuestProvider.notifier);
    final theme = Theme.of(context);
    final cur = g.current;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.groups, color: theme.colorScheme.primary),
            title: Text(l10n.jamOf(g.hostName ?? '')),
            trailing: TextButton(onPressed: notifier.leave, child: Text(l10n.leaveJam)),
          ),
          if (cur != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _HostCover(id: cur['coverArt'] as String?, size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${cur['title'] ?? ''}', style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${cur['artist'] ?? ''}', style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: g.duration.inMilliseconds == 0 ? 0 : (g.position.inMilliseconds / g.duration.inMilliseconds).clamp(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.skip_previous), onPressed: () => notifier.control('previous')),
              IconButton.filled(
                iconSize: 32,
                icon: Icon(g.playing ? Icons.pause : Icons.play_arrow),
                onPressed: () => notifier.control('toggle'),
              ),
              IconButton(icon: const Icon(Icons.skip_next), onPressed: () => notifier.control('next')),
            ],
          ),
          TabBar(tabs: [Tab(text: l10n.upNext), Tab(text: l10n.jamAdd), Tab(text: l10n.jamMine)]),
          const Expanded(child: TabBarView(children: [_UpNext(), _HostSearch(), _MySongs()])),
        ],
      ),
    );
  }
}

class _HostCover extends ConsumerWidget {
  const _HostCover({required this.id, this.size = 44});
  final String? id;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(jamGuestProvider.notifier);
    return ValueListenableBuilder(
      valueListenable: notifier.coverVersion,
      builder: (context, _, _) {
        final bytes = notifier.cover(id);
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: bytes == null
              ? Container(
                  width: size,
                  height: size,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.music_note, size: size * 0.5),
                )
              : Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
        );
      },
    );
  }
}

class _UpNext extends ConsumerWidget {
  const _UpNext();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final next = ref.watch(jamGuestProvider.select((g) => g.next));
    if (next.isEmpty) return Center(child: Text(l10n.jamQueueEmpty));
    return ListView.builder(
      itemCount: next.length,
      itemBuilder: (context, i) {
        final s = next[i];
        final by = s['by'] as String?;
        return ListTile(
          leading: _HostCover(id: s['coverArt'] as String?),
          title: Text('${s['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [s['artist'] ?? '', if (by != null) l10n.addedBy(by)].where((x) => '$x'.isNotEmpty).join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _HostSearch extends ConsumerStatefulWidget {
  const _HostSearch();
  @override
  ConsumerState<_HostSearch> createState() => _HostSearchState();
}

class _HostSearchState extends ConsumerState<_HostSearch> {
  final _q = TextEditingController();
  List<Song> _results = const [];
  bool _busy = false;
  final _added = <String>{};

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    final r = await ref.read(jamGuestProvider.notifier).searchHost(_q.text);
    if (mounted) {
      setState(() {
        _results = r;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.jamSearchHost,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, i) {
              final s = _results[i];
              final added = _added.contains(s.id);
              return ListTile(
                leading: _HostCover(id: s.coverArt),
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(s.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Icon(added ? Icons.check : Icons.add),
                onTap: added
                    ? null
                    : () {
                        ref.read(jamGuestProvider.notifier).addFromHost(s);
                        setState(() => _added.add(s.id));
                        showSnack(context, l10n.jamAdded(s.title));
                      },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MySongs extends ConsumerStatefulWidget {
  const _MySongs();
  @override
  ConsumerState<_MySongs> createState() => _MySongsState();
}

class _MySongsState extends ConsumerState<_MySongs> {
  final _q = TextEditingController();
  List<Song> _results = const [];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    try {
      final r = await ref.read(musicProvider).search(_q.text, artistCount: 0, albumCount: 0, songCount: 40);
      if (mounted) setState(() => _results = r.songs);
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    final path = picked.firstOrNull?.path;
    if (path == null) return;
    final covers = p.join(ref.read(cacheDirProvider).path, 'jam_covers');
    final t = await lib.libraryReadFile(path: path, coversDir: covers);
    final song = Song(
      id: 'file:$path',
      title: t?.title ?? p.basenameWithoutExtension(path),
      artist: t?.artist,
      album: t?.album,
      duration: t?.durationMs == null ? null : Duration(milliseconds: t!.durationMs!),
      suffix: p.extension(path).replaceFirst('.', '').toLowerCase(),
      coverArt: t?.cover,
      path: path,
    );
    await ref.read(jamGuestProvider.notifier).sendSong(song);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final transfers = ref.watch(jamGuestProvider.select((g) => g.transfers));
    final hasLibrary = ref.watch(sessionProvider).value != null;
    return ListView(
      children: [
        for (final t in transfers.values)
          ListTile(
            dense: true,
            leading: Icon(t.error != null ? Icons.error_outline : (t.done ? Icons.check_circle : Icons.upload)),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: t.error != null
                ? Text(l10n.jamSendFailed)
                : (t.done ? Text(l10n.jamSent) : LinearProgressIndicator(value: t.progress)),
          ),
        ListTile(
          leading: const Icon(Icons.audio_file_outlined),
          title: Text(l10n.jamSendFile),
          subtitle: Text(l10n.jamSendFileHint),
          onTap: _pickFile,
        ),
        if (hasLibrary)
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.jamSearchMine,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        for (final s in _results)
          ListTile(
            leading: CoverArt(coverArtId: s.coverArt, size: 44),
            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [s.displayArtist, if (s.duration != null) formatDuration(s.duration!)].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.send),
            onTap: () {
              ref.read(jamGuestProvider.notifier).sendSong(s);
              showSnack(context, l10n.jamSending(s.title));
            },
          ),
      ],
    );
  }
}

/// Abre a Jam (usado pelo menu de aparelhos e pela biblioteca).
void openJam(BuildContext context) => context.push('/jam');
