import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n.dart';
import 'jam_core.dart';

/// Faixa da Festa dentro do player.
///
/// Sem ela, quem está numa Festa só descobre isso indo na aba — e o convidado
/// via a música mudar sozinha sem entender por quê. Fica escondida quando não
/// há Festa, então o player volta ao normal ao sair.
class JamBar extends ConsumerWidget {
  const JamBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dono = ref.watch(jamHostProvider);
    final convidado = ref.watch(jamGuestProvider);
    final naFesta = dono.active || convidado.phase == JamPhase.joined;
    if (!naFesta) return const SizedBox.shrink();

    final (texto, sair, rotulo) = dono.active
        ? (
            l10n.jamBarHosting(dono.participants.length),
            () => ref.read(jamHostProvider.notifier).stop(),
            l10n.endJam,
          )
        : (
            l10n.jamBarGuest(convidado.hostName ?? '?'),
            () => ref.read(jamGuestProvider.notifier).leave(),
            l10n.jamLeave,
          );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          // Tocar na faixa leva para a Festa, onde ficam os detalhes.
          onTap: () => context.push('/jam'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.groups, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: sair, child: Text(rotulo)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
