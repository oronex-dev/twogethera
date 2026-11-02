import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/supabase_runtime_config.dart';
import '../application/auth_controller.dart';
import 'auth_components.dart';

class AuthWelcomeScreen extends ConsumerWidget {
  const AuthWelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(supabaseRuntimeConfigProvider);
    return AuthFrame(
      title: 'Your story, together.',
      description: 'Make room for the moments that matter.',
      onBack: () => context.go('/'),
      backLabel: 'Back to preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: () => context.go('/auth/local'),
            child: const Text('Sign in'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.go('/auth/register'),
            child: const Text('Create account'),
          ),
          const SizedBox(height: 20),
          Text(
            config?.isDevelopment == true
                ? 'Explore the authentication preview with a local test account. Your shared space stays private.'
                : 'Sign in or create an account to continue to your private shared space.',
          ),
        ],
      ),
    );
  }
}

class LocalAuthScreen extends ConsumerStatefulWidget {
  const LocalAuthScreen({this.nextRoute, super.key});
  final String? nextRoute;
  @override
  ConsumerState<LocalAuthScreen> createState() => _LocalAuthScreenState();
}

class _LocalAuthScreenState extends ConsumerState<LocalAuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_form.currentState?.validate() ?? false)) return;
    _submitting = true;
    final password = _password.text;
    _password.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(_email.text, password);
      if (mounted &&
          ref.read(authControllerProvider).phase == AuthPhase.authenticated) {
        context.go(widget.nextRoute ?? '/account');
      }
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final busy =
        state.phase == AuthPhase.loading || state.phase == AuthPhase.refreshing;
    final config = ref.watch(supabaseRuntimeConfigProvider);
    final configured = config != null;
    return AuthFrame(
      title: 'Welcome back.',
      description: 'A quiet moment to pick up where you left off.',
      onBack: () => context.go('/auth/welcome'),
      backLabel: 'Back to welcome',
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              authEmailField(
                _email,
                fieldKey: 'auth-email',
                enabled: !busy && configured,
                localOnly: config?.isDevelopment ?? true,
              ),
              const SizedBox(height: 16),
              AuthPasswordField(
                controller: _password,
                label: 'Password',
                fieldKey: 'auth-password',
                enabled: !busy && configured,
                validator: (value) =>
                    (value?.isEmpty ?? true) ? 'Enter your password.' : null,
                onSubmitted: !busy && configured ? _submit : null,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : () => context.go('/auth/recovery'),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy || !configured ? null : _submit,
                child: Text(
                  busy
                      ? (config?.isDevelopment == true
                            ? 'Checking local access…'
                            : 'Signing in…')
                      : (config?.isDevelopment == true
                            ? 'Sign in locally'
                            : 'Sign in'),
                ),
              ),
              if (!configured)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'Authentication is not configured for this build. Contact the app administrator.',
                  ),
                ),
              AuthFeedback(state: state),
              const SizedBox(height: 16),
              TextButton(
                onPressed: busy ? null : () => context.go('/auth/register'),
                child: const Text('New here? Create an account'),
              ),
              TextButton(
                onPressed: busy ? null : () => context.go('/auth/verify'),
                child: const Text('Confirm your email'),
              ),
              if (state.expired)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => ref
                            .read(authControllerProvider.notifier)
                            .refreshSession(),
                  child: const Text('Retry session refresh'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class LocalAccountScreen extends ConsumerWidget {
  const LocalAccountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final isDevelopment =
        ref.watch(supabaseRuntimeConfigProvider)?.isDevelopment == true;
    final account = state.phase == AuthPhase.authenticated
        ? state.context
        : null;
    return AuthFrame(
      title: 'A space for you.',
      description: 'Your account, with a little peace of mind.',
      onBack: () => context.go('/'),
      backLabel: 'Back to preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (account != null) ...[
            const Icon(Icons.verified_user_outlined, size: 36),
            const SizedBox(height: 16),
            Text(
              isDevelopment ? 'Local account verified' : 'Account verified',
              key: const ValueKey('account-verified'),
            ),
            const SizedBox(height: 16),
            if (account.displayName != null)
              Text(
                account.displayName!,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            if (account.email != null) Text(account.email!),
            const SizedBox(height: 16),
            Text(
              account.spaces.any((space) => space.state == 'paired')
                  ? 'Your shared space is ready. Open your planner to see what you are building together.'
                  : 'Link with your partner to open your shared planner.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).reloadContext(),
              child: const Text('Check server access'),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).refreshSession(),
              child: const Text('Refresh session'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sign-out clears this device’s memory and requests server sign-out. Previously issued access tokens can remain valid until they expire.',
            ),
          ],
          AuthFeedback(state: state),
        ],
      ),
    );
  }
}

