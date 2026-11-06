import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/theme_mode_controller.dart';
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
            onSelected: ref.read(themeModeProvider.notifier).setMode,
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
                      const Text(
                        'Local preview · Synthetic accounts only. Your session stays in memory and ends when the app closes.',
                      ),
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
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
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
    this.action = TextInputAction.done,
  });
  final TextEditingController controller;
  final String label;
  final String fieldKey;
  final bool enabled;
  final String? Function(String?)? validator;
  final VoidCallback? onSubmitted;
  final TextInputAction action;
  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _visible = false;
  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey(widget.fieldKey),
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: !_visible,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    autofillHints: null,
    textInputAction: widget.action,
    validator: widget.validator,
    onFieldSubmitted: (_) => widget.onSubmitted?.call(),
    decoration: InputDecoration(
      labelText: widget.label,
      errorMaxLines: 4,
      suffixIcon: IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        tooltip: '${_visible ? 'Hide' : 'Show'} ${widget.label.toLowerCase()}',
        onPressed: widget.enabled
            ? () => setState(() => _visible = !_visible)
            : null,
        icon: Icon(
          _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
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

String? validateNewPassword(String? value) => (value?.length ?? 0) < 16
    ? 'Use at least 16 characters for your password.'
    : null;

Widget authEmailField(
  TextEditingController controller, {
  required String fieldKey,
  bool localOnly = true,
  bool enabled = true,
  TextInputAction action = TextInputAction.next,
  VoidCallback? onSubmitted,
}) => TextFormField(
  key: ValueKey(fieldKey),
  controller: controller,
  enabled: enabled,
  keyboardType: TextInputType.emailAddress,
  textInputAction: action,
  autocorrect: false,
  enableSuggestions: false,
  autofillHints: null,
  enableIMEPersonalizedLearning: false,
  validator: (value) => validateAccountEmail(value, localOnly: localOnly),
  onFieldSubmitted: (_) => onSubmitted?.call(),
  decoration: const InputDecoration(
    labelText: 'Email address',
    errorMaxLines: 4,
  ),
);
