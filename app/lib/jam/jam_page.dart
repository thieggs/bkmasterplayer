import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../core/format.dart';
import '../connect/connect_service.dart';
import '../core/providers.dart';
import '../domain/models.dart';
import '../l10n/l10n.dart';
import '../player/player_controller.dart';
import '../src/rust/api/library.dart' as lib;
import '../ui/actions.dart';
import '../ui/widgets/cover_art.dart';
import 'jam_bluetooth.dart';
import 'jam_core.dart';
import 'jam_permissions.dart';

/// Avisos da Festa em qualquer tela (o shell chama): pedidos para entrar na
/// deste aparelho e, para o convidado, músicas indo para lá e o fim da Festa.
void listenJamRequests(WidgetRef ref, BuildContext context) {
  ref.listen(jamHostProvider.select((s) => s.pending), (prev, next) {
    final shown = prev ?? const [];
    for (final req in next.where((r) => !shown.contains(r))) {
      showJamRequestDialog(context, ref, req);
    }
  });
  ref.listen(jamGuestProvider.select((g) => g.sentTick), (prev, next) {
    if (next > (prev ?? 0)) showSnack(context, context.l10n.jamSentToParty(ref.read(jamGuestProvider).sentCount));
  });
  ref.listen(jamGuestProvider.select((g) => g.phase), (prev, next) {
    if (prev == JamPhase.joined && next == JamPhase.ended) showSnack(context, context.l10n.jamEnded);
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

  /// Entrou: o resto da Festa acontece no player normal.
  void _openPlayer() {
    if (!mounted) return;
    context.canPop() ? context.pushReplacement('/now-playing') : context.go('/now-playing');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final host = ref.watch(jamHostProvider);
    final guest = ref.watch(jamGuestProvider);
    ref.listen(jamGuestProvider.select((g) => g.phase), (prev, next) {
      if (next == JamPhase.joined && prev != JamPhase.joined) _openPlayer();
      // Saiu da Festa com esta tela aberta: volta a procurar.
      if (next == JamPhase.idle && prev == JamPhase.joined) unawaited(ref.read(jamGuestProvider.notifier).search());
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.party),
        // Sem conta e aberta direto (link, fim da Festa): o caminho de volta é o login.
        leading: !context.canPop() && ref.watch(sessionProvider).value == null
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/login'),
              )
            : null,
      ),
      body: SafeArea(
        child: host.active
            ? const _HostView()
            : switch (guest.phase) {
                JamPhase.joined => const _JoinedView(),
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
                    await ensureJamPermissions(bluetooth: ref.read(jamBluetoothModeProvider));
                    await ref.read(jamHostProvider.notifier).start();
                  },
                ),
              ],
            ),
          ),
        ),
        const _PlainBtSwitch(),
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
              onPressed: () async {
                // A permissão pode ter sido negada antes: pede de novo.
                await ensureJamPermissions(bluetooth: ref.read(jamBluetoothModeProvider));
                await ref.read(jamGuestProvider.notifier).search();
              },
            ),
          ],
        ),
        // Onde a descoberta não passa — iPhone, Wi-Fi de hotel — ainda dá
        // para entrar digitando o endereço que o dono mostra na tela dele.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.keyboard, size: 18),
            label: Text(l10n.jamJoinByAddress),
            onPressed: () => _perguntarEndereco(context, ref),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.qr_code_2, size: 18, color: theme.colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.jamJoinByQr, style: theme.textTheme.bodySmall)),
            ],
          ),
        ),
        // Com a chave do Bluetooth sem Play Services ligada o aviso não vale mais.
        if (guest.bluetooth != JamBluetooth.ok && !(guest.bluetooth == JamBluetooth.unavailable && ref.watch(jamBluetoothModeProvider)))
          ListTile(
            leading: Icon(Icons.bluetooth_disabled, color: theme.colorScheme.error),
            title: Text(guest.bluetooth == JamBluetooth.unavailable ? l10n.jamBluetoothUnavailable : l10n.jamBluetoothFailed),
            subtitle: guest.bluetooth == JamBluetooth.failed
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(onPressed: openAppSettings, child: Text(l10n.jamOpenPermissions)),
                  )
                : null,
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
        const _MeuEndereco(),
        const _PlainBtSwitch(host: true),
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

/// Já na Festa: a tela só mostra onde se está. Tocar, ver a fila e mandar
/// músicas é no player normal.
class _JoinedView extends ConsumerWidget {
  const _JoinedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final host = ref.watch(jamGuestProvider.select((g) => g.hostName)) ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.groups, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.jamBarGuest(host), style: theme.textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l10n.jamJoinedHint, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.play_circle_outline),
                      label: Text(l10n.jamOpenPlayer),
                      onPressed: () => context.push('/now-playing'),
                    ),
                    OutlinedButton(
                      onPressed: () => ref.read(jamGuestProvider.notifier).leave(),
                      child: Text(l10n.leaveJam),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Capa de uma música do dono (chega pela conexão da Festa, em arquivo).
class JamHostCover extends ConsumerWidget {
  const JamHostCover({super.key, required this.id, this.size = 44});
  final String? id;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(jamGuestProvider.notifier);
    return ValueListenableBuilder(
      valueListenable: notifier.coverVersion,
      builder: (context, _, _) => CoverArt(coverArtId: notifier.coverFile(id), size: size, icon: Icons.music_note),
    );
  }
}

