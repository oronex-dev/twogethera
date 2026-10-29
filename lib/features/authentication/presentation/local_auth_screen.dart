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
    final busy = state.phase == AuthPhase.loading;
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
                  const SizedBox(height: 24),
                  const Text(
                    'Registration, recovery, OAuth, persistent login and automatic refresh are not enabled.',
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
