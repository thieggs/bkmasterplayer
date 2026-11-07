import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/recommend.dart';
import '../../data/smart_marks.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../pages/smart_saved_page.dart';
import '../widgets/cover_art.dart';

/// O que o aleatório smart aprendeu: as músicas que puxam (com a força de
/// cada uma) e as que afastam, cada uma com um ✕ para esquecer.
///
/// Ver o que o modo entendeu é o que deixa confiar nele — e corrigir quando
/// ele entendeu errado (o Deezer lançou o "Flow Tuner" em 2026 por isso).
///
/// Em cima, as marcas dos botões "+" e "−" ("Sempre" e "Nunca"), que valem
/// para sempre: por isso o painel abre também com o modo desligado (pelos
/// ajustes), só com elas.
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
    final marks = ref.watch(smartMarksProvider);
    final player = ref.read(playerProvider.notifier);
    final learned = player.smartLearned;
    // Os ímãs do modo, sem as marcadas com "+" (essas vão em "Sempre").
    final liked = [
      for (final x in learned?.liked ?? const <(Song, double)>[])
        if (!(learned?.more.contains(x.$1.id) ?? false)) x,
    ];
    final forte = liked.isEmpty ? 1.0 : liked.first.$2;
    void esquecer(String id) {
      player.smartForget(id);
      setState(() {});
    }

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(t, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        );

    Widget marcada(Song song) => ListTile(
          dense: true,
          leading: CoverArt(coverArtId: song.coverArt, size: 40, icon: Icons.music_note),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(song.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: l10n.smartUnmark,
            icon: const Icon(Icons.close),
            onPressed: () {
              player.smartUnmark(song.id);
              setState(() {});
            },
          ),
        );

    final secoesMarcas = [
      if (marks.more.isNotEmpty) titulo(l10n.smartMoreSection),
      for (final s in marks.more) marcada(s),
      if (marks.never.isNotEmpty) titulo(l10n.smartNeverSection),
      for (final s in marks.never) marcada(s),
    ];

    if (learned == null) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: Text(l10n.smartMarksTitle, style: theme.textTheme.titleLarge),
                subtitle: Text('${l10n.smartOff} · ${l10n.smartMarksHint}'),
              ),
              ...secoesMarcas,
              if (secoesMarcas.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.smartNoMarks, style: theme.textTheme.bodyMedium),
                ),
            ],
          ),
        ),
      );
    }

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
            if (liked.isEmpty && learned.avoiding.isEmpty && secoesMarcas.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.smartNothingYet, style: theme.textTheme.bodyMedium),
              ),
            ...secoesMarcas,
            if (liked.isNotEmpty) titulo(l10n.smartLiked),
            for (final (song, peso) in liked)
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
                // Guarda o estilo na aba "Aleatórios smart" (fecha o painel
                // para o nome e o aviso aparecerem na tela de baixo).
                TextButton.icon(
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(l10n.smartSave),
                  onPressed: liked.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          saveSmartStyle(widget.host, player);
                        },
                ),
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
