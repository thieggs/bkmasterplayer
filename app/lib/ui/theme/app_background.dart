import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/providers.dart';
import '../../data/theme_library.dart';
import '../../player/player_controller.dart';
import '../widgets/cover_art.dart';

/// Fundo atrás de todas as telas quando o tema não é liso: gradiente com as
/// cores do tema, capa que toca desfocada ou uma imagem, com a cor do tema
/// por cima na medida escolhida (legibilidade).
class AppBackground extends ConsumerWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(uiPrefsProvider.select((u) => u.background));
    if (kind == 'solid') return child;
    final dim = ref.watch(uiPrefsProvider.select((u) => u.backgroundDim));
    final scheme = Theme.of(context).colorScheme;

    Widget? layer;
    switch (kind) {
      case 'gradient':
        layer = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primaryContainer, scheme.surface, scheme.tertiaryContainer],
            ),
          ),
        );
      case 'cover':
        final cover = ref.watch(playerProvider.select((s) => s.current?.song.coverArt));
        final image = coverProvider(ref, cover, 300);
        if (image != null) {
          layer = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Image(image: image, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
          );
        }
      case 'image':
        final name = ref.watch(uiPrefsProvider.select((u) => u.backgroundImage));
        if (name != null) {
          final file = File(p.join(themeImagesDir(ref.watch(supportDirProvider).path), name));
          layer = Image.file(file, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox());
        }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: scheme.surface),
        if (layer != null) Positioned.fill(child: layer),
        if (layer != null) ColoredBox(color: scheme.surface.withValues(alpha: dim.clamp(0.0, 1.0))),
        child,
      ],
    );
  }
}
