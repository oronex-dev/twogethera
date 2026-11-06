import 'package:flutter/material.dart';

enum TwogetheraTheme {
  roseGold,
  emerald,
  amethyst,
  champagne,
  oceanBlue,
  midnightSlate,
}

extension TwogetheraThemeLabel on TwogetheraTheme {
  String get label => switch (this) {
    TwogetheraTheme.roseGold => 'Rose Gold',
    TwogetheraTheme.emerald => 'Emerald',
    TwogetheraTheme.amethyst => 'Amethyst',
    TwogetheraTheme.champagne => 'Champagne',
    TwogetheraTheme.oceanBlue => 'Ocean Blue',
    TwogetheraTheme.midnightSlate => 'Midnight Slate',
  };

  String get storageKey => switch (this) {
    TwogetheraTheme.roseGold => 'rose_gold',
    TwogetheraTheme.emerald => 'emerald',
    TwogetheraTheme.amethyst => 'amethyst',
    TwogetheraTheme.champagne => 'champagne',
    TwogetheraTheme.oceanBlue => 'ocean_blue',
    TwogetheraTheme.midnightSlate => 'midnight_slate',
  };

  static TwogetheraTheme fromStorageKey(Object? value) =>
      TwogetheraTheme.values.firstWhere(
        (theme) => theme.storageKey == value,
        orElse: () => TwogetheraTheme.roseGold,
      );
}

class AppearancePreferences {
  const AppearancePreferences({
    this.mode = ThemeMode.system,
    this.theme = TwogetheraTheme.roseGold,
    this.customHex,
  });

  final ThemeMode mode;
  final TwogetheraTheme theme;
  final String? customHex;

  AppearancePreferences copyWith({
    ThemeMode? mode,
    TwogetheraTheme? theme,
    String? customHex,
    bool clearCustomHex = false,
  }) => AppearancePreferences(
    mode: mode ?? this.mode,
    theme: theme ?? this.theme,
    customHex: clearCustomHex ? null : customHex ?? this.customHex,
  );

  Map<String, dynamic> toJson() => {
    'appearance_mode': switch (mode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    },
    'appearance_theme': theme.storageKey,
    'appearance_custom_hex': customHex?.toUpperCase(),
  };

