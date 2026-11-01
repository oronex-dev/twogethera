import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../authentication/application/auth_controller.dart';
import '../domain/partner_invitation_repository.dart';

class PartnerLinkingScreen extends ConsumerStatefulWidget {
  const PartnerLinkingScreen({super.key});

  @override
  ConsumerState<PartnerLinkingScreen> createState() =>
      _PartnerLinkingScreenState();
}

class _PartnerLinkingScreenState extends ConsumerState<PartnerLinkingScreen> {
  final _email = TextEditingController();
  final _token = TextEditingController();
  PartnerLinkContext? _context;
  String? _oneTimeToken;
  String? _oneTimeRecipient;
  String? _issueRequestKey;
  String? _issueOperationId;
  String? _acceptRequestToken;
  String? _acceptOperationId;
  String? _revokeInvitationId;
  String? _revokeOperationId;
  DateTime? _oneTimeExpiry;
  String? _error;
  String? _notice;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    // A created invitation token exists only in this widget's memory.
    _oneTimeToken = null;
    _email.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final context = await ref
          .read(partnerInvitationRepositoryProvider)
          .loadPartnerContext();
      if (!mounted) return;
      setState(() {
        _context = context;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'We could not load your couple space. Try again.';
      });
    }
  }

  Future<void> _createSpace() async {
    await _perform(() async {
      await ref
          .read(partnerInvitationRepositoryProvider)
          .createDraftSpace(newPartnerOperationId());
      await ref.read(authControllerProvider.notifier).reloadContext();
      _notice = 'Your private setup space is ready.';
      await _refresh();
    });
  }

  Future<void> _issueInvitation() async {
    final recipientEmail = _email.text.trim();
    if (!_looksLikeEmail(recipientEmail)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    final space = _context?.space;
    if (space == null) return;
    final requestKey =
        '${space.id}|${space.authorizationEpoch}|$recipientEmail';
    if (_issueRequestKey != requestKey || _issueOperationId == null) {
      _issueRequestKey = requestKey;
      _issueOperationId = newPartnerOperationId();
    }
    await _perform(() async {
      final invitation = await ref
          .read(partnerInvitationRepositoryProvider)
          .issueInvitation(
            operationId: _issueOperationId!,
            spaceId: space.id,
            expectedEpoch: space.authorizationEpoch,
            recipientEmail: recipientEmail,
          );
      _email.clear();
      _issueRequestKey = null;
      _issueOperationId = null;
      _oneTimeToken = invitation.oneTimeToken;
      _oneTimeRecipient = invitation.recipientHint;
      _oneTimeExpiry = invitation.expiresAt;
      _notice = invitation.oneTimeToken == null
          ? 'An invitation was already created. Its code is shown only once; revoke it and create another to share a new code.'
          : 'Invitation created. Share the one-time code with the intended person.';
      await _refresh();
    });
  }

  Future<void> _acceptInvitation() async {
    final token = _token.text.trim();
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)) {
      setState(() => _error = 'Enter the 64-character invitation code.');
      return;
    }
    final normalizedToken = token.toLowerCase();
    if (_acceptRequestToken != normalizedToken || _acceptOperationId == null) {
      _acceptRequestToken = normalizedToken;
      _acceptOperationId = newPartnerOperationId();
    }
    await _perform(() async {
      await ref
          .read(partnerInvitationRepositoryProvider)
          .acceptInvitation(
            operationId: _acceptOperationId!,
            oneTimeToken: normalizedToken,
          );
      _token.clear();
      _oneTimeToken = null;
      _acceptRequestToken = null;
      _acceptOperationId = null;
      await ref.read(authControllerProvider.notifier).reloadContext();
      _notice = 'You are now linked. Your shared space is ready.';
      await _refresh();
    });
  }

  Future<void> _revokeInvitation(String invitationId) async {
    if (_revokeInvitationId != invitationId || _revokeOperationId == null) {
      _revokeInvitationId = invitationId;
      _revokeOperationId = newPartnerOperationId();
    }
    await _perform(() async {
      await ref
          .read(partnerInvitationRepositoryProvider)
          .revokeInvitation(
            operationId: _revokeOperationId!,
            invitationId: invitationId,
          );
      _oneTimeToken = null;
      _revokeInvitationId = null;
      _revokeOperationId = null;
      _notice = 'The invitation has been revoked.';
      await _refresh();
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on PartnerInvitationFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We could not complete that request. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _looksLikeEmail(String value) =>
      value.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  @override
  Widget build(BuildContext context) {
    final space = _context?.space;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your couple space'),
        leading: IconButton(
          tooltip: 'Back to home',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ResponsivePage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading(
              title: 'Make it a space for two',
              description: 'Invite the person you choose. Your shared planner stays private until they accept.',
            ),
            const SizedBox(height: AppSpace.lg),
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: _MessageCard(text: _error!, error: true),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (_notice != null) ...[
              Semantics(liveRegion: true, child: _MessageCard(text: _notice!)),
              const SizedBox(height: AppSpace.md),
            ],
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (space == null)
              _noSpaceCard()
            else if (space.state == PartnerSpaceState.paired)
              _linkedCard()
            else ...[
              _draftCard(space),
              const SizedBox(height: AppSpace.md),
              _acceptCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noSpaceCard() => Column(
    children: [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.favorite_border_rounded, size: 32),
            const SizedBox(height: AppSpace.md),
            Text(
              'Start your space',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpace.sm),
            const Text(
              'Your space stays private until your partner accepts your invitation.',
            ),
            const SizedBox(height: AppSpace.md),
            FilledButton.icon(
              onPressed: _busy ? null : _createSpace,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create couple space'),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpace.md),
      _acceptCard(),
    ],
  );

  Widget _linkedCard() => SurfaceCard(
    child: Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.favorite_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 32,
          ),
          const SizedBox(height: AppSpace.md),
          Text('You’re linked', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.sm),
          const Text('Your couple space is active for both of you.'),
          const SizedBox(height: AppSpace.md),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh status'),
          ),
        ],
      ),
    ),
  );

  Widget _draftCard(PartnerSpaceSummary space) {
    final invite = _context?.invitation;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invite your partner',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpace.sm),
          const Text(
            'We’ll bind the invitation to this address. Only an account that verifies the same email can accept it.',
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Partner’s email address',
              hintText: 'name@example.com',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            onSubmitted: (_) => _issueInvitation(),
            onChanged: (_) {
              _issueRequestKey = null;
              _issueOperationId = null;
            },
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: _busy ? null : _issueInvitation,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Create invitation'),
          ),
          if (invite != null) ...[
            const SizedBox(height: AppSpace.lg),
            const Divider(),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Invitation ${invite.state.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'For ${invite.recipientHint} · expires ${_formatDate(invite.expiresAt)}',
            ),
            if (invite.state == PartnerInvitationState.pending) ...[
              const SizedBox(height: AppSpace.sm),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _revokeInvitation(invite.id),
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Revoke invitation'),
              ),
            ],
          ],
          if (_oneTimeToken != null) ...[
            const SizedBox(height: AppSpace.lg),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'One-time invitation code',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Share only with ${_oneTimeRecipient ?? 'the intended person'}. This code is shown once and expires ${_formatDate(_oneTimeExpiry!)}.',
                  ),
                  const SizedBox(height: AppSpace.sm),
                  SelectableText(
                    _oneTimeToken!,
                    key: const ValueKey('partner-one-time-code'),
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontFamily: 'monospace', letterSpacing: 1),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _copyCode,
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Copy code'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _oneTimeToken = null),
                        child: const Text('Hide code'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          Text(
            'The code is kept in memory and cannot be recovered after you leave this screen. Share it yourself; no invitation email is sent.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('Refresh invitation status'),
          ),
        ],
      ),
    );
  }

  Widget _acceptCard() => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Accept an invitation',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpace.sm),
        const Text(
          'Sign in with the verified email address the invitation was sent to. Accepting won’t move you out of another couple space.',
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _token,
          enabled: !_busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '64-character invitation code',
            prefixIcon: Icon(Icons.key_rounded),
          ),
          onSubmitted: (_) => _acceptInvitation(),
          onChanged: (_) {
            _acceptRequestToken = null;
            _acceptOperationId = null;
          },
        ),
        const SizedBox(height: AppSpace.md),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _acceptInvitation,
          icon: const Icon(Icons.favorite_rounded),
          label: const Text('Accept invitation'),
        ),
      ],
    ),
  );

  Future<void> _copyCode() async {
    final token = _oneTimeToken;
    if (token == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: token));
      if (mounted) {
        setState(
          () =>
              _notice = 'Code copied. Share it only with the intended person.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not copy the code. Select it to copy manually.',
        );
      }
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day ${local.year} at $hour:$minute';
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error
              ? Icons.info_outline_rounded
              : Icons.check_circle_outline_rounded,
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