/// Fila da Festa no painel de fila do player, para o convidado: a do dono,
/// com quem pediu cada música, o que está indo daqui e o botão de adicionar.
/// Não dá para tirar nem mudar de lugar: a fila é de todos.
class JamQueue extends ConsumerWidget {
  const JamQueue({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final (queue, index) = ref.watch(playerProvider.select((s) => (s.queue, s.index)));
    final g = ref.watch(jamGuestProvider);
    final by = g.addedBy;
    final canJump = g.hostVersion >= 2;
    final notifier = ref.read(jamGuestProvider.notifier);
    final pending = [for (final e in g.transfers.entries) if (!e.value.done) e];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Icon(Icons.groups, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.jamQueueTitle, style: theme.textTheme.titleMedium)),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.jamAddToParty),
                onPressed: () => showJamAddSheet(context),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final e in pending)
                ListTile(
                  dense: true,
                  leading: Icon(e.value.error != null
                      ? Icons.error_outline
                      : (e.value.waiting ? Icons.schedule : Icons.upload)),
                  title: Text(e.value.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: e.value.error != null
                      ? Text(l10n.jamSendFailed)
                      : (e.value.waiting ? Text(l10n.jamWaitingSend) : LinearProgressIndicator(value: e.value.progress)),
                  trailing: e.value.error != null ? const Icon(Icons.close, size: 18) : null,
                  onTap: e.value.error != null ? () => notifier.dismissTransfer(e.key) : null,
                ),
              if (queue.isEmpty && pending.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(l10n.jamQueueEmpty, style: theme.textTheme.bodyMedium)),
                ),
              for (final (i, q) in queue.indexed)
                ListTile(
                  dense: true,
                  selected: i == index,
                  leading: CoverArt(coverArtId: q.song.coverArt, size: 36, icon: Icons.music_note),
                  title: Text(q.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [q.song.displayArtist, if (by[q.uid] case final b?) l10n.addedBy(b)].where((x) => x.isNotEmpty).join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(formatDuration(q.song.duration), style: theme.textTheme.bodySmall),
                  onTap: canJump && i != index ? () => ref.read(playerProvider.notifier).jumpTo(i) : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Folha "Adicionar à Festa": buscar nas músicas do dono ou mandar daqui
/// (arquivo do aparelho ou da biblioteca). As páginas normais da biblioteca
/// também mandam — esta é para quem não tem conta, e para as do dono.
Future<void> showJamAddSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.8,
        child: const _JamAddSheet(),
      ),
    );

class _JamAddSheet extends ConsumerWidget {
  const _JamAddSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // A Festa acabou com a folha aberta: não há mais para onde mandar.
    ref.listen(jamGuestProvider.select((g) => g.phase), (_, next) {
      if (next != JamPhase.joined && Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: l10n.jamTabParty), Tab(text: l10n.jamMine)]),
          const Expanded(child: TabBarView(children: [_HostSearch(), _MySongs()])),
        ],
      ),
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
                leading: JamHostCover(id: s.coverArt),
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
    ref.read(jamGuestProvider.notifier).sendSong(song);
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
            // Pelo id quando o dono tem a mesma música (mesmo servidor), senão o arquivo.
            onTap: () {
              ref.read(jamGuestProvider.notifier).addSongs([s]);
              showSnack(context, l10n.jamSending(s.title));
            },
          ),
      ],
    );
  }
}

/// Abre a Jam (usado pelo menu de aparelhos e pela biblioteca).
void openJam(BuildContext context) => context.push('/jam');


/// Pergunta o endereço da Festa e tenta entrar.
Future<void> _perguntarEndereco(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final campo = TextEditingController();
  final texto = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(l10n.jamJoinByAddress),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.jamJoinByAddressHint, style: Theme.of(d).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: campo,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: '192.168.1.10', border: OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(d, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(d, campo.text), child: Text(l10n.join)),
      ],
    ),
  );
  campo.dispose();
  if (texto == null || !context.mounted) return;
  final deu = await ref.read(jamGuestProvider.notifier).joinByAddress(texto);
  if (!deu && context.mounted) showSnack(context, l10n.jamAddressBad);
}

/// O endereço desta máquina, para quem vai digitar do outro lado.
class _MeuEndereco extends ConsumerStatefulWidget {
  const _MeuEndereco();

