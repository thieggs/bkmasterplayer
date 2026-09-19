import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/commands.dart';

/// Aviso do volume do aparelho controlado, no lugar do que o sistema mostraria.
///
/// Quando o app está controlando outro aparelho, ele fica com os botões de
/// volume do celular (ver [CommandsNotifier]) — e aí o Android não mostra mais
/// a barrinha dele. Sem isto, apertar o botão não daria sinal nenhum.
class RemoteVolumeOverlay extends ConsumerStatefulWidget {
  const RemoteVolumeOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RemoteVolumeOverlay> createState() => _RemoteVolumeOverlayState();
}

class _RemoteVolumeOverlayState extends ConsumerState<RemoteVolumeOverlay> {
  static const _hold = Duration(milliseconds: 1200);

  ({double volume, String device, int seq})? _show;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _onNudge(({double volume, String device, int seq})? n) {
    if (n == null) return;
    setState(() => _show = n);
    _hide?.cancel();
    _hide = Timer(_hold, () {
      if (mounted) setState(() => _show = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(commandsProvider.select((c) => c.nudge), (_, n) => _onNudge(n));
    final theme = Theme.of(context);
    final n = _show;
    return Stack(
      children: [
        widget.child,
        // Não intercepta toque: é só um aviso passando.
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: n == null ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: n == null
                ? const SizedBox.shrink()
                : Center(
                    child: Material(
                      color: theme.colorScheme.inverseSurface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              n.volume <= 0 ? Icons.volume_off : (n.volume < 0.5 ? Icons.volume_down : Icons.volume_up),
                              color: theme.colorScheme.onInverseSurface,
                            ),
                            const SizedBox(height: 8),
                            Text(n.device,
                                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onInverseSurface)),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 160,
                              child: LinearProgressIndicator(
                                value: n.volume,
                                color: theme.colorScheme.onInverseSurface,
                                backgroundColor: theme.colorScheme.onInverseSurface.withValues(alpha: 0.25),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('${(n.volume * 100).round()}%',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onInverseSurface)),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
