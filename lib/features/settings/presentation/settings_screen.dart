import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../../shared/widgets/together_mark.dart';
import '../../appearance/application/appearance_controller.dart';
import '../../appearance/domain/appearance_preferences.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _hexController = TextEditingController();
  Color? _previewColor;
  String? _hexError;

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appearanceControllerProvider);
    final preferences = state.preferences;
    final busy =
        state.saving ||
        state.loading ||
        (state.userId != null && !state.loaded);
    final mode = preferences.mode;
    final effectiveBrightness = Theme.of(context).brightness;
    final previewColor = _previewColor;
    final previewPreferences = previewColor == null
        ? null
        : preferences.copyWith(
            customHex:
                '#${previewColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
          );

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PreviewBadge(label: 'Your kind of calm'),
          const SizedBox(height: 24),
          SectionHeading(
            title: 'Make yourself at home',
            description: state.userId == null
                ? 'Choose a palette and preview it. Sign in to save your appearance across devices.'
                : 'Your appearance is personal to your account and follows you across devices.',
          ),
          const SizedBox(height: 28),
          if (kDebugMode) ...[
            OutlinedButton.icon(
              onPressed: () => context.go('/auth/welcome'),
              icon: const Icon(Icons.person_outline_rounded),
              label: const Text('Explore local authentication'),
            ),
            const SizedBox(height: 20),
          ],
          if (state.loading) const LinearProgressIndicator(),
          if (state.error != null || state.notice != null) ...[
            _StatusMessage(
              text: state.error ?? state.notice!,
              isError: state.error != null,
              onRetry: state.error == null || state.userId == null
                  ? null
                  : () => ref
                        .read(appearanceControllerProvider.notifier)
                        .load(state.userId!, force: true),
            ),
            const SizedBox(height: 16),
          ],
          AdaptiveGrid(
            minWidth: 370,
            children: [
              _ModeCard(
                selected: mode,
                disabled: busy,
                onChanged: (value) => ref
                    .read(appearanceControllerProvider.notifier)
                    .setMode(value),
              ),
              _ThemeCard(
                selected: preferences.theme,
                customActive: preferences.customHex != null,
                disabled: busy,
                onSelected: (theme) => ref
                    .read(appearanceControllerProvider.notifier)
                    .selectTheme(theme),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom color',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter a six-digit HEX color. Preview it first; your selected theme keeps its calm surfaces and gets a coordinated accent palette.',
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final input = TextField(
                      controller: _hexController,
                      enabled: !busy,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      maxLength: 7,
                      decoration: InputDecoration(
                        labelText: 'HEX color',
                        hintText: '#8E3F62',
                        prefixIcon: const Icon(Icons.color_lens_outlined),
                        errorText: _hexError,
                        counterText: '',
                      ),
                      onChanged: (_) {
                        if (_hexError != null || _previewColor != null) {
                          setState(() {
                            _hexError = null;
                            _previewColor = null;
                          });
                        }
                      },
                    );
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: busy ? null : _previewHex,
                          child: const Text('Preview color'),
                        ),
                        FilledButton(
                          onPressed: busy || previewColor == null
                              ? null
                              : () async {
                                  final applied = await ref
                                      .read(
                                        appearanceControllerProvider.notifier,
                                      )
                                      .applyCustomColor(previewColor);
                                  if (applied && mounted) {
                                    setState(() => _previewColor = null);
                                  }
                                },
                          child: const Text('Apply color'),
                        ),
                        TextButton(
                          onPressed: busy || preferences.customHex == null
                              ? null
                              : () => ref
                                    .read(appearanceControllerProvider.notifier)
                                    .resetCustomColor(),
                          child: Text('Reset to ${preferences.theme.label}'),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 620) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [input, const SizedBox(height: 12), actions],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: input),
                        const SizedBox(width: 16),
                        Expanded(child: actions),
                      ],
                    );
                  },
                ),
                if (previewPreferences != null) ...[
                  const SizedBox(height: 20),
                  _AppearancePreview(
                    preferences: previewPreferences,
                    brightness: effectiveBrightness,
                    title: 'Preview · not applied',
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  _AppearancePreview(
                    preferences: preferences,
                    brightness: effectiveBrightness,
                    title: 'Live appearance preview',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Twogethera, your way'),
                      SizedBox(height: 6),
                      Text('A considered palette for every hour.'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const TogetherMark(size: 76),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _previewHex() {
    final color = parseHexColor(_hexController.text);
    setState(() {
      _previewColor = color;
      _hexError = color == null
          ? 'Enter a valid HEX color, such as #8E3F62.'
          : null;
    });
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.disabled,
    required this.onChanged,
  });

  final ThemeMode selected;
  final bool disabled;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Appearance mode', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('System mode follows your device preference.'),
        const SizedBox(height: 12),
        RadioGroup<ThemeMode>(
          groupValue: selected,
          onChanged: (mode) {
            if (!disabled && mode != null) onChanged(mode);
          },
          child: Column(
            children: [
              for (final mode in ThemeMode.values)
                RadioListTile<ThemeMode>(
                  contentPadding: EdgeInsets.zero,
                  value: mode,
                  title: Text(switch (mode) {
                    ThemeMode.system => 'System default',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                  subtitle: mode == ThemeMode.system
                      ? const Text('Changes with your device')
                      : null,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.selected,
    required this.customActive,
    required this.disabled,
    required this.onSelected,
  });

  final TwogetheraTheme selected;
  final bool customActive;
  final bool disabled;
  final ValueChanged<TwogetheraTheme> onSelected;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Curated themes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('Each theme includes a matched light and dark palette.'),
        const SizedBox(height: 18),
        for (final theme in TwogetheraTheme.values)
          _ThemeChoice(
            theme: theme,
            selected: selected == theme,
            disabled: disabled,
            onTap: () => onSelected(theme),
          ),
        if (customActive) ...[
          const SizedBox(height: 8),
          Text(
            'A custom accent is layered over ${selected.label}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    ),
  );
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.theme,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final TwogetheraTheme theme;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final swatch = AppearancePalettes.forTheme(
      theme,
      Theme.of(context).brightness,
    );
    final border = selected
        ? Theme.of(context).colorScheme.primary
        : BrandColors.of(context).border;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${theme.label}${selected ? ', selected' : ''}',
        child: Material(
          color: swatch.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: disabled ? null : onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border, width: selected ? 2 : 1),
              ),
              child: Row(
                children: [
                  _SwatchDot(color: swatch.primary),
                  const SizedBox(width: 5),
                  _SwatchDot(color: swatch.secondary),
                  const SizedBox(width: 5),
                  _SwatchDot(color: swatch.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      theme.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: swatch.text,
                        fontWeight: selected ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: border, size: 21),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    ),
  );
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({
    required this.preferences,
    required this.brightness,
    required this.title,
  });

  final AppearancePreferences preferences;
  final Brightness brightness;
  final String title;

  @override
  Widget build(BuildContext context) => Theme(
    data: brightness == Brightness.dark
        ? AppTheme.dark(preferences)
        : AppTheme.light(preferences),
    child: Builder(
      builder: (context) => Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: BrandColors.of(context).border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.favorite_rounded,
                          color: BrandColors.of(context).accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'A day to remember',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'Thoughtful plans, together.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: null, child: const Text('Save')),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: BrandColors.of(context).panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: BrandColors.of(context).border),
              ),
              child: Wrap(
                spacing: 14,
                runSpacing: 8,
                children: const [
                  _PreviewNavItem(
                    icon: Icons.home_outlined,
                    label: 'Summary',
                    selected: true,
                  ),
                  _PreviewNavItem(
                    icon: Icons.favorite_border,
                    label: 'Planner',
                  ),
                  _PreviewNavItem(icon: Icons.person_outline, label: 'Profile'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PreviewNavItem extends StatelessWidget {
  const _PreviewNavItem({
    required this.icon,
    required this.label,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.text,
    required this.isError,
    this.onRetry,
  });
  final String text;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Material(
    color: isError
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
