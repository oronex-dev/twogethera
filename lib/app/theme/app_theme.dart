import 'package:flutter/material.dart';

import 'design_tokens.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = BrandColors(
      canvas: dark ? const Color(0xFF17141C) : const Color(0xFFFAF8F6),
      panel: dark ? const Color(0xFF231F2A) : const Color(0xFFFFFFFF),
      border: dark ? const Color(0xFF443A4C) : const Color(0xFFE7DFE7),
      heroStart: dark ? const Color(0xFF30243B) : const Color(0xFFF8EBED),
      heroEnd: dark ? const Color(0xFF382530) : const Color(0xFFEDE7F8),
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8E3F62),
      secondary: const Color(0xFF75528C),
      brightness: brightness,
      surface: colors.panel,
    );
    final text =
        (dark
                ? Typography.material2021().white
                : Typography.material2021().black)
            .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
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
}
