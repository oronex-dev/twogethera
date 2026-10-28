import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../../shared/widgets/together_mark.dart';

/// Component review only: controls are ephemeral UI state, not planner features.
class DesignStudioScreen extends StatelessWidget {
  const DesignStudioScreen({super.key});
  @override
  Widget build(BuildContext context) => ResponsivePage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PreviewBadge(label: 'The Twogethera collection'),
        const SizedBox(height: 24),
        const SectionHeading(
          title: 'Small details. A shared feeling.',
          description: 'A living preview of our visual language. Try a few details and make yourself at home.',
        ),
        const SizedBox(height: 32),
        const AdaptiveGrid(
          minWidth: 360,
          children: [_IdentityCard(), _PaletteCard()],
        ),
        const SizedBox(height: 24),
        const _InteractionCard(),
        const SizedBox(height: 24),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A quieter kind of typography',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 28),
              Text(
                'Less noise. More us.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'Clear words, generous space, and room to breathe.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'Designed to grow with your text size.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'These controls are for visual exploration. Preview choices reset when you leave the studio.',
        ),
      ],
    ),
  );
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard();
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Two forms. One feeling.',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                BrandColors.of(context).heroStart,
                BrandColors.of(context).heroEnd,
              ],
            ),
          ),
          child: const Center(child: TogetherMark(size: 200)),
        ),
        const SizedBox(height: 20),
        const Text(
          'An original intertwined mark, softened with rose, lilac, and a little reflected light.',
        ),
      ],
    ),
  );
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard();
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Soft color. Clear purpose.',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        for (final entry in const [
          (Color(0xFF8E3F62), 'Rosewood', '#8E3F62'),
          (Color(0xFFBA9CE9), 'Quiet lilac', '#BA9CE9'),
          (Color(0xFFFFE3D5), 'First light', '#FFE3D5'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: entry.$1,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: BrandColors.of(context).border),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(entry.$3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const Text('Expressive accents sit beside calm, readable surfaces.'),
      ],
    ),
  );
}

class _InteractionCard extends StatefulWidget {
  const _InteractionCard();
  @override
  State<_InteractionCard> createState() => _InteractionCardState();
}

class _InteractionCardState extends State<_InteractionCard> {
  bool spacious = true;
  bool lavender = false;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A little interaction',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text('Explore selection, spacing, inputs, and gentle feedback.'),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ChoiceChip(
              label: const Text('Rose accent'),
              selected: !lavender,
              onSelected: (_) => setState(() => lavender = false),
            ),
            ChoiceChip(
              label: const Text('Lavender accent'),
              selected: lavender,
              onSelected: (_) => setState(() => lavender = true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Generous spacing'),
          subtitle: const Text('Adjust the sample below'),
          value: spacious,
          onChanged: (value) => setState(() => spacious = value),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: lavender
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Padding(
            padding: EdgeInsets.all(spacious ? 28 : 16),
            child: Text(
              lavender
                  ? 'A softer shade of together.'
                  : 'A warm little welcome.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: lavender
                    ? Theme.of(context).colorScheme.onSecondaryContainer
                    : Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const TextField(
          maxLength: 80,
          decoration: InputDecoration(
            labelText: 'Try a short note',
            hintText: 'A little moment worth keeping',
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('A small moment, beautifully acknowledged.'),
                  showCloseIcon: true,
                ),
              ),
              child: const Text('Preview feedback'),
            ),
            const OutlinedButton(
              onPressed: null,
              child: Text('Unavailable example'),
            ),
          ],
        ),
      ],
    ),
  );
}
