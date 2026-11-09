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
import '../../legal/presentation/legal_document_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _personalColorSwatches = <(String, Color)>[
    ('Rose', Color(0xFF9B4D69)),
    ('Lavender', Color(0xFF77617E)),
    ('Plum', Color(0xFF694AA0)),
    ('Ocean', Color(0xFF356B8C)),
    ('Emerald', Color(0xFF26735E)),
    ('Champagne', Color(0xFF806321)),
  ];
  final _hexController = TextEditingController();
  Color? _previewColor;
  String? _hexError;
  GradientPreset? _previewGradientPreset;
  GradientDirection _gradientDirection = GradientDirection.diagonal;
  Color _gradientStart = const Color(0xFFF8EBED);
  Color _gradientEnd = const Color(0xFFEDE7F8);
  double _primaryHue = 338;
  double _startHue = 338;
  double _endHue = 272;

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
    if (_previewGradientPreset == null) {
      _gradientDirection = preferences.gradientDirection;
      if (preferences.gradientPreset == GradientPreset.custom) {
        _gradientStart =
            parseHexColor(preferences.gradientStartHex ?? '') ??
            const Color(0xFFF8EBED);
        _gradientEnd =
            parseHexColor(preferences.gradientEndHex ?? '') ??
            const Color(0xFFEDE7F8);
        _startHue = HSVColor.fromColor(_gradientStart).hue;
        _endHue = HSVColor.fromColor(_gradientEnd).hue;
      }
    }
    final previewColor = _previewColor;
    final appearancePreview = previewColor == null
        ? preferences
        : preferences.copyWith(customHex: _toHex(previewColor));
    final previewPreset = _previewGradientPreset;
    final previewPreferences = previewPreset == null
        ? (previewColor == null ? null : appearancePreview)
        : appearancePreview.copyWith(
            gradientPreset: previewPreset,
            gradientDirection: _gradientDirection,
            gradientStartHex: previewPreset == GradientPreset.custom
                ? _toHex(_gradientStart)
                : null,
            gradientEndHex: previewPreset == GradientPreset.custom
                ? _toHex(_gradientEnd)
                : null,
            clearGradientColors: previewPreset != GradientPreset.custom,
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
          Text(
            'Personalization',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
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
                  'Choose a swatch or adjust the hue. The coordinated accent preview keeps your selected theme’s calm surfaces.',
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final swatch in _personalColorSwatches)
                      Semantics(
                        button: true,
                        label: swatch.$1,
                        selected: previewColor == swatch.$2,
                        child: Tooltip(
                          message: swatch.$1,
                          child: InkWell(
                            onTap: busy
                                ? null
                                : () => setState(() {
                                    _previewColor = swatch.$2;
                                    _hexController.text = _toHex(swatch.$2);
                                    _hexError = null;
                                  }),
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: swatch.$2,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: previewColor == swatch.$2
                                      ? Theme.of(context).colorScheme.onSurface
                                      : BrandColors.of(context).border,
                                  width: previewColor == swatch.$2 ? 3 : 1,
                                ),
                              ),
                              child: previewColor == swatch.$2
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: _contrastTextForSwatch(swatch.$2),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 76, child: Text('Hue')),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 360,
                        divisions: 360,
                        label: '${_primaryHue.round()}°',
                        value: _primaryHue,
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                _primaryHue = value;
                                _previewColor = HSVColor.fromAHSV(
                                  1,
                                  value,
                                  .58,
                                  .58,
                                ).toColor();
                                _hexController.text = _toHex(_previewColor!);
                              }),
                      ),
                    ),
                  ],
                ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gradient identity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Preview a soft brand gradient, then apply it to the app’s gradient surfaces.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in GradientPreset.values)
                      ChoiceChip(
                        label: Text(preset.label),
                        selected:
                            (previewPreset ?? preferences.gradientPreset) ==
                            preset,
                        onSelected: busy
                            ? null
                            : (_) => setState(() {
                                _previewGradientPreset = preset;
                                final colors = AppearancePalettes.gradientFor(
                                  preferences.copyWith(gradientPreset: preset),
                                  effectiveBrightness,
                                );
                                if (preset != GradientPreset.custom) {
                                  _gradientStart = colors.$1;
                                  _gradientEnd = colors.$2;
                                }
                              }),
                      ),
                  ],
                ),
                if ((previewPreset ?? preferences.gradientPreset) ==
                    GradientPreset.custom) ...[
                  const SizedBox(height: 12),
                  _HueControl(
                    label: 'First color',
                    value: _startHue,
                    color: _gradientStart,
                    disabled: busy,
                    onChanged: (hue) => setState(() {
                      _previewGradientPreset = GradientPreset.custom;
                      _startHue = hue;
                      _gradientStart = HSVColor.fromAHSV(
                        1,
                        hue,
                        .28,
                        .96,
                      ).toColor();
                    }),
                  ),
                  _HueControl(
                    label: 'Second color',
                    value: _endHue,
                    color: _gradientEnd,
                    disabled: busy,
                    onChanged: (hue) => setState(() {
                      _previewGradientPreset = GradientPreset.custom;
                      _endHue = hue;
                      _gradientEnd = HSVColor.fromAHSV(
                        1,
                        hue,
                        .24,
                        .92,
                      ).toColor();
                    }),
                  ),
                ],
                const SizedBox(height: 12),
                SegmentedButton<GradientDirection>(
                  segments: [
                    for (final direction in GradientDirection.values)
                      ButtonSegment(
                        value: direction,
                        label: Text(direction.label),
                      ),
                  ],
                  selected: {_gradientDirection},
                  onSelectionChanged: busy
                      ? null
                      : (value) => setState(() {
                          _gradientDirection = value.first;
                          _previewGradientPreset ??= preferences.gradientPreset;
                        }),
                ),
                const SizedBox(height: 14),
                if (previewPreferences != null)
                  _AppearancePreview(
                    preferences: previewPreferences,
                    brightness: effectiveBrightness,
                    title: 'Gradient preview · not applied',
                  )
                else
                  _AppearancePreview(
                    preferences: preferences,
                    brightness: effectiveBrightness,
                    title: 'Current gradient',
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final controller = ref.read(
                                appearanceControllerProvider.notifier,
                              );
                              final preset =
                                  previewPreset ?? preferences.gradientPreset;
                              final saved = preset == GradientPreset.custom
                                  ? await controller.applyCustomGradient(
                                      start: _gradientStart,
                                      end: _gradientEnd,
                                      direction: _gradientDirection,
                                    )
                                  : await controller.selectGradientPreset(
                                      preset,
                                      direction: _gradientDirection,
                                    );
                              if (saved && mounted) {
                                setState(() => _previewGradientPreset = null);
                              }
                            },
                      child: const Text('Apply gradient'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final saved = await ref
                                  .read(appearanceControllerProvider.notifier)
                                  .selectGradientPreset(
                                    GradientPreset.roseDawn,
                                  );
                              if (saved && mounted) {
                                setState(() {
                                  _previewGradientPreset = null;
                                  _gradientDirection =
                                      GradientDirection.diagonal;
                                });
                              }
                            },
                      child: const Text('Reset gradient'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Text size',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'This preference adjusts the app’s text while preserving your device text scaling.',
                ),
                const SizedBox(height: 12),
                SegmentedButton<PersonalFontSize>(
                  segments: [
                    for (final size in PersonalFontSize.values)
                      ButtonSegment(value: size, label: Text(size.label)),
                  ],
                  selected: {preferences.fontSize},
                  onSelectionChanged: busy
                      ? null
                      : (selection) => ref
                            .read(appearanceControllerProvider.notifier)
                            .setFontSize(selection.first),
                ),
                const SizedBox(height: 12),
                Text(
                  'A little more room for what matters.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
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
          const SizedBox(height: 12),
          const SurfaceCard(child: LegalDocumentLinks()),
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

  String _toHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Color _contrastTextForSwatch(Color color) {
    final luminance = color.computeLuminance();
    final whiteContrast = 1.05 / (luminance + .05);
    final blackContrast = (luminance + .05) / .05;
    return blackContrast >= whiteContrast ? Colors.black : Colors.white;
  }
}

class _HueControl extends StatelessWidget {
  const _HueControl({
    required this.label,
    required this.value,
    required this.color,
    required this.disabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Color color;
  final bool disabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 92,
        child: Row(
          children: [
            CircleAvatar(radius: 9, backgroundColor: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, maxLines: 1)),
          ],
        ),
      ),
      Expanded(
        child: Slider(
          min: 0,
          max: 360,
          divisions: 360,
          label: '${value.round()}°',
          value: value,
          onChanged: disabled ? null : onChanged,
        ),
      ),
    ],
  );
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
            Container(
              height: 56,
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: BrandColors.of(context).heroBegin,
                  end: BrandColors.of(context).heroFinish,
                  colors: [
                    BrandColors.of(context).heroStart,
                    BrandColors.of(context).heroEnd,
                  ],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: BrandColors.of(context).border),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    'A softer way to plan together',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ),
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
