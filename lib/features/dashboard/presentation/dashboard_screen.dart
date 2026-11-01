import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../../shared/widgets/together_mark.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => ResponsivePage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WelcomeHero(),
        const SizedBox(height: 40),
        const SectionHeading(
          title: 'Our story starts here',
          description:
              'Room for the big dreams. And the beautifully ordinary days.',
        ),
        const SizedBox(height: 24),
        SurfaceCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final text = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A space for two',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Invite your partner with a private, one-time code.',
                  ),
                ],
              );
              final action = FilledButton.tonalIcon(
                onPressed: () => context.go('/partner'),
                icon: const Icon(Icons.favorite_border_rounded),
                label: const Text('Partner linking'),
              );
              if (constraints.maxWidth < 680 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [text, const SizedBox(height: 20), action],
                );
              }
              return Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 24),
                  action,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        const AdaptiveGrid(
          children: [
            IdeaCard(
              icon: Icons.north_east_rounded,
              title: 'A little more someday',
              description: 'The places to go. The things to try. A home for your shared dreams.',
            ),
            IdeaCard(
              icon: Icons.wb_sunny_outlined,
              title: 'Moments that matter',
              description:
                  'Milestones and small celebrations, held a little closer.',
            ),
            IdeaCard(
              icon: Icons.spa_outlined,
              title: 'Life, in your rhythm',
              description:
                  'A calmer way to make room for what matters to both of you.',
            ),
          ],
        ),
        const SizedBox(height: 32),
        SurfaceCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final text = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Made to feel like yours',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Explore the colors, details, and little interactions taking shape.',
                  ),
                ],
              );
              final action = OutlinedButton.icon(
                onPressed: () => context.go('/studio'),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Explore the studio'),
              );
              if (constraints.maxWidth < 680 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [text, const SizedBox(height: 24), action],
                );
              }
              return Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 28),
                  action,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Thoughtfully built for a life together.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
      ],
    ),
  );
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(32),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          BrandColors.of(context).heroStart,
          BrandColors.of(context).heroEnd,
        ],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 600 &&
              MediaQuery.textScalerOf(context).scale(14) <= 20;
          final words = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PreviewBadge(),
              const SizedBox(height: 32),
              Semantics(
                header: true,
                child: Text(
                  'A little space.\nFor the two of you.',
                  style: wide && constraints.maxWidth >= 900
                      ? Theme.of(context).textTheme.displayLarge
                      : Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Make room for shared dreams, meaningful dates, and everyday moments.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => context.go('/studio'),
                label: const Text('Discover the details'),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          );
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 3, child: words),
                const SizedBox(width: 24),
                const Expanded(
                  flex: 2,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TogetherMark(size: 260),
                    ),
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              words,
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerRight,
                child: TogetherMark(size: 144),
              ),
            ],
          );
        },
      ),
    ),
  );
}
