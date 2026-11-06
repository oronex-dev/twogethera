import 'package:flutter/material.dart';

abstract final class AppSpace {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 20.0;
  static const lg = 28.0;
  static const xl = 40.0;
}

abstract final class AppLayout {
  static const tablet = 600.0;
  static const desktop = 1100.0;
  static const maxContent = 1200.0;
}

@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.primary,
    required this.secondary,
    required this.text,
    required this.accent,
    required this.canvas,
    required this.panel,
    required this.border,
    required this.heroStart,
    required this.heroEnd,
  });
  final Color primary;
  final Color secondary;
  final Color text;
  final Color accent;
  final Color canvas;
  final Color panel;
  final Color border;
  final Color heroStart;
  final Color heroEnd;

  static BrandColors of(BuildContext context) =>
      Theme.of(context).extension<BrandColors>()!;

  @override
  BrandColors copyWith({
    Color? primary,
    Color? secondary,
    Color? text,
    Color? accent,
    Color? canvas,
    Color? panel,
    Color? border,
    Color? heroStart,
    Color? heroEnd,
  }) => BrandColors(
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    text: text ?? this.text,
    accent: accent ?? this.accent,
    canvas: canvas ?? this.canvas,
    panel: panel ?? this.panel,
    border: border ?? this.border,
    heroStart: heroStart ?? this.heroStart,
    heroEnd: heroEnd ?? this.heroEnd,
  );

  @override
  BrandColors lerp(BrandColors? other, double t) {
    if (other == null) return this;
    return BrandColors(
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      text: Color.lerp(text, other.text, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      border: Color.lerp(border, other.border, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
    );
  }
}
