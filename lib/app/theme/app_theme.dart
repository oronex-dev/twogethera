import 'package:flutter/material.dart';

import '../../features/appearance/domain/appearance_preferences.dart';
import 'design_tokens.dart';

abstract final class AppTheme {
  static ThemeData light([
    AppearancePreferences preferences = const AppearancePreferences(),
  ]) => _build(Brightness.light, preferences);
  static ThemeData dark([
    AppearancePreferences preferences = const AppearancePreferences(),
  ]) => _build(Brightness.dark, preferences);

  static ThemeData _build(
    Brightness brightness,
    AppearancePreferences preferences,
  ) {
    final dark = brightness == Brightness.dark;
    var palette = AppearancePalettes.forTheme(preferences.theme, brightness);
    final custom = preferences.customHex;
    if (custom != null) {
      final color = parseHexColor(custom);
      if (color != null) {
        palette = AppearancePalettes.withCustomPrimary(
          palette,
          color,
          brightness,
        );
      }
    }
    final colors = BrandColors(
      primary: palette.primary,
      secondary: palette.secondary,
      text: palette.text,
      accent: palette.accent,
      canvas: palette.background,
      panel: palette.surface,
      border: palette.border,
      heroStart: palette.heroStart,
      heroEnd: palette.heroEnd,
    );
    final generated = ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: brightness,
      surface: palette.surface,
    );
    final scheme = generated.copyWith(
      primary: palette.primary,
      onPrimary: _contrastText(palette.primary),
      secondary: palette.secondary,
      onSecondary: _contrastText(palette.secondary),
      tertiary: palette.accent,
      onTertiary: _contrastText(palette.accent),
      surface: palette.surface,
      onSurface: palette.text,
      outline: palette.border,
    );
    final text =
        (dark
                ? Typography.material2021().white
                : Typography.material2021().black)
            .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      primaryColor: palette.primary,
      extensions: [colors],
      scaffoldBackgroundColor: colors.canvas,
      visualDensity: VisualDensity.standard,
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.copyWith(
          fontSize: 54,
          height: 1.08,
          fontWeight: FontWeight.w600,
          letterSpacing: -2,
        ),
        headlineLarge: text.headlineLarge?.copyWith(
          fontSize: 34,
          height: 1.15,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.6),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.5),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        foregroundColor: scheme.onSurface,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.panel,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: colors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.panel,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: colors.border),
    );
  }

  static Color _contrastText(Color background) {
    final luminance = background.computeLuminance();
    final lightContrast = 1.05 / (luminance + .05);
    final darkContrast = (luminance + .05) / .05;
    return darkContrast >= lightContrast ? Colors.black : Colors.white;
  }
}
