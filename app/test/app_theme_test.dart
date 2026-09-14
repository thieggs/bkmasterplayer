import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_musica/data/ui_prefs.dart';
import 'package:player_musica/ui/theme/app_theme.dart';

/// O tema como era antes da personalização gráfica (commit 56a9681): com as
/// preferências padrão, o novo tem de sair igual.
ThemeData _oldBuild(ColorScheme scheme, {bool amoled = false, String density = 'auto', double radius = 12}) {
  final isDesktop = switch (ThemeData().platform) {
    TargetPlatform.linux || TargetPlatform.windows || TargetPlatform.macOS => true,
    _ => false,
  };
  if (amoled && scheme.brightness == Brightness.dark) {
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF101010),
      surfaceContainerHigh: const Color(0xFF161616),
      surfaceContainerHighest: const Color(0xFF1C1C1C),
    );
  }
  final d = switch (density) {
    'compact' => VisualDensity.compact,
    'comfortable' => VisualDensity.comfortable,
    'standard' => VisualDensity.standard,
    _ => isDesktop ? VisualDensity.compact : VisualDensity.standard,
  };
  final r = radius;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: d,
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
    cardTheme: CardThemeData(elevation: 0, color: scheme.surfaceContainerLow, shape: shape),
  );
}

/// Comparação campo a campo do que o app usa (os estilos de botão guardam
/// objetos sem igualdade por valor, então compara o que eles resolvem).
void _expectSame(ThemeData a, ThemeData b) {
  expect(a.colorScheme, b.colorScheme);
  expect(a.visualDensity, b.visualDensity);
  expect(a.textTheme, b.textTheme);
  expect(a.scaffoldBackgroundColor, b.scaffoldBackgroundColor);
  expect(a.cardTheme, b.cardTheme);
  expect(a.chipTheme, b.chipTheme);
  expect(a.dialogTheme, b.dialogTheme);
  expect(a.sliderTheme, b.sliderTheme);
  expect(a.listTileTheme, b.listTileTheme);
  expect(a.tooltipTheme, b.tooltipTheme);
  expect(a.pageTransitionsTheme, b.pageTransitionsTheme);
  for (final (x, y) in [
    (a.filledButtonTheme.style!, b.filledButtonTheme.style!),
    (a.outlinedButtonTheme.style!, b.outlinedButtonTheme.style!),
  ]) {
    expect(x.shape?.resolve({}), y.shape?.resolve({}));
    expect(x.backgroundColor?.resolve({}), y.backgroundColor?.resolve({}));
    expect(x.foregroundColor?.resolve({}), y.foregroundColor?.resolve({}));
  }
}

void main() {
  for (final b in Brightness.values) {
    test('padrão igual ao original ($b)', () {
      final scheme = AppTheme.seeded(const UiPrefs(), b);
      expect(scheme, ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF), brightness: b));
      _expectSame(AppTheme.build(scheme), _oldBuild(scheme));
    });

    test('AMOLED, cantos e densidade como antes ($b)', () {
      const prefs = UiPrefs(amoled: true, radius: 20, density: 'compact');
      final raw = ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF), brightness: b);
      _expectSame(
        AppTheme.build(AppTheme.finish(raw, prefs), prefs: prefs),
        _oldBuild(raw, amoled: true, density: 'compact', radius: 20),
      );
    });
  }

  test('as opções mudam mesmo o tema', () {
    const prefs = UiPrefs(bodyFont: 'nunito', titleFont: 'bebas', buttonStyle: 'tonal', background: 'image', transitions: 'none');
    final t = AppTheme.build(AppTheme.seeded(prefs, Brightness.dark), prefs: prefs);
    expect(t.textTheme.bodyMedium?.fontFamily, 'Nunito');
    expect(t.textTheme.headlineMedium?.fontFamily, 'Bebas Neue');
    expect(t.scaffoldBackgroundColor, Colors.transparent);
    expect(t.filledButtonTheme.style!.backgroundColor?.resolve({}), t.colorScheme.secondaryContainer);
    expect(t.pageTransitionsTheme, isNot(const PageTransitionsTheme()));
  });

  test('cores à mão por cima da paleta, com texto legível', () {
    const prefs = UiPrefs(colors: {'primary': 0xFFFFEB3B, 'background': 0xFF0B0B0B});
    final s = AppTheme.seeded(prefs, Brightness.dark);
    expect(s.primary, const Color(0xFFFFEB3B));
    expect(s.onPrimary, Colors.black);
    expect(s.surface, const Color(0xFF0B0B0B));
    expect(s.onSurface, Colors.white);
  });

  test('todas as combinações de paleta montam', () {
    for (final v in UiPrefs.variants) {
      for (final b in Brightness.values) {
        for (final c in [-1.0, 0.0, 1.0]) {
          final prefs = UiPrefs(variant: v, contrast: c);
          expect(() => AppTheme.build(AppTheme.seeded(prefs, b), prefs: prefs), returnsNormally);
        }
      }
    }
  });
}