/// All credentials and mailbox links remain in RAM. No autofill persistence.
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
  final _form = GlobalKey<FormState>();
  final _linkForm = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _link = TextEditingController();
  bool _submitting = false;
  Future<void> _back() async {
    final phase = ref.read(authControllerProvider).phase;
    if ({
      AuthPhase.recovering,
      AuthPhase.loading,
      AuthPhase.refreshing,
    }.contains(phase)) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
    if (mounted) context.go('/auth/local');
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    _confirmation.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _submit({bool link = false, bool resend = false}) async {
    if (_submitting) return;
    final valid = link
        ? _linkForm.currentState?.validate()
        : _form.currentState?.validate();
    if (valid != true) return;
    _submitting = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final controller = ref.read(authControllerProvider.notifier);
    final ready =
        ref.read(authControllerProvider).phase == AuthPhase.recovering;
    final password = _password.text;
    final url = _link.text;
    _password.clear();
    _confirmation.clear();
    _link.clear();
    try {
      if (link) {
        await controller.verifyLink(url, recovery: widget.recovery);
      } else if (ready) {
        await controller.updatePassword(password);
      } else if (resend) {
        await controller.resendVerification(_email.text);
      } else if (widget.registration) {
        await controller.register(
          _email.text,
          password,
          displayName: _name.text.trim(),
        );
        if (mounted &&
            ref.read(authControllerProvider).phase ==
                AuthPhase.awaitingConfirmation) {
          context.go('/auth/verify');
        }
      } else {
        await controller.requestRecovery(_email.text);
      }
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final config = ref.watch(supabaseRuntimeConfigProvider);
    final busy =
        state.phase == AuthPhase.loading || state.phase == AuthPhase.refreshing;
    final configured = config != null;
    final enabled = configured && !busy;
    final ready = widget.recovery && state.phase == AuthPhase.recovering;
    final registration = widget.registration;
    final verification = !registration && !widget.recovery;
    return AuthFrame(
      title: ready
          ? 'A fresh start.'
          : registration
          ? 'Begin your story.'
          : widget.recovery
          ? 'Let’s get you back in.'
          : 'Check your inbox.',
      description: ready
          ? 'Choose a new password, then sign in again.'
          : registration
          ? 'A few details, and you’re on your way.'
          : widget.recovery
          ? 'We’ll send a recovery message if your address is eligible.'
          : registration
          ? 'We’ll send a confirmation link to your email. Confirm it to finish creating your account.'
          : config?.isDevelopment == true
          ? 'Open the local development mailbox and use the newest confirmation link. Expired or used links cannot be reused.'
          : 'Open the newest confirmation link in your email. Expired or used links cannot be reused.',
      onBack: _back,
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!configured)
              const Text(
                'Authentication is not configured for this build. Contact the app administrator.',
              ),
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (registration) ...[
                    TextFormField(
                      key: const ValueKey('auth-display-name'),
                      controller: _name,
                      enabled: enabled,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: null,
                      enableIMEPersonalizedLearning: false,
                      validator: (value) =>
                          (value?.trim().length ?? 0) < 2 ||
                              (value?.trim().length ?? 0) > 64
                          ? 'Use a display name between 2 and 64 characters.'
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        errorMaxLines: 4,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!ready) ...[
                    authEmailField(
                      _email,
                      fieldKey: 'lifecycle-email',
                      enabled: enabled,
                      localOnly: config?.isDevelopment ?? true,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (registration || ready) ...[
                    AuthPasswordField(
                      controller: _password,
                      label: ready ? 'New password' : 'Password',
                      fieldKey: 'lifecycle-password',
                      enabled: enabled,
                      action: TextInputAction.next,
                      validator: validateNewPassword,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use at least 16 characters. A memorable phrase works well.',
                    ),
                    const SizedBox(height: 16),
                    AuthPasswordField(
                      controller: _confirmation,
                      label: 'Confirm password',
                      fieldKey: 'auth-confirm-password',
                      enabled: enabled,
                      validator: (value) =>
                          value != _password.text || (value?.isEmpty ?? true)
                          ? 'Your passwords need to match.'
                          : null,
                      onSubmitted: enabled ? _submit : null,
                    ),
                    const SizedBox(height: 24),
                  ],
                  FilledButton(
                    onPressed: !enabled
                        ? null
                        : () => _submit(resend: verification),
                    child: Text(
                      busy
                          ? 'Please wait…'
                          : ready
                          ? 'Update password'
                          : registration
                          ? 'Create account'
                          : verification
                          ? 'Resend confirmation'
                          : 'Send recovery email',
                    ),
                  ),
                ],
              ),
            ),
            if (ready) ...[
              const SizedBox(height: 16),
              const Text(
                'After a reset, sign in with your new password. If the request is interrupted, the password may already have changed; try signing in or request a fresh recovery link.',
              ),
            ] else if (!registration && config?.isDevelopment == true) ...[
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Using the local mailbox? Paste the link here. It is processed in memory without opening its destination.',
              ),
              const SizedBox(height: 16),
              Form(
                key: _linkForm,
                child: TextFormField(
                  key: const ValueKey('lifecycle-link'),
                  controller: _link,
                  enabled: enabled,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  autofillHints: null,
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Paste the newest local mailbox link.'
                      : null,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: enabled ? (_) => _submit(link: true) : null,
                  decoration: InputDecoration(
                    labelText: widget.recovery
                        ? 'Local recovery link'
                        : 'Local confirmation link',
                    errorMaxLines: 4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: enabled ? () => _submit(link: true) : null,
                child: Text(
                  widget.recovery
                      ? 'Verify recovery link'
                      : 'Verify confirmation link',
                ),
              ),
            ],
            AuthFeedback(state: state),
            const SizedBox(height: 16),
            TextButton(
              onPressed: busy ? null : _back,
              child: const Text('Return to sign-in'),
            ),
          ],
        ),
      ),
    );
  }
}
