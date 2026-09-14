import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/l10n.dart';

/// Tela de ajustes: título com a seta de voltar e o conteúdo numa coluna de
/// leitura confortável (centralizada nas telas largas).
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({super.key, required this.title, required this.children, this.back = '/settings', this.actions});

  final String title;
  final List<Widget> children;

  /// Para onde a seta leva quando não há tela para voltar (null = sem seta).
  final String? back;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(back == null ? 16 : 4, back == null ? 20 : 12, 8, 4),
              child: Row(
                children: [
                  if (back != null)
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.canPop() ? context.pop() : context.go(back!),
                    ),
                  Expanded(
                    child: Text(title, style: theme.textTheme.headlineMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  ...?actions,
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Título de um grupo dentro de uma tela de ajustes.
class SettingsSection extends StatelessWidget {
  const SettingsSection(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// Escolha entre poucas opções, em fichas (cabe no celular).
class ChoiceTile<T> extends StatelessWidget {
  const ChoiceTile({super.key, required this.title, required this.value, required this.options, required this.onChanged, this.icon, this.subtitle});

  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon ?? Icons.tune),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(subtitle!)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in options.entries)
                  ChoiceChip(label: Text(e.value), selected: value == e.key, onSelected: (_) => onChanged(e.key)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pede um texto (chave de API, nome, endereço). '' = remover; null = cancelou.
Future<String?> askText(BuildContext context,
    {required String title, String? initial, String? hint, String? helper, bool canRemove = false}) {
  final l10n = context.l10n;
  final ctl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        autocorrect: false,
        decoration: InputDecoration(hintText: hint, helperText: helper, helperMaxLines: 3),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        if (canRemove) TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(l10n.remove)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: Text(l10n.save)),
      ],
    ),
  ).whenComplete(ctl.dispose);
}
