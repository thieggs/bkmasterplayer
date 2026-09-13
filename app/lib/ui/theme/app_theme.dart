import 'package:flutter/material.dart';

/// Tema base (Material 3). Na Fase 4 isto vira um motor de tokens editáveis.
class AppTheme {
  static ThemeData build(ColorScheme scheme, {double uiScale = 1.0}) {
    final isDesktop = switch (ThemeData().platform) {
      TargetPlatform.linux || TargetPlatform.windows || TargetPlatform.macOS => true,
      _ => false,
    };
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: isDesktop ? VisualDensity.compact : VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.15),
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ColorScheme seeded(int seed, Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: Color(seed), brightness: brightness);
}
