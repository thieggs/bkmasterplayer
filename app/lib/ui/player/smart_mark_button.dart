import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/smart_marks.dart';
import '../../l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../actions.dart';

/// Botões "−" e "+" do aleatório smart, dos lados dos controles (pedido do
/// usuário, 07/11/2026): "−" ao lado do aleatório, "+" ao lado do repetir.
/// Marcam a música que está tocando, para sempre; apertar de novo desmarca.
/// Aceso = a música já tem essa marca. Ver `PlayerController.setSmartMark`.
class SmartMarkButton extends ConsumerWidget {
  const SmartMarkButton({super.key, required this.more, this.iconSize});

  /// "+" (true) ou "−".
  final bool more;
  final double? iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final id = ref.watch(playerProvider.select((s) => s.current?.song.id));
    final marked = ref.watch(smartMarksProvider.select((m) => id != null && (more ? m.isMore(id) : m.isNever(id))));
    return IconButton(
      tooltip: marked ? l10n.smartUnmark : (more ? l10n.smartMoreButton : l10n.smartNeverButton),
      iconSize: iconSize,
      isSelected: marked,
      color: marked ? (more ? scheme.primary : scheme.error) : null,
      icon: Icon(more ? Icons.add_circle_outline : Icons.remove_circle_outline),
      selectedIcon: Icon(more ? Icons.add_circle : Icons.remove_circle),
      onPressed: id == null ? null : () => pressSmartMark(context, ref, more: more),
    );
  }
}

/// Marca (ou desmarca) a música que está tocando e avisa, com "desfazer".
void pressSmartMark(BuildContext context, WidgetRef ref, {required bool more}) {
  final player = ref.read(playerProvider.notifier);
  final r = player.smartMark(more: more);
  if (r == null) return;
  final (song, mark) = r;
  final l10n = context.l10n;
  if (mark == null) {
    showSnack(context, l10n.smartUnmarked(song.title));
    return;
  }
  showUndoSnack(
    context,
    mark ? l10n.smartMarkedMore(song.title) : l10n.smartMarkedNever(song.title),
    undoLabel: l10n.smartUndo,
    onUndo: () => player.setSmartMark(song, more: more, on: false),
  );
}
