import 'package:flutter/material.dart';

/// Scrollable, bounded content that keeps text scaling and small screens usable.
class ResponsivePage extends StatelessWidget {
  const ResponsivePage({required this.child, super.key});
  final Widget child;

  static const maxContentWidth = 960.0;
  static const wideBreakpoint = 720.0;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth >= wideBreakpoint ? 40.0 : 20.0;
        return SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: child,
            ),
          ),
        );
      },
    ),
  );
}
