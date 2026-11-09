import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../core/config/app_config.dart';
import '../../appearance/application/appearance_controller.dart';
import '../domain/password_policy.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../../shared/widgets/together_mark.dart';
import '../application/auth_controller.dart';
import '../domain/auth_repository.dart';

/// Uses the existing palette and vector mark; no images or persistence.
class AuthFrame extends ConsumerWidget {
  const AuthFrame({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    required this.onBack,
    this.backLabel = 'Back to sign-in',
  });
  final String title;
  final String description;
  final Widget child;
  final VoidCallback onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BrandColors.of(context);
    final theme = Theme.of(context);
    final environment = ref.watch(appConfigProvider).environment;
    final disclosure = switch (environment) {
      AppEnvironment.development => 'Local preview · Synthetic accounts only. Your session stays in memory and ends when the app closes.',
      AppEnvironment.staging => 'Private beta staging · Your session stays in memory and ends when the app closes.',
      AppEnvironment.production =>
        'For your privacy, sign in again after refreshing or closing this tab.',
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: backLabel,
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Twogethera'),
        actions: [
          IconButton(
            tooltip: 'Go to Summary',
            onPressed: () => context.go('/'),
            icon: const TogetherMark(size: 34),
          ),
          PopupMenuButton<ThemeMode>(
            tooltip: 'Choose appearance',
            initialValue: ref.watch(themeModeProvider),
            onSelected: ref.read(appearanceControllerProvider.notifier).setMode,
            icon: const Icon(Icons.contrast_rounded),
            itemBuilder: (_) => [
              for (final mode in ThemeMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Text(switch (mode) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ResponsivePage(
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final split =
                  constraints.maxWidth >= 1000 &&
                  MediaQuery.textScalerOf(context).scale(16) < 24;
              final form = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!split) ...[
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: TogetherMark(size: 64),
                        ),
                        const SizedBox(height: 24),
                      ],
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(description, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 28),
                      child,
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 12),
                      Text(disclosure),
                    ],
                  ),
                ),
              );
              if (!split) return Center(child: form);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: colors.heroBegin,
                          end: colors.heroFinish,
                          colors: [colors.heroStart, colors.heroEnd],
                        ),
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(color: colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const TogetherMark(size: 140),
                          const SizedBox(height: 40),
                          Text(
                            'A little closer.\nEvery day.',
                            style: theme.textTheme.displaySmall,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'A thoughtful place for the life you share.',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 40),
                          const Text('Made for your everyday moments.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                  Expanded(
                    child: Align(alignment: Alignment.topRight, child: form),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class AuthFeedback extends StatelessWidget {
  const AuthFeedback({super.key, required this.state});
  final AuthViewState state;
  @override
  Widget build(BuildContext context) {
    final busy =
        state.phase == AuthPhase.loading || state.phase == AuthPhase.refreshing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(
              semanticsLabel: 'Checking local account access',
            ),
          ),
        if (state.problem != null || state.notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Semantics(
              liveRegion: true,
              child: AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                alignment: Alignment.topLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.problem != null) ...[
                      const Icon(Icons.info_outline_rounded),
                      const SizedBox(height: 8),
                      Text(AuthFailure(state.problem!).message),
                    ],
                    if (state.notice != null) Text(state.notice!),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.fieldKey,
    this.enabled = true,
    this.validator,
    this.onSubmitted,
    this.onChanged,
    this.showRequirements = false,
    this.action = TextInputAction.done,
  });
  final TextEditingController controller;
  final String label;
  final String fieldKey;
  final bool enabled;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool showRequirements;
  final TextInputAction action;
  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _visible = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        key: ValueKey(widget.fieldKey),
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        obscureText: !_visible,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        autofillHints: null,
        textInputAction: widget.action,
        autovalidateMode: widget.showRequirements
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        validator: widget.validator,
        onChanged: widget.onChanged,
        onFieldSubmitted: (_) => widget.onSubmitted?.call(),
        decoration: InputDecoration(
          labelText: widget.label,
          errorMaxLines: 4,
          suffixIcon: IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip:
                '${_visible ? 'Hide' : 'Show'} ${widget.label.toLowerCase()}',
            onPressed: widget.enabled
                ? () => setState(() => _visible = !_visible)
                : null,
            icon: Icon(
              _visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
      ),
      if (widget.showRequirements)
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final visible = _focusNode.hasFocus || value.text.isNotEmpty;
            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            return AnimatedSize(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: visible
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _PasswordRequirementsPanel(
                        requirements: evaluatePassword(value.text),
                        reduceMotion: reduceMotion,
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            );
          },
        ),
    ],
  );
}

