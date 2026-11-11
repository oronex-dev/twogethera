import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../authentication/application/auth_controller.dart';
import '../../authentication/domain/auth_repository.dart';
import '../application/profile_controller.dart';
import '../domain/profile_repository.dart';

class ProfileSections extends ConsumerStatefulWidget {
  const ProfileSections({required this.account, super.key});

  final AccountContext account;

  @override
  ConsumerState<ProfileSections> createState() => _ProfileSectionsState();
}

class _ProfileSectionsState extends ConsumerState<ProfileSections> {
  String? _requestedUserId;
  String? _draftProfileKey;
  String _draftName = '';
  String _draftAbout = '';
  bool _hasUnsavedChanges = false;
  String? _displayName;
  String? _about;
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      final terminalPhase = switch (next.phase) {
        AuthPhase.signedOut ||
        AuthPhase.error ||
        AuthPhase.recovering ||
        AuthPhase.awaitingConfirmation ||
        AuthPhase.recoveryRequested => true,
        _ => false,
      };
      final identityChanged =
          next.context?.userId != null &&
          next.context?.userId != widget.account.userId;
      if (terminalPhase || identityChanged) {
        _requestedUserId = null;
        _draftProfileKey = null;
        _hasUnsavedChanges = false;
        ref.read(profileControllerProvider.notifier).clear();
      }
    });
    final auth = ref.watch(authControllerProvider);
    final state = ref.watch(profileControllerProvider);
    final signedInUserMatches =
        auth.phase == AuthPhase.authenticated &&
        auth.context?.userId == widget.account.userId;
    if (signedInUserMatches && _requestedUserId != widget.account.userId) {
      _requestedUserId = widget.account.userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(profileControllerProvider.notifier).load(widget.account);
        }
      });
    }
    final profile =
        auth.phase == AuthPhase.authenticated &&
            auth.context?.userId == widget.account.userId &&
            state.userId == widget.account.userId
        ? state.myProfile
        : null;
    if (profile != null) _syncDraft(profile);
    final paired = widget.account.spaces.any(
      (space) => space.state == 'paired',
    );

    return PopScope<Object?>(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_hasUnsavedChanges || !context.mounted) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Discard profile changes?'),
            content: const Text(
              'Your unsaved name or About me changes will be lost.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep editing'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard changes'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          setState(() => _hasUnsavedChanges = false);
          context.pop();
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.error != null)
            _InlineMessage(
              text: state.error!,
              color: Theme.of(context).colorScheme.error,
              onRetry: () => ref
                  .read(profileControllerProvider.notifier)
                  .load(widget.account),
            ),
          if (state.notice != null)
            _InlineMessage(
              text: state.notice!,
              color: Theme.of(context).colorScheme.primary,
            ),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My profile',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpace.md),
                if ((state.loading && profile == null) ||
                    (auth.phase != AuthPhase.authenticated &&
                        state.userId == widget.account.userId))
                  const Center(child: CircularProgressIndicator())
                else if (profile == null)
                  const Text('Your profile could not be displayed.')
                else ...[
                  Center(
                    child: Column(
                      children: [
                        _Avatar(bytes: null, label: profile.displayName),
                        const SizedBox(height: AppSpace.xs),
                        const Text(
                          'Profile photos are disabled in Private Beta V1.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          key: ValueKey(
                            'profile-name-${profile.userId}-${profile.revision}',
                          ),
                          initialValue: _hasUnsavedChanges
                              ? _draftName
                              : profile.displayName,
                          maxLength: 64,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            if (name.length < 2 || name.length > 64) {
                              return 'Use 2 to 64 characters.';
                            }
                            return null;
                          },
                          onChanged: (value) => _updateDraft(
                            profile,
                            displayName: value,
                            about: _draftAbout,
                          ),
                          onSaved: (value) => _displayName = value?.trim(),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        TextFormField(
                          key: ValueKey(
                            'profile-about-${profile.userId}-${profile.revision}',
                          ),
                          initialValue: _hasUnsavedChanges
                              ? _draftAbout
                              : profile.about,
                          maxLength: 280,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'About me (private)',
                            alignLabelWithHint: true,
                          ),
                          onChanged: (value) => _updateDraft(
                            profile,
                            displayName: _draftName,
                            about: value,
                          ),
                          onSaved: (value) => _about = value?.trim() ?? '',
                        ),
                        if (_hasUnsavedChanges) ...[
                          const SizedBox(height: AppSpace.xs),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: AppSpace.xs,
                              runSpacing: AppSpace.xs,
                              children: [
                                Text(
                                  'Unsaved changes',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                TextButton(
                                  onPressed: state.saving
                                      ? null
                                      : () => _discardChanges(profile),
                                  child: const Text('Discard'),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpace.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: state.saving || state.photoBusy
                                ? null
                                : _save,
                            icon: state.saving
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(
                              state.saving
                                  ? 'Saving'
                                  : _hasUnsavedChanges
                                  ? 'Save changes'
                                  : 'Save profile',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Your profile settings are personal. Only your display name appears to your active partner; About me stays private.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Partner profile',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpace.md),
                if (!paired)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      const Text(
                        'Link with your partner to see their profile.',
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.go('/partner'),
                        icon: const Icon(Icons.favorite_border_rounded),
                        label: const Text('Link partner'),
                      ),
                    ],
                  )
                else if (state.loading)
                  const LinearProgressIndicator()
                else if (state.partnerLoadFailed)
                  const Text('Your partner’s profile could not be loaded.')
                else if (state.partnerProfile == null)
                  const Text('Your partner has not set up a profile yet.')
                else
                  Row(
                    children: [
                      _Avatar(
                        bytes: state.partnerAvatarBytes,
                        label: state.partnerProfile!.displayName,
                        size: 64,
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Text(
                          state.partnerProfile!.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _syncDraft(UserProfile profile) {
    final key = '${profile.userId}:${profile.revision}';
    if (_draftProfileKey == key) return;
    _draftProfileKey = key;
    _draftName = profile.displayName;
    _draftAbout = profile.about;
    _hasUnsavedChanges = false;
  }

  void _updateDraft(
    UserProfile profile, {
    required String displayName,
    required String about,
  }) {
    final dirty =
        displayName.trim() != profile.displayName ||
        about.trim() != profile.about;
    if (_draftName == displayName &&
        _draftAbout == about &&
        _hasUnsavedChanges == dirty) {
      return;
    }
    setState(() {
      _draftName = displayName;
      _draftAbout = about;
      _hasUnsavedChanges = dirty;
    });
  }

  void _discardChanges(UserProfile profile) {
    _formKey.currentState?.reset();
    setState(() {
      _draftName = profile.displayName;
      _draftAbout = profile.about;
      _hasUnsavedChanges = false;
    });
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    _formKey.currentState!.save();
    final saved = await ref
        .read(profileControllerProvider.notifier)
        .save(displayName: _displayName ?? '', about: _about ?? '');
    if (saved && mounted) {
      ref
          .read(authControllerProvider.notifier)
          .applySavedDisplayName(widget.account.userId, _displayName!.trim());
    }
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.bytes, required this.label, this.size = 88});

  final Uint8List? bytes;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: bytes == null
        ? '$label profile photo not set'
        : '$label profile photo',
    image: bytes != null,
    child: CircleAvatar(
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      backgroundImage: bytes == null ? null : MemoryImage(bytes!),
      child: bytes == null
          ? Icon(Icons.person_outline_rounded, size: size * 0.46)
          : null,
    ),
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.text, required this.color, this.onRetry});

  final String text;
  final Color color;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      spacing: AppSpace.sm,
      runSpacing: AppSpace.xs,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width - 96,
          ),
          child: Text(text, style: TextStyle(color: color)),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
