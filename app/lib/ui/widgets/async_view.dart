import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/subsonic/subsonic_client.dart';
import '../../l10n/l10n.dart';

/// Em português e curto, em vez da exceção crua na tela.
///
/// O que vem do servidor já chega explicado (`SubsonicException`); o resto é
/// defeito nosso, e o nome da classe não ajuda ninguém.
String mensagemDoErro(Object e, AppLocalizations l10n) => switch (e) {
      SubsonicException s => s.message,
      StateError _ => l10n.notConnected,
      _ => l10n.couldNotLoad,
    };

/// Mostra carregando / erro com "tentar de novo" / conteúdo.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 40, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(mensagemDoErro(e, context.l10n), textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
          ?action,
        ],
      ),
    );
  }
}
