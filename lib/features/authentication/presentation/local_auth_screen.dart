import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/supabase_runtime_config.dart';
import '../application/auth_controller.dart';
import '../domain/password_policy.dart';
import '../../profile/presentation/profile_sections.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../../shared_planner/domain/shared_planner_repository.dart';
import 'auth_components.dart';

class AuthWelcomeScreen extends ConsumerWidget {
  const AuthWelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(supabaseRuntimeConfigProvider);
    return AuthFrame(
      title: 'Your story, together.',
      description: 'Make room for the moments that matter.',
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
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
        context.go(widget.nextRoute ?? '/');
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
                    'Local authentication is not enabled for this debug build. Check APP_ENV, LOCAL_AUTH_ENABLED, LOCAL_SUPABASE_URL, and LOCAL_SUPABASE_ANON_KEY, then restart the app.',
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
    final hasPairedSpace =
        account?.spaces.any((space) => space.state == 'paired') ?? false;
    return AuthFrame(
      title: 'A space for you.',
      description: 'Your account, with a little peace of mind.',
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      backLabel: 'Back to preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (account != null) ...[
            ProfileSections(account: account),
            const SizedBox(height: 24),
            Text(
              'Account information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
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
            if (!isDevelopment && hasPairedSpace) ...[
              OutlinedButton(
                onPressed: state.lifecycleBusy
                    ? null
                    : () async {
                        final confirmed = await _confirmLifecycleAction(
                          context,
                          title: 'Close the shared space for both partners?',
                          detail: 'Both partners immediately lose server access. There is no survivor archive or replacement partner. The primary-copy purge target is 30 days; minimized financial audit fields have a 90-day target. Previously downloaded copies cannot be remotely erased.',
                          phrase: 'CLOSE',
                          actionLabel: 'Close for both',
                        );
                        if (!confirmed || !context.mounted) return;
                        final completed = await ref
                            .read(authControllerProvider.notifier)
                            .closeCoupleSpace();
                        if (completed && context.mounted) {
                          context.go('/auth/local');
                        }
                      },
                child: state.lifecycleBusy
                    ? const Text('Closing shared space…')
                    : const Text('Close shared space for both partners'),
              ),
              const SizedBox(height: 12),
            ],
            if (!isDevelopment) ...[
              FilledButton.tonal(
                onPressed: state.lifecycleBusy
                    ? null
                    : () async {
                        final confirmed = await _confirmLifecycleAction(
                          context,
                          title: 'Delete your account?',
                          detail: 'This closes the entire shared space and immediately removes server access for both partners. The account is not recoverable. Primary-copy nonfinancial purge targets 30 days; minimized financial audit fields have a 90-day target. Reauthentication within the last 10 minutes is required. Previously downloaded copies cannot be remotely erased.',
                          phrase: 'DELETE',
                          actionLabel: 'Request deletion',
                        );
                        if (!confirmed || !context.mounted) return;
                        final completed = await ref
                            .read(authControllerProvider.notifier)
                            .deleteAccount();
                        if (completed && context.mounted) {
                          context.go('/auth/local');
                        }
                      },
                child: state.lifecycleBusy
                    ? const Text('Processing deletion…')
                    : const Text('Delete account'),
              ),
              const SizedBox(height: 12),
            ],
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
            if (!isDevelopment) ...[
              const SizedBox(height: 28),
              const _RecentlyDeletedSharedRecords(),
            ],
          ],
          const LegalDocumentLinks(),
          const SizedBox(height: 8),
          AuthFeedback(state: state),
        ],
      ),
    );
  }
}

