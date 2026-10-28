import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

/// Scrollable, bounded content that keeps text scaling and small screens usable.
class ResponsivePage extends StatelessWidget {
  const ResponsivePage({required this.child, super.key});
  final Widget child;

  static const maxContentWidth = AppLayout.maxContent;
  static const wideBreakpoint = 720.0;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth >= wideBreakpoint ? 40.0 : 20.0;
        return SingleChildScrollView(
          key: const ValueKey('page-scroll'),
          padding: EdgeInsets.all(padding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        );
      },
    ),
  );
}
