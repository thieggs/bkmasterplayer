import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/diagnostics.dart';
import '../l10n/l10n.dart';

/// Tela para quando o motor de áudio não inicia: em vez de a abertura ficar
/// parada para sempre, diz o que houve e deixa copiar o relatório.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF6446C9)),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF6446C9), brightness: Brightness.dark),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          final l10n = context.l10n;
          final theme = Theme.of(context);
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(24),
                    children: [
                      Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(l10n.startupFailed, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(l10n.startupFailedHint, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      SelectableText(redactSecrets('$error'), style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (context) => FilledButton.tonalIcon(
                          icon: const Icon(Icons.copy_all_outlined),
                          label: Text(l10n.diagnosticsCopy),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: diagnosticReport(info: {'Início': 'o motor não iniciou'})));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.diagnosticsCopied)));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      );
}