class _RecentlyDeletedSharedRecords extends ConsumerWidget {
  const _RecentlyDeletedSharedRecords();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recoverableSharedRecordsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Recently deleted', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text(
          'Ordinarily deleted shared items can be restored by either active partner for seven days. Privacy removals cannot be restored.',
        ),
        const SizedBox(height: 12),
        records.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text(
            'Recently deleted items could not be loaded. Try refreshing your account.',
          ),
          data: (items) => items.isEmpty
              ? const Text('There are no items available to restore.')
              : Column(
                  children: [
                    for (final item in items)
                      _RecoverableRecordTile(record: item),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RecoverableRecordTile extends ConsumerStatefulWidget {
  const _RecoverableRecordTile({required this.record});
  final RecoverableSharedRecord record;

  @override
  ConsumerState<_RecoverableRecordTile> createState() =>
      _RecoverableRecordTileState();
}

class _RecoverableRecordTileState
    extends ConsumerState<_RecoverableRecordTile> {
  bool _busy = false;

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    var restored = false;
    try {
      final repository = ref.read(authRepositoryProvider);
      if (repository is SharedContentRecoveryRepository) {
        restored = await (repository as SharedContentRecoveryRepository)
            .restoreSharedRecord(widget.record);
      }
    } catch (_) {
      restored = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ref.invalidate(recoverableSharedRecordsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored ? '${widget.record.label} restored.' : 'This item could not be restored. It may have expired or the shared space may be closed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.restore_rounded),
    title: Text(widget.record.label),
    subtitle: Text(
      'Available until ${MaterialLocalizations.of(context).formatMediumDate(widget.record.restoreUntil.toLocal())}',
    ),
    trailing: TextButton(
      onPressed: _busy ? null : _restore,
      child: Text(_busy ? 'Restoring…' : 'Restore'),
    ),
  );
}

Future<bool> _confirmLifecycleAction(
  BuildContext context, {
  required String title,
  required String detail,
  required String phrase,
  required String actionLabel,
}) async {
  final controller = TextEditingController();
  try {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(detail),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Type $phrase to confirm',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: controller.text == phrase
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ) ??
        false;
  } finally {
    controller.dispose();
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

  void _handleInputChanged(String _) {
    if (mounted) setState(() {});
  }

  bool _validDisplayName() {
    final length = _name.text.trim().length;
    return length >= 2 && length <= 64;
  }

  bool _validPasswordPair() =>
      evaluatePassword(_password.text).isComplete &&
      _confirmation.text.isNotEmpty &&
      _confirmation.text == _password.text;

  bool _validRegistration(bool localOnly) =>
      _validDisplayName() &&
      validateAccountEmail(_email.text, localOnly: localOnly) == null &&
      _validPasswordPair();

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
    final registration = widget.registration && !ready && !link && !resend;
    final password = _password.text;
    final url = _link.text;
    // Retain registration input if Auth rejects the request so the user can
    // correct/retry it. Other credential operations keep their previous
    // clear-before-request behavior.
    if (!registration) {
      _password.clear();
      _confirmation.clear();
      _link.clear();
    }
    try {
      if (link) {
        await controller.verifyLink(url, recovery: widget.recovery);
      } else if (ready) {
        await controller.updatePassword(password);
      } else if (resend) {
        await controller.resendVerification(_email.text);
      } else if (registration) {
        await controller.register(
          _email.text,
          password,
          displayName: _name.text.trim(),
        );
        if (mounted &&
            ref.read(authControllerProvider).phase ==
                AuthPhase.awaitingConfirmation) {
          _password.clear();
          _confirmation.clear();
          context.go('/auth/verify');
        }
      } else {
        await controller.requestRecovery(_email.text);
      }
    } finally {
      _submitting = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.registration) {
      return AuthFrame(
        title: 'Private beta access',
        description: 'New account registration is closed. This beta is limited to the two existing partner accounts.',
        onBack: () => context.go('/auth/local'),
        child: const SizedBox.shrink(),
      );
    }
    final state = ref.watch(authControllerProvider);
    final config = ref.watch(supabaseRuntimeConfigProvider);
    final busy =
        state.phase == AuthPhase.loading || state.phase == AuthPhase.refreshing;
    final configured = config != null;
    final enabled = configured && !busy;
    final ready = widget.recovery && state.phase == AuthPhase.recovering;
    final registration = widget.registration;
    final verification = !registration && !widget.recovery;
    final localOnly = config?.isDevelopment ?? true;
    final registrationReady = registration && _validRegistration(localOnly);
    final passwordUpdateReady = ready && _validPasswordPair();
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
          ? 'Open local Mailpit at http://127.0.0.1:54324 and paste the newest confirmation link below. Expired or used links cannot be reused.'
          : 'Open the newest confirmation link in your email. Expired or used links cannot be reused.',
      onBack: _back,
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!configured)
              const Text(
                'Local authentication is not enabled for this debug build. Check APP_ENV, LOCAL_AUTH_ENABLED, LOCAL_SUPABASE_URL, and LOCAL_SUPABASE_ANON_KEY, then restart the app.',
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
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: _handleInputChanged,
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
                      onChanged: _handleInputChanged,
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
                      showRequirements: true,
                      onChanged: _handleInputChanged,
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
                      onChanged: _handleInputChanged,
                      onSubmitted: enabled ? _submit : null,
                    ),
                    if (_confirmation.text.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        child: Text(
                          _confirmation.text == _password.text
                              ? 'Passwords match.'
                              : 'Your passwords need to match.',
                          key: ValueKey(_confirmation.text == _password.text),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _confirmation.text == _password.text
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                  FilledButton(
                    onPressed:
                        !enabled ||
                            (registration && !registrationReady) ||
                            (ready && !passwordUpdateReady)
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
