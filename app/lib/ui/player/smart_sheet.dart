import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/recommend.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/cover_art.dart';

/// O que o aleatório smart aprendeu: as músicas que puxam (com a força de
/// cada uma) e as que afastam, cada uma com um ✕ para esquecer.
///
/// Ver o que o modo entendeu é o que deixa confiar nele — e corrigir quando
/// ele entendeu errado (o Deezer lançou o "Flow Tuner" em 2026 por isso).
Future<void> showSmartSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SmartSheet(host: context),
    );

class _SmartSheet extends ConsumerStatefulWidget {
  const _SmartSheet({required this.host});

  /// Tela de baixo: continua viva depois que a folha fecha, e é ela que
  /// navega para os ajustes.
  final BuildContext host;

  @override
  ConsumerState<_SmartSheet> createState() => _SmartSheetState();
}

class _SmartSheetState extends ConsumerState<_SmartSheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // Cada música que sai pode mudar o que ele sabe: o painel acompanha.
    ref.watch(playerProvider.select((s) => (s.index, s.smart, s.queue.length)));
    final vetores = ref.watch(recommendProvider).ready;
    final player = ref.read(playerProvider.notifier);
    final learned = player.smartLearned;
    if (learned == null) {
      return SafeArea(child: ListTile(leading: const Icon(Icons.psychology_outlined), title: Text(l10n.smartOff)));
    }
    final forte = learned.liked.isEmpty ? 1.0 : learned.liked.first.$2;
    void esquecer(String id) {
      player.smartForget(id);
      setState(() {});
    }

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            ListTile(
              leading: Icon(Icons.psychology, color: theme.colorScheme.primary),
              title: Text(l10n.smartLearned, style: theme.textTheme.titleLarge),
              subtitle: Text(learned.searching ? l10n.smartSearching : l10n.smartExploreStatus(learned.exploreEvery)),
            ),
            // Sem os vetores o modo só tira a própria música pulada: dizer,
            // senão parece que ele não aprende.
            if (!vetores)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(l10n.smartNeedsVectors,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
            if (learned.liked.isEmpty && learned.avoiding.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.smartNothingYet, style: theme.textTheme.bodyMedium),
              ),
            if (learned.liked.isNotEmpty) titulo(l10n.smartLiked),
            for (final (song, peso) in learned.liked)
              ListTile(
                dense: true,
                leading: CoverArt(coverArtId: song.coverArt, size: 40, icon: Icons.music_note),
                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    // A força de cada ímã, perto da mais forte.
                    LinearProgressIndicator(value: (peso / forte).clamp(0.05, 1.0)),
                  ],
                ),
                trailing: IconButton(
                  tooltip: l10n.smartForget,
                  icon: const Icon(Icons.close),
                  onPressed: () => esquecer(song.id),
                ),
              ),
            if (learned.avoiding.isNotEmpty) titulo(l10n.smartAvoiding),
            for (final song in learned.avoiding)
              ListTile(
                dense: true,
                leading: CoverArt(coverArtId: song.coverArt, size: 40, icon: Icons.music_note),
                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(song.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: l10n.smartForget,
                  icon: const Icon(Icons.close),
                  onPressed: () => esquecer(song.id),
                ),
              ),
            const Divider(height: 24),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: Text(l10n.smartForgetAll),
                  onPressed: () {
                    player.smartForgetAll();
                    setState(() {});
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.tune),
                  label: Text(l10n.settings),
                  onPressed: () {
                    Navigator.of(context).pop();
                    goFromPlayer(widget.host, '/settings/recommend');
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
