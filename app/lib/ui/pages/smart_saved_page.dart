import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/smart_saved.dart';
import '../../data/subsonic/subsonic_client.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';
import '../widgets/cover_art.dart';

/// Aba "Aleatórios smart": os estilos que a pessoa salvou de um aleatório
/// smart, para voltar a eles (pedido do usuário, 07/11/2026). Tocar um
/// recomeça o modo com o que ele tinha aprendido. Ver `data/smart_saved.dart`.
///
/// A lista vem na ordem de uso, nunca pela parecença com o gosto (a regra 1
/// da patente, em `player/smart_session.dart`).
class SmartSavedPage extends ConsumerWidget {
  const SmartSavedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final list = ref.watch(savedSmartProvider);
    final smart = ref.watch(playerProvider.select((s) => s.smart && !s.elsewhere));
    // O id do que toca agora (para marcar na lista).
    ref.watch(playerProvider.select((s) => s.index));
    final tocando = smart ? ref.read(playerProvider.notifier).smartSavedFrom?.id : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(l10n.smartSavedTab, style: theme.textTheme.headlineMedium),
              Wrap(
                spacing: 8,
                children: [
                  if (smart)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(l10n.smartSave),
                      onPressed: () => saveSmartStyle(context, ref.read(playerProvider.notifier)),
                    ),
                  if (!smart)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.psychology_outlined),
                      label: Text(l10n.smartShuffle),
                      onPressed: () => LibraryActions.smartShuffle(context, ref),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.psychology_outlined, size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        Text(l10n.smartSavedEmpty, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _SavedTile(saved: list[i], playing: list[i].id == tocando),
                ),
        ),
      ],
    );
  }
}

class _SavedTile extends ConsumerWidget {
  const _SavedTile({required this.saved, required this.playing});
  final SavedSmart saved;
  final bool playing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final artistas = saved.artists(3).join(', ');
    return ListTile(
      leading: _Mosaic(covers: saved.covers),
      title: Text(saved.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (playing) l10n.smartSavedPlaying, l10n.smartSavedCount(saved.liked.length), if (artistas.isNotEmpty) artistas]
            .join(' • '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: playing ? TextStyle(color: theme.colorScheme.primary) : null,
      ),
      selected: playing,
      onTap: () => playSmartSaved(context, ref, saved),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          final notifier = ref.read(savedSmartProvider.notifier);
          switch (v) {
            case 'play':
              await playSmartSaved(context, ref, saved);
            case 'rename':
              final nome = await LibraryActions.promptText(context, l10n.rename, l10n.smartSaveName, initial: saved.name);
              if (nome != null && nome.trim().isNotEmpty) notifier.rename(saved.id, nome.trim());
            case 'delete':
              notifier.remove(saved.id);
              if (context.mounted) {
                showUndoSnack(context, l10n.smartSavedDeleted(saved.name),
                    undoLabel: l10n.smartUndo, onUndo: () => notifier.put(saved));
              }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'play', child: Text(l10n.play)),
          PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
          PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
        ],
      ),
    );
  }
}

/// Até quatro capas dos ímãs, em mosaico; sem capa, o ícone do modo.
class _Mosaic extends StatelessWidget {
  const _Mosaic({required this.covers});
  final List<String> covers;

  static const size = 48.0;

  @override
  Widget build(BuildContext context) {
    if (covers.length < 4) {
      return CoverArt(coverArtId: covers.firstOrNull, size: size, icon: Icons.psychology_outlined);
    }
    const half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: Wrap(
          children: [for (final c in covers) CoverArt(coverArtId: c, size: half, icon: Icons.music_note)],
        ),
      ),
    );
  }
}

/// Toca o aleatório smart salvo [saved], com o aviso de "montando".
Future<void> playSmartSaved(BuildContext context, WidgetRef ref, SavedSmart saved) async {
  final l10n = context.l10n;
  showSnack(context, l10n.smartStarting);
  try {
    final ok = await ref.read(playerProvider.notifier).startSmartSaved(saved);
    if (!ok && context.mounted) showSnack(context, l10n.smartNothing);
  } on SubsonicException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  }
}

/// "Salvar este estilo": pergunta o nome (sugere os artistas que mais puxam)
/// e salva na aba. Se o aleatório veio de um salvo, oferece atualizar aquele.
///
/// Recebe o [player] e não o `ref`: o painel se fecha antes de perguntar.
Future<void> saveSmartStyle(BuildContext context, PlayerController player) async {
  final l10n = context.l10n;
  final learned = player.smartLearned;
  final liked = <(Song, double)>[
    for (final x in learned?.liked ?? const <(Song, double)>[])
      if (!(learned?.more.contains(x.$1.id) ?? false)) x,
  ];
  if (liked.isEmpty) {
    showSnack(context, l10n.smartSaveNothing);
    return;
  }
  final antigo = player.smartSavedFrom;
  final controller = TextEditingController(text: antigo?.name ?? SavedSmart.suggestName(liked));
  final r = await showDialog<(String, bool)>(
    context: context,
    builder: (ctx) {
      void ok(bool replace) => Navigator.pop(ctx, (controller.text, replace));
      return AlertDialog(
        title: Text(l10n.smartSaveTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.smartSaveName),
              onSubmitted: (_) => ok(antigo != null),
            ),
            const SizedBox(height: 12),
            Text(l10n.smartSaveHint, style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          if (antigo != null) ...[
            TextButton(onPressed: () => ok(false), child: Text(l10n.smartSaveNew)),
            FilledButton(onPressed: () => ok(true), child: Text(l10n.smartSaveUpdate(antigo.name))),
          ] else
            FilledButton(onPressed: () => ok(false), child: Text(l10n.save)),
        ],
      );
    },
  );
  if (r == null || !context.mounted) return;
  final (nome, replace) = r;
  final name = nome.trim().isEmpty ? SavedSmart.suggestName(liked) : nome.trim();
  final saved = player.saveSmart(name, replace: replace);
  showSnack(context, saved == null ? l10n.smartSaveNothing : l10n.smartSavedDone(saved.name));
}