class _PasswordRequirementsPanel extends StatelessWidget {
  const _PasswordRequirementsPanel({
    required this.requirements,
    required this.reduceMotion,
  });

  final PasswordRequirements requirements;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final checks = <(String, bool)>[
      ('At least 8 characters', requirements.minimumLength),
      ('One uppercase letter (A–Z)', requirements.uppercase),
      ('One lowercase letter (a–z)', requirements.lowercase),
      ('One number (0–9)', requirements.number),
      ('One special character', requirements.special),
    ];

    return Semantics(
      container: true,
      label: 'Password requirements. Strength: ${requirements.strength}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < checks.length; index++)
            _PasswordRequirementRow(
              key: ValueKey('password-rule-$index-${checks[index].$2}'),
              label: checks[index].$1,
              met: checks[index].$2,
              color: color,
              neutralColor: theme.colorScheme.onSurfaceVariant,
              duration: duration,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Password strength',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                requirements.strength,
                key: const ValueKey('password-strength-label'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Semantics(
            label:
                'Password strength ${requirements.completedCount} of 5 requirements',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  end: requirements.completedCount / checks.length,
                ),
                duration: duration,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: color,
                  semanticsLabel: 'Password strength',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordRequirementRow extends StatelessWidget {
  const _PasswordRequirementRow({
    super.key,
    required this.label,
    required this.met,
    required this.color,
    required this.neutralColor,
    required this.duration,
  });

  final String label;
  final bool met;
  final Color color;
  final Color neutralColor;
  final Duration duration;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, ${met ? 'met' : 'not met'}',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 24,
            child: Center(
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Icon(
                  met ? Icons.check_circle_rounded : Icons.circle_outlined,
                  key: ValueKey(met),
                  size: 16,
                  color: met ? color : neutralColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: duration,
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: met ? color : neutralColor),
              child: Text(label),
            ),
          ),
        ],
      ),
    ),
  );
}

String? validateLocalEmail(String? value) {
  final email = value?.trim() ?? '';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  if (!email.toLowerCase().endsWith('@example.invalid')) {
    return 'Use a synthetic @example.invalid address in this local preview.';
  }
  return null;
}

String? validateAccountEmail(String? value, {required bool localOnly}) {
  if (localOnly) return validateLocalEmail(value);
  final email = value?.trim() ?? '';
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
      ? null
      : 'Enter a valid email address.';
}

Widget authEmailField(
  TextEditingController controller, {
  required String fieldKey,
  bool localOnly = true,
  bool enabled = true,
  ValueChanged<String>? onChanged,
  TextInputAction action = TextInputAction.next,
  VoidCallback? onSubmitted,
}) => TextFormField(
  key: ValueKey(fieldKey),
  controller: controller,
  enabled: enabled,
  keyboardType: TextInputType.emailAddress,
  textInputAction: action,
  autovalidateMode: AutovalidateMode.onUserInteraction,
  autocorrect: false,
  enableSuggestions: false,
  autofillHints: null,
  enableIMEPersonalizedLearning: false,
  onChanged: onChanged,
  validator: (value) => validateAccountEmail(value, localOnly: localOnly),
  onFieldSubmitted: (_) => onSubmitted?.call(),
  decoration: const InputDecoration(
    labelText: 'Email address',
    errorMaxLines: 4,
  ),
);
