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
    required this.canvas,
    required this.panel,
    required this.border,
    required this.heroStart,
    required this.heroEnd,
  });
  final Color canvas;
  final Color panel;
  final Color border;
  final Color heroStart;
  final Color heroEnd;

  static BrandColors of(BuildContext context) =>
      Theme.of(context).extension<BrandColors>()!;

  @override
  BrandColors copyWith({
    Color? canvas,
    Color? panel,
    Color? border,
    Color? heroStart,
    Color? heroEnd,
  }) => BrandColors(
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
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      border: Color.lerp(border, other.border, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
    );
  }
}