  factory AppearancePreferences.fromJson(Map<String, dynamic> json) {
    final mode = switch (json['appearance_mode']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final rawHex = json['appearance_custom_hex'];
    final customHex = rawHex is String && parseHexColor(rawHex) != null
        ? '#${rawHex.replaceFirst('#', '').toUpperCase()}'
        : null;
    return AppearancePreferences(
      mode: mode,
      theme: TwogetheraThemeLabel.fromStorageKey(json['appearance_theme']),
      customHex: customHex,
    );
  }
}

abstract interface class AppearancePreferencesRepository {
  Future<AppearancePreferences?> loadAppearancePreferences(String userId);
  Future<void> saveAppearancePreferences(
    String userId,
    AppearancePreferences preferences,
  );
}

class AppearancePreferencesFailure implements Exception {
  const AppearancePreferencesFailure();
}

Color? parseHexColor(String input) {
  final value = input.trim().replaceFirst(RegExp(r'^#'), '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) return null;
  return Color(int.parse('FF$value', radix: 16));
}

@immutable
class ThemePalette {
  const ThemePalette({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.text,
    required this.border,
    required this.accent,
    required this.heroStart,
    required this.heroEnd,
  });

  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color text;
  final Color border;
  final Color accent;
  final Color heroStart;
  final Color heroEnd;
}

abstract final class AppearancePalettes {
  static ThemePalette forTheme(TwogetheraTheme theme, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch ((theme, dark)) {
      (TwogetheraTheme.roseGold, false) => _palette(
        0xFF9B4D69,
        0xFF77617E,
        0xFFFBF7F5,
        0xFFFFFFFF,
        0xFF30242A,
        0xFFE8DADF,
        0xFFC47E89,
        0xFFF8EBED,
        0xFFEDE7F8,
      ),
      (TwogetheraTheme.roseGold, true) => _palette(
        0xFFE9A5B8,
        0xFFC6AFE0,
        0xFF17141A,
        0xFF241F28,
        0xFFF6EDF1,
        0xFF493B47,
        0xFFD48DA0,
        0xFF30243B,
        0xFF382530,
      ),
      (TwogetheraTheme.emerald, false) => _palette(
        0xFF26735E,
        0xFF667D69,
        0xFFF5F9F6,
        0xFFFFFFFF,
        0xFF1E302A,
        0xFFD7E6DC,
        0xFF72A88E,
        0xFFE4F1E9,
        0xFFE5EEE7,
      ),
      (TwogetheraTheme.emerald, true) => _palette(
        0xFF87D6B2,
        0xFFB2C7A0,
        0xFF121B18,
        0xFF1D2923,
        0xFFEAF6EF,
        0xFF354A3F,
        0xFF62B58C,
        0xFF1D332A,
        0xFF29352B,
      ),
      (TwogetheraTheme.amethyst, false) => _palette(
        0xFF694AA0,
        0xFF785887,
        0xFFF8F6FB,
        0xFFFFFFFF,
        0xFF2D2637,
        0xFFE2D9EF,
        0xFFA28BCF,
        0xFFF0EAF8,
        0xFFEAE7F4,
      ),
      (TwogetheraTheme.amethyst, true) => _palette(
        0xFFC5A8F2,
        0xFFD3B9DA,
        0xFF191521,
        0xFF252032,
        0xFFF2ECFA,
        0xFF443A55,
        0xFFB39CDD,
        0xFF30263F,
        0xFF342A3A,
      ),
      (TwogetheraTheme.champagne, false) => _palette(
        0xFF806321,
        0xFF79644C,
        0xFFFBF8F1,
        0xFFFFFFFF,
        0xFF352D22,
        0xFFE8DFC9,
        0xFFB18E47,
        0xFFF5ECD9,
        0xFFF0E9E0,
      ),
      (TwogetheraTheme.champagne, true) => _palette(
        0xFFE1C47B,
        0xFFD2B99C,
        0xFF1C1912,
        0xFF2A251C,
        0xFFF6F1E4,
        0xFF4B4231,
        0xFFD4B365,
        0xFF342D1F,
        0xFF352D27,
      ),
      (TwogetheraTheme.oceanBlue, false) => _palette(
        0xFF356B8C,
        0xFF586F96,
        0xFFF4F8FB,
        0xFFFFFFFF,
        0xFF24313C,
        0xFFD8E3EB,
        0xFF65A6C6,
        0xFFE6F0F6,
        0xFFE9EAF6,
      ),
      (TwogetheraTheme.oceanBlue, true) => _palette(
        0xFF89C6EA,
        0xFFB0B9F0,
        0xFF121920,
        0xFF1D2730,
        0xFFEAF4FA,
        0xFF394A57,
        0xFF6AB6D6,
        0xFF1E303A,
        0xFF282A3A,
      ),
      (TwogetheraTheme.midnightSlate, false) => _palette(
        0xFF4E617C,
        0xFF6B708F,
        0xFFF5F7FA,
        0xFFFFFFFF,
        0xFF242B37,
        0xFFDBE1EA,
        0xFF8595B0,
        0xFFE8EDF5,
        0xFFECEAF4,
      ),
      (TwogetheraTheme.midnightSlate, true) => _palette(
        0xFFB2C4E1,
        0xFFC7B5E3,
        0xFF10151D,
        0xFF1B222D,
        0xFFEBF0F8,
        0xFF364252,
        0xFF91A6C7,
        0xFF232D3A,
        0xFF2B2939,
      ),
    };
  }

  static ThemePalette withCustomPrimary(
    ThemePalette base,
    Color customPrimary,
    Brightness brightness,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: customPrimary,
      brightness: brightness,
      surface: base.surface,
    );
    return ThemePalette(
      primary: customPrimary,
      secondary: scheme.secondary,
      background: base.background,
      surface: base.surface,
      text: base.text,
      border: base.border,
      accent: scheme.tertiary,
      heroStart: Color.lerp(base.heroStart, customPrimary, .16)!,
      heroEnd: Color.lerp(base.heroEnd, scheme.secondary, .14)!,
    );
  }

  static ThemePalette _palette(
    int primary,
    int secondary,
    int background,
    int surface,
    int text,
    int border,
    int accent,
    int heroStart,
    int heroEnd,
  ) => ThemePalette(
    primary: Color(primary),
    secondary: Color(secondary),
    background: Color(background),
    surface: Color(surface),
    text: Color(text),
    border: Color(border),
    accent: Color(accent),
    heroStart: Color(heroStart),
    heroEnd: Color(heroEnd),
  );
}
