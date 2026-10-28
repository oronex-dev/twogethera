import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({required this.child, this.padding = 24, super.key});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.title,
    required this.description,
    super.key,
  });
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
      const SizedBox(height: 10),
      Text(
        description,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class PreviewBadge extends StatelessWidget {
  const PreviewBadge({this.label = 'Design preview', super.key});
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    ),
  );
}

/// Content-sized rows wrap rather than cropping scaled text into fixed cards.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({required this.children, this.minWidth = 280, super.key});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns =
          (constraints.maxWidth /
                  (minWidth * scale.clamp(1, 1.6) + AppSpace.md))
              .floor()
              .clamp(1, 3);
      final width =
          (constraints.maxWidth - AppSpace.md * (columns - 1)) / columns;
      return Wrap(
        spacing: AppSpace.md,
        runSpacing: AppSpace.md,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class IdeaCard extends StatelessWidget {
  const IdeaCard({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });
  final IconData icon;
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
        const SizedBox(height: 24),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}
