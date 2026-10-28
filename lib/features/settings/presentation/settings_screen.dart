import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme_mode_controller.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../../shared/widgets/together_mark.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ResponsivePage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PreviewBadge(label: 'Your kind of calm'),
        const SizedBox(height: 24),
        const SectionHeading(
          title: 'Make yourself at home',
          description: 'Choose a comfortable appearance. Your choice lasts for this session.',
        ),
        const SizedBox(height: 32),
        AdaptiveGrid(
          minWidth: 360,
          children: [
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set the mood',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  RadioGroup<ThemeMode>(
                    groupValue: ref.watch(themeModeProvider),
                    onChanged: (mode) {
                      if (mode != null) {
                        ref.read(themeModeProvider.notifier).setMode(mode);
                      }
                    },
                    child: Column(
                      children: [
                        for (final mode in ThemeMode.values)
                          RadioListTile<ThemeMode>(
                            contentPadding: EdgeInsets.zero,
                            value: mode,
                            title: Text(switch (mode) {
                              ThemeMode.system => 'System',
                              ThemeMode.light => 'Light',
                              ThemeMode.dark => 'Dark',
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: TogetherMark(size: 140)),
                  Text(
                    'Beautiful at every hour',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Warm daylight or a quieter evening. The same thoughtful details, with a different kind of glow.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Theme.of(context).brightness == Brightness.dark
                        ? 'After-hours palette is active.'
                        : 'Daylight palette is active.',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
