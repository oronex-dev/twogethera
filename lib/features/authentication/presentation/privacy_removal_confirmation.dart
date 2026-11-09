import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';
import '../domain/auth_repository.dart';
import 'recent_reauthentication_dialog.dart';

Future<void> confirmPrivacyRemoval(
  BuildContext context,
  WidgetRef ref, {
  required String table,
  required String recordId,
  String? field,
  required Future<void> Function() onSubmitted,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove shared content for privacy?'),
      content: Text(
        field == null
            ? 'This immediately hides the selected shared record and cannot be undone. Its primary-copy cleanup is queued with a 24-hour target; backups and downloaded copies may remain for their separate retention periods.'
            : 'This immediately removes the selected text field from the shared record. It cannot be restored. The other safe fields remain unchanged.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Confirm removal'),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return;

  final repository = ref.read(authRepositoryProvider);
  if (repository is! PrivacyRemovalRepository) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            const AuthFailure(AuthProblem.lifecycleUnavailable).message,
          ),
        ),
      );
    }
    return;
  }
  final privacyRepository = repository as PrivacyRemovalRepository;
  Future<void> submit() async {
    await privacyRepository.requestPrivacyRemoval(
      table: table,
      recordId: recordId,
      field: field,
      removeRecord: field == null,
    );
  }

  try {
    await submit();
  } on AuthFailure catch (error) {
    if (error.problem == AuthProblem.reauthenticationRequired &&
        context.mounted &&
        await requestRecentPasswordReauthentication(context, ref) &&
        context.mounted) {
      try {
        await submit();
      } on AuthFailure catch (retryError) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(retryError.message)));
        }
        return;
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The privacy request could not be submitted.'),
            ),
          );
        }
        return;
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The privacy request could not be submitted.'),
        ),
      );
    }
    return;
  }

  try {
    await onSubmitted();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            field == null
                ? 'Content hidden. Primary-copy cleanup is queued.'
                : 'The selected text field was removed.',
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The privacy request could not be submitted.'),
        ),
      );
    }
  }
}
