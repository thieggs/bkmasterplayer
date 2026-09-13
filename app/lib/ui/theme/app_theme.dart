import 'package:flutter/material.dart';

import '../../data/ui_prefs.dart';

/// Tema (Material 3) montado a partir das preferências de customização.
class AppTheme {
  static ThemeData build(ColorScheme scheme, {UiPrefs prefs = const UiPrefs()}) {
    final isDesktop = switch (ThemeData().platform) {
      TargetPlatform.linux || TargetPlatform.windows || TargetPlatform.macOS => true,
      _ => false,
    };
    if (prefs.amoled && scheme.brightness == Brightness.dark) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF101010),
        surfaceContainerHigh: const Color(0xFF161616),
        surfaceContainerHighest: const Color(0xFF1C1C1C),
      );
    }
    final density = switch (prefs.density) {
      'compact' => VisualDensity.compact,
      'comfortable' => VisualDensity.comfortable,
      'standard' => VisualDensity.standard,
      _ => isDesktop ? VisualDensity.compact : VisualDensity.standard,
    };
    final r = prefs.radius;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: density,
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: r >= 18 ? const StadiumBorder() : shape)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: r >= 18 ? const StadiumBorder() : shape)),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.clamp(0, 16)))),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 8))),
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
        shape: shape,
      ),
    );
  }

  static ColorScheme seeded(int seed, Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: Color(seed), brightness: brightness);
}