  @override
  ConsumerState<_MeuEndereco> createState() => _MeuEnderecoState();
}

class _MeuEnderecoState extends ConsumerState<_MeuEndereco> {
  List<String> _enderecos = const [];

  @override
  void initState() {
    super.initState();
    // A porta de verdade: com outra instância no computador ela não é a padrão.
    jamAddressesFor(ref.read(connectProvider.notifier).jamPort).then((e) {
      if (mounted) setState(() => _enderecos = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_enderecos.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final texto = _enderecos.join('   ');
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: Text(l10n.jamMyAddress),
          subtitle: Text(texto, style: Theme.of(context).textTheme.bodySmall),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l10n.jamShowQr,
                icon: const Icon(Icons.qr_code_2),
                onPressed: () => _mostrarQr(context, _enderecos.first),
              ),
              IconButton(
                tooltip: l10n.jamCopyAddress,
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _enderecos.first));
                  if (context.mounted) showSnack(context, l10n.jamAddressCopied);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}


/// Mostra o endereço em QR, para o convidado apontar a câmera **do próprio
/// celular** — o app não precisa de câmera nem de permissão para isso.
///
/// O QR leva um link `bkplayer://jam?...`, que o Android e o iOS sabem abrir
/// no app. Quem não tiver o app instalado ainda vê o endereço escrito
/// embaixo e pode digitar.
Future<void> _mostrarQr(BuildContext context, String endereco) {
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(l10n.jamShowQr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            // O leitor precisa de fundo claro; no tema escuro ficaria ilegível.
            color: Colors.white,
            child: QrImageView(
              data: 'bkplayer://jam?h=${Uri.encodeComponent(endereco.split(':').first)}'
                  '&p=${endereco.split(':').last}',
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(l10n.jamQrHint, textAlign: TextAlign.center, style: Theme.of(d).textTheme.bodySmall),
          const SizedBox(height: 8),
          SelectableText(endereco, style: Theme.of(d).textTheme.bodyMedium),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(l10n.jamClose))],
    ),
  );
}

// ---- Bluetooth sem Google Play Services ----

/// Chave do Bluetooth sem Play Services e, para o convidado, o modo manual
/// (escolher o dono entre os celulares pareados).
class _PlainBtSwitch extends ConsumerWidget {
  const _PlainBtSwitch({this.host = false});
  final bool host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (jamBluetooth == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final on = ref.watch(jamBluetoothModeProvider);
    final failed = !host && ref.watch(jamGuestProvider.select((g) => g.plainBtFailed));
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.bluetooth),
            title: Text(l10n.jamPlainBt),
            subtitle: Text(l10n.jamPlainBtHint),
            value: on,
            onChanged: (v) => _setPlainBt(context, ref, v),
          ),
          if (on && failed)
            ListTile(
              leading: Icon(Icons.bluetooth_disabled, color: theme.colorScheme.error),
              title: Text(l10n.jamPlainBtFailed),
            ),
          if (on && !host)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: TextButton.icon(icon: const Icon(Icons.link, size: 18), label: Text(l10n.jamPairedPick), onPressed: () => _escolherPareado(context, ref)),
            ),
        ],
      ),
    );
  }
}

Future<void> _setPlainBt(BuildContext context, WidgetRef ref, bool on) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  if (on) {
    await ensureJamPermissions(bluetooth: true);
    if (!await BluetoothJam.isOn()) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.jamBtOff)));
      return;
    }
  }
  ref.read(jamBluetoothModeProvider.notifier).set(on);
  final host = ref.read(jamHostProvider.notifier);
  if (ref.read(jamHostProvider).active) {
    if (!await host.setBluetooth(on) && on) messenger.showSnackBar(SnackBar(content: Text(l10n.jamPlainBtHostFailed)));
  } else {
    await ref.read(jamGuestProvider.notifier).setBluetooth(on);
  }
}

/// Modo manual: o convidado escolhe o dono entre os celulares pareados.
Future<void> _escolherPareado(BuildContext context, WidgetRef ref) async {
  final bt = BluetoothJam.instance;
  if (bt == null) return;
  final l10n = context.l10n;
  List<JamOffer> pareados;
  try {
    pareados = await bt.paired();
  } catch (_) {
    pareados = const [];
  }
  if (!context.mounted) return;
  final escolhido = await showModalBottomSheet<JamOffer>(
    context: context,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(l10n.jamPairedTitle), subtitle: Text(l10n.jamPairedHint)),
          if (pareados.isEmpty) ListTile(leading: const Icon(Icons.info_outline), title: Text(l10n.jamPairedNone)),
          for (final o in pareados) ListTile(leading: const Icon(Icons.smartphone), title: Text(o.hostName), onTap: () => Navigator.pop(c, o)),
        ],
      ),
    ),
  );
  if (escolhido != null) await ref.read(jamGuestProvider.notifier).join(escolhido);
}
