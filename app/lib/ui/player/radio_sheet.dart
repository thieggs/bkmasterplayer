import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/recommend.dart';
import '../../data/similar.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../actions.dart';
import '../recommend_style_ui.dart';

/// Rádio da tela do player: escolhe por onde a análise se guia para completar
/// a fila a partir da música que está tocando.
///
/// Isto **não** é o AutoMix — o AutoMix costura uma música na outra; aqui se
/// decide qual música vem.
///
/// Menos "Deixar o servidor escolher", todos os métodos são contados aqui no
/// aparelho e **precisam da análise guardada**. Sem ela o servidor responde no
/// lugar e a escolha não muda nada: a folha diz isso em vez de deixar a pessoa
/// trocar de método à toa.
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
              leading: Icon(Icons.radio, color: rec.ready ? null : theme.colorScheme.error),
              title: Text(l10n.radioSheetTitle, style: theme.textTheme.titleLarge),
              // Sem os vetores o aviso **substitui** a explicação: é o que
              // importa saber agora, e não empurra os métodos fora da tela.
              subtitle: Text(
                rec.ready ? l10n.radioSheetHint : l10n.radioSheetOnline,
                style: rec.ready ? null : TextStyle(color: theme.colorScheme.error),
              ),
            ),
            const Divider(height: 8),
            for (final e in RecommendStyle.values)
              _StyleTile(
                style: e,
                chosen: e == escolhido,
                // Vai valer de verdade, ou vai cair no servidor?
                works: styleWorksNow(e, vectorsReady: rec.ready),
                onTap: () {
                  hostRef.read(settingsProvider.notifier).update((x) => x.copyWith(recommendStyle: e.id));
                  Navigator.of(context).pop();
                  if (!styleWorksNow(e, vectorsReady: rec.ready)) {
                    showSnack(host, l10n.radioStyleWontApply(e.label(l10n)));
                  }
                  LibraryActions.instantMix(host, hostRef, song, style: e);
                },
              ),
            const Divider(height: 8),
            ListTile(
              dense: true,
              leading: Icon(
                rec.ready ? Icons.offline_bolt_outlined : Icons.cloud_download_outlined,
                size: 20,
                color: theme.colorScheme.outline,
              ),
              title: Text(
                rec.ready ? l10n.recommendReady(rec.songs) : l10n.recommendTurnOn,
                style: theme.textTheme.bodySmall,
              ),
              trailing: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  goFromPlayer(host, '/settings/recommend');
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

/// Um método na lista. [works] falso = está escolhível, mas hoje o servidor
/// responde no lugar dele; o aviso fica visível em vez de a troca ser muda.
class _StyleTile extends StatelessWidget {
  const _StyleTile({required this.style, required this.chosen, required this.works, required this.onTap});

  final RecommendStyle style;
  final bool chosen;
  final bool works;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cor = chosen ? theme.colorScheme.primary : null;
    return ListTile(
      leading: Icon(style.icon, color: cor),
      title: Text(style.label(l10n), style: chosen ? TextStyle(color: cor) : null),
      subtitle: Text(style.hint(l10n), style: theme.textTheme.bodySmall),
      // O aviso vai no ícone, não numa linha a mais: com seis métodos avisados
      // a lista cresceria até esconder os últimos. O leitor de tela lê o
      // `message` do Tooltip.
      trailing: chosen
          ? Icon(Icons.check, color: cor)
          : (works
              ? null
              : Tooltip(
                  message: l10n.recommendStyleNeedsVectors,
                  child: Icon(Icons.cloud_download_outlined, size: 20, color: theme.colorScheme.error),
                )),
      onTap: onTap,
    );
  }
}
