import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';
import '../domain/auth_repository.dart';

/// Collects the current account password transiently and asks Supabase Auth
/// for a new signed password session. Never writes the password to storage or
/// logs. The caller retries its original server-authorized operation on true.
Future<bool> requestRecentPasswordReauthentication(
  BuildContext context,
  WidgetRef ref,
) async {
  final repository = ref.read(authRepositoryProvider);
  if (repository is! RecentReauthenticationRepository) return false;
  final reauthenticationRepository =
      repository as RecentReauthenticationRepository;
  return await showDialog<bool>(
        context: context,
        builder: (_) => _RecentReauthenticationDialog(
          repository: reauthenticationRepository,
        ),
      ) ??
      false;
}

class _RecentReauthenticationDialog extends StatefulWidget {
  const _RecentReauthenticationDialog({required this.repository});
  final RecentReauthenticationRepository repository;

  @override
  State<_RecentReauthenticationDialog> createState() =>
      _RecentReauthenticationDialogState();
}

class _RecentReauthenticationDialogState
    extends State<_RecentReauthenticationDialog> {
  final _password = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_password.text.isEmpty) {
      setState(() => _errorMessage = 'Enter your password to continue.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await widget.repository.reauthenticateWithPassword(_password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AuthFailure catch (failure) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = failure.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = 'Password verification could not be completed.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verify it’s you'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter your account password again to continue this sensitive action. Your password is used only for this verification.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [],
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Password',
            errorText: _errorMessage,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: Text(_submitting ? 'Verifying…' : 'Verify and retry'),
      ),
    ],
  );
}

Future<bool> runSensitiveActionWithReauthentication(
  BuildContext context,
  WidgetRef ref,
  Future<bool> Function() action,
) async {
  var completed = await action();
  if (completed || !context.mounted) return completed;
  if (ref.read(authControllerProvider).problem !=
      AuthProblem.reauthenticationRequired) {
    return false;
  }
  if (!await requestRecentPasswordReauthentication(context, ref) ||
      !context.mounted) {
    return false;
  }
  completed = await action();
  return completed;
}
