import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/recommend.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../actions.dart';
import '../recommend_style_ui.dart';

/// Rádio da tela do player: escolhe por onde a análise do AudioMuse se guia
/// para completar a fila a partir da música que está tocando.
///
/// Isto **não** é o AutoMix — o AutoMix costura uma música na outra; aqui se
/// decide qual música vem.
Future<void> showRadioSheet(BuildContext context, WidgetRef ref, Song song) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _RadioSheet(song: song, host: context, hostRef: ref),
  );
}

class _RadioSheet extends ConsumerWidget {
  const _RadioSheet({required this.song, required this.host, required this.hostRef});

  final Song song;

  /// Tela de baixo: continua viva depois que a folha fecha, então é ela que
  /// mostra o aviso, navega e toca. O `ref` da folha morre junto com ela, e a
  /// rádio ainda está sendo montada quando isso acontece.
  final BuildContext host;
  final WidgetRef hostRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final rec = ref.watch(recommendProvider);
    final escolhido = RecommendStyle.parse(s.recommendStyle);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            ListTile(
              leading: const Icon(Icons.radio),
              title: Text(l10n.radioSheetTitle, style: theme.textTheme.titleLarge),
              subtitle: Text(l10n.radioSheetHint),
            ),
            const Divider(height: 8),
            for (final e in RecommendStyle.values)
              ListTile(
                leading: Icon(e.icon, color: e == escolhido ? theme.colorScheme.primary : null),
                title: Text(e.label(l10n),
                    style: e == escolhido ? TextStyle(color: theme.colorScheme.primary) : null),
                subtitle: Text(e.hint(l10n), style: theme.textTheme.bodySmall),
                trailing: e == escolhido ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                onTap: () {
                  hostRef.read(settingsProvider.notifier).update((x) => x.copyWith(recommendStyle: e.id));
                  Navigator.of(context).pop();
                  LibraryActions.instantMix(host, hostRef, song, style: e);
                },
              ),
            const Divider(height: 8),
            ListTile(
              dense: true,
              leading: Icon(
                rec.ready ? Icons.offline_bolt_outlined : Icons.cloud_outlined,
                size: 20,
                color: theme.colorScheme.outline,
              ),
              title: Text(
                rec.ready ? l10n.recommendReady(rec.songs) : l10n.radioSheetOnline,
                style: theme.textTheme.bodySmall,
              ),
              trailing: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  host.push('/settings/recommend');
                },
                child: Text(l10n.settings),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
