import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/local_auth_config.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../../shared/widgets/together_mark.dart';
import '../application/auth_controller.dart';
import '../domain/auth_repository.dart';

class LocalAuthScreen extends ConsumerStatefulWidget {
  const LocalAuthScreen({super.key});
  @override
  ConsumerState<LocalAuthScreen> createState() => _LocalAuthScreenState();
}

class _LocalAuthScreenState extends ConsumerState<LocalAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(localAuthConfigProvider);
    final state = ref.watch(authControllerProvider);
    final busy =
        state.phase == AuthPhase.loading || state.phase == AuthPhase.refreshing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local authentication'),
        leading: IconButton(
          tooltip: 'Back to preview',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: ResponsivePage(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TogetherMark(size: 80),
                  const SizedBox(height: 24),
                  const PreviewBadge(label: 'Development proof · memory only'),
                  const SizedBox(height: 24),
                  const SectionHeading(
                    title: 'A thoughtful sign-in.',
                    description: 'Use a synthetic @example.invalid account on the local test backend. This proof does not connect partners or load planner data.',
                  ),
                  const SizedBox(height: 24),
                  if (config == null)
                    Text(const AuthFailure(AuthProblem.configuration).message)
                  else ...[
                    AutofillGroup(
                      onDisposeAction: AutofillContextAction.cancel,
                      child: Column(
                        children: [
                          TextField(
                            controller: _email,
                            enabled: !busy,
                            key: const ValueKey('auth-email'),
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: null,
                            enableIMEPersonalizedLearning: false,
                            decoration: const InputDecoration(
                              labelText: 'Synthetic email',
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _password,
                            enabled: !busy,
                            key: const ValueKey('auth-password'),
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: null,
                            enableIMEPersonalizedLearning: false,
                            decoration: const InputDecoration(
                              labelText: 'Test password',
                            ),
                            onSubmitted: busy ? null : (_) => _submit(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: Text(
                        busy ? 'Checking local access…' : 'Sign in locally',
                      ),
                    ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(
                          semanticsLabel: 'Checking local account access',
                        ),
                      ),
                  ],
                  if (state.problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(AuthFailure(state.problem!).message),
                      ),
                    ),
                  if (state.notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(state.notice!),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => context.go('/auth/register'),
                        child: const Text('Create synthetic account'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => context.go('/auth/verify'),
                        child: const Text('Verify local confirmation'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => context.go('/auth/recovery'),
                        child: const Text('Local password recovery'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => ref
                                  .read(authControllerProvider.notifier)
                                  .refreshSession(),
                        child: const Text('Retry session refresh'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Local lifecycle proof only. OAuth, persistent login and automatic refresh are not enabled.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final password = _password.text;
    _password.clear();
    await ref
        .read(authControllerProvider.notifier)
        .signIn(_email.text, password);
  }
}

class LocalAccountScreen extends ConsumerWidget {
  const LocalAccountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final account = state.phase == AuthPhase.authenticated
        ? state.context
        : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local account context'),
        leading: IconButton(
          tooltip: 'Back to preview',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: ResponsivePage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PreviewBadge(label: 'Protected development proof'),
            const SizedBox(height: 24),
            const SectionHeading(
              title: 'Your local access.',
              description: 'This screen shows only the current server-authorized account context.',
            ),
            const SizedBox(height: 24),
            if (account != null)
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local account verified',
                      key: ValueKey('account-verified'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      account.spaces.isEmpty
                          ? 'No active couple space. Partner linking is deferred.'
                          : '${account.spaces.length} active space authorized. Shared content is not loaded.',
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: () => ref
                              .read(authControllerProvider.notifier)
                              .reloadContext(),
                          child: const Text('Check server access'),
                        ),
                        OutlinedButton(
                          onPressed: () => ref
                              .read(authControllerProvider.notifier)
                              .refreshSession(),
                          child: const Text('Refresh session'),
                        ),
                        OutlinedButton(
                          onPressed: () => ref
                              .read(authControllerProvider.notifier)
                              .signOut(),
                          child: const Text('Sign out'),
                        ),
                        OutlinedButton(
                          onPressed: () => ref
                              .read(authControllerProvider.notifier)
                              .clearLocalSession(),
                          child: const Text('Clear local proof session'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Clearing local memory does not revoke server sessions or previously issued tokens.',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Minimal local email-flow exercise, using the approved reusable components.
/// Links are pasted into RAM fields, never placed in a route/query/history.
class LocalLifecycleScreen extends ConsumerStatefulWidget {
  const LocalLifecycleScreen({
    super.key,
    this.registration = false,
    this.recovery = false,
  });
  final bool registration;
  final bool recovery;
  @override
  ConsumerState<LocalLifecycleScreen> createState() =>
      _LocalLifecycleScreenState();
}

class _LocalLifecycleScreenState extends ConsumerState<LocalLifecycleScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _link = TextEditingController();
  Future<void> _back() async {
    if (ref.read(authControllerProvider).phase == AuthPhase.recovering) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
    if (mounted) context.go('/auth/local');
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _link.dispose();
    super.dispose();
  }

  Widget field(
    TextEditingController controller,
    String label,
    String key, {
    bool password = false,
    bool enabled = true,
  }) => TextField(
    controller: controller,
    key: ValueKey(key),
    enabled: enabled,
    obscureText: password,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    autofillHints: null,
    decoration: InputDecoration(labelText: label),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final controller = ref.read(authControllerProvider.notifier);
    final busy =
        state.phase == AuthPhase.loading || state.phase == AuthPhase.refreshing;
    final configured = ref.watch(localAuthConfigProvider) != null;
    final recovery = widget.recovery;
    final ready = recovery && state.phase == AuthPhase.recovering;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          recovery ? 'Local password recovery' : 'Local email confirmation',
        ),
        leading: IconButton(
          tooltip: 'Back to sign-in',
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
      ),
      body: ResponsivePage(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SurfaceCard(
              child: AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TogetherMark(size: 64),
                    const SizedBox(height: 24),
                    const PreviewBadge(label: 'Local mailbox · RAM only'),
                    const SizedBox(height: 24),
                    SectionHeading(
                      title: ready
                          ? 'Choose a new password.'
                          : recovery
                          ? 'Recover local access.'
                          : 'Confirm your local account.',
                      description: 'Use only synthetic accounts and links from the development mailbox. Links are never opened in the browser or stored in navigation history.',
                    ),
                    const SizedBox(height: 24),
                    if (!configured)
                      Text(const AuthFailure(AuthProblem.configuration).message)
                    else ...[
                      if ((widget.registration || recovery) && !ready) ...[
                        field(
                          _email,
                          'Synthetic email',
                          'lifecycle-email',
                          enabled: !busy,
                        ),
                        const SizedBox(height: 16),
                        if (widget.registration) ...[
                          field(
                            _password,
                            'Test password (16+ characters)',
                            'lifecycle-password',
                            password: true,
                            enabled: !busy,
                          ),
                          const SizedBox(height: 16),
                        ],
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () {
                                  final password = _password.text;
                                  _password.clear();
                                  if (recovery) {
                                    controller.requestRecovery(_email.text);
                                  } else {
                                    controller.register(_email.text, password);
                                  }
                                },
                          child: Text(
                            recovery
                                ? 'Request local reset'
                                : 'Request local confirmation',
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (ready) ...[
                        field(
                          _password,
                          'New password (16+ characters)',
                          'lifecycle-password',
                          password: true,
                          enabled: !busy,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () {
                                  final password = _password.text;
                                  _password.clear();
                                  controller.updatePassword(password);
                                },
                          child: const Text('Update password'),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Password reset revokes Auth refresh sessions and requires fresh sign-in. Issued access tokens may last until expiry.',
                        ),
                      ] else ...[
                        field(
                          _link,
                          recovery
                              ? 'Local recovery link'
                              : 'Local confirmation link',
                          'lifecycle-link',
                          password: true,
                          enabled: !busy,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () {
                                  final link = _link.text;
                                  _link.clear();
                                  controller.verifyLink(
                                    link,
                                    recovery: recovery,
                                  );
                                },
                          child: Text(
                            recovery
                                ? 'Verify recovery link'
                                : 'Verify confirmation link',
                          ),
                        ),
                      ],
                    ],
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(
                          semanticsLabel: 'Processing local authentication',
                        ),
                      ),
                    if (state.notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(state.notice!),
                        ),
                      ),
                    if (state.problem != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(AuthFailure(state.problem!).message),
                        ),
                      ),
                    TextButton(
                      onPressed: busy ? null : _back,
                      child: const Text('Return to sign-in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
