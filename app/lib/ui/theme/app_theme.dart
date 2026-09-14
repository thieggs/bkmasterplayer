import 'package:flutter/material.dart';

import '../../data/ui_prefs.dart';

/// Tema (Material 3) montado a partir da personalização gráfica. Com as
/// preferências padrão sai igual ao visual original do app.
class AppTheme {
  /// Paleta a partir da cor base, no estilo e contraste escolhidos.
  static ColorScheme seeded(UiPrefs prefs, Brightness brightness) => finish(
        ColorScheme.fromSeed(
          seedColor: Color(prefs.seed),
          brightness: brightness,
          dynamicSchemeVariant: variantOf(prefs),
          contrastLevel: prefs.contrast,
        ),
        prefs,
      );

  /// Paleta tirada de uma imagem (a capa que toca).
  static Future<ColorScheme> fromImage(ImageProvider image, UiPrefs prefs, Brightness brightness) async => finish(
        await ColorScheme.fromImageProvider(
          provider: image,
          brightness: brightness,
          dynamicSchemeVariant: variantOf(prefs),
          contrastLevel: prefs.contrast,
        ),
        prefs,
      );

  static DynamicSchemeVariant variantOf(UiPrefs p) =>
      DynamicSchemeVariant.values.asNameMap()[p.variant] ?? DynamicSchemeVariant.tonalSpot;

  /// AMOLED e as cores trocadas à mão por cima da paleta calculada.
  static ColorScheme finish(ColorScheme scheme, UiPrefs prefs) {
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
    final c = prefs.colors;
    Color on(Color bg) => ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : Colors.black;
    if (c['primary'] case final v?) {
      final x = Color(v);
      scheme = scheme.copyWith(primary: x, onPrimary: on(x));
    }
    if (c['secondary'] case final v?) {
      final x = Color(v);
      scheme = scheme.copyWith(secondary: x, onSecondary: on(x));
    }
    if (c['tertiary'] case final v?) {
      final x = Color(v);
      scheme = scheme.copyWith(tertiary: x, onTertiary: on(x));
    }
    if (c['background'] case final v?) {
      final bg = Color(v);
      final toward = on(bg);
      Color step(double t) => Color.lerp(bg, toward, t)!;
      scheme = scheme.copyWith(
        surface: bg,
        surfaceContainerLowest: bg,
        surfaceContainerLow: step(0.03),
        surfaceContainer: step(0.05),
        surfaceContainerHigh: step(0.08),
        surfaceContainerHighest: step(0.11),
        onSurface: c['text'] == null ? toward : null,
      );
    }
    if (c['text'] case final v?) {
      final x = Color(v);
      scheme = scheme.copyWith(onSurface: x, onSurfaceVariant: x.withValues(alpha: 0.72));
    }
    return scheme;
  }

  static ThemeData build(ColorScheme scheme, {UiPrefs prefs = const UiPrefs()}) {
    final isDesktop = switch (ThemeData().platform) {
      TargetPlatform.linux || TargetPlatform.windows || TargetPlatform.macOS => true,
      _ => false,
    };
    final density = switch (prefs.density) {
      'compact' => VisualDensity.compact,
      'comfortable' => VisualDensity.comfortable,
      'standard' => VisualDensity.standard,
      _ => isDesktop ? VisualDensity.compact : VisualDensity.standard,
    };
    final r = prefs.radius;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
    final OutlinedBorder buttonShape = r >= 18 ? const StadiumBorder() : shape;
    final filled = switch (prefs.buttonStyle) {
      'tonal' => FilledButton.styleFrom(
          shape: buttonShape,
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
        ),
      'outlined' => FilledButton.styleFrom(
          shape: buttonShape.copyWith(side: BorderSide(color: scheme.primary, width: 1.5)),
          backgroundColor: Colors.transparent,
          foregroundColor: scheme.primary,
        ),
      _ => FilledButton.styleFrom(shape: buttonShape),
    };
    final title = UiPrefs.fontFamily(prefs.titleFont);
    final transitions = prefs.animations == 'off' ? 'none' : prefs.transitions;
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: UiPrefs.fontFamily(prefs.bodyFont),
      visualDensity: density,
      filledButtonTheme: FilledButtonThemeData(style: filled),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: buttonShape)),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r.clamp(0, 16)))),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r + 8))),
      // Fundo próprio (gradiente, capa, imagem): as telas deixam ver o que está atrás.
      scaffoldBackgroundColor: prefs.background == 'solid' ? scheme.surface : Colors.transparent,
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 12)),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.15),
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
      cardTheme: CardThemeData(
        elevation: prefs.cardStyle == 'elevated' ? 3 : 0,
        color: scheme.surfaceContainerLow,
        shape: prefs.cardStyle == 'outlined' ? shape.copyWith(side: BorderSide(color: scheme.outlineVariant)) : shape,
      ),
      pageTransitionsTheme: switch (transitions) {
        'fade' => _all(const _FadeTransitionBuilder()),
        'slide' => _all(const CupertinoPageTransitionsBuilder()),
        'none' => _all(const _NoTransitionBuilder()),
        _ => null,
      },
    );
    if (title == null) return theme;
    // Fonte dos títulos: só nos textos grandes (cabeçalhos, nomes de álbum).
    TextStyle? t(TextStyle? s) => s?.copyWith(fontFamily: title);
    final tt = theme.textTheme;
    return theme.copyWith(
      textTheme: tt.copyWith(
        displayLarge: t(tt.displayLarge),
        displayMedium: t(tt.displayMedium),
        displaySmall: t(tt.displaySmall),
        headlineLarge: t(tt.headlineLarge),
        headlineMedium: t(tt.headlineMedium),
        headlineSmall: t(tt.headlineSmall),
        titleLarge: t(tt.titleLarge),
      ),
    );
  }

  static PageTransitionsTheme _all(PageTransitionsBuilder b) =>
      PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: b});
}

class _FadeTransitionBuilder extends PageTransitionsBuilder {
  const _FadeTransitionBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child);
}

class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}
