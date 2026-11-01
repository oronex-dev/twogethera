import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/partner_linking/domain/partner_invitation_repository.dart';
import 'package:twogethera/features/partner_linking/presentation/partner_linking_screen.dart';

import 'authentication_test.dart' show FakeAuthRepository;

class FakePartnerRepository implements PartnerInvitationRepository {
  PartnerLinkContext context = const PartnerLinkContext();
  String? acceptedToken;
  final acceptedOperationIds = <String>[];
  bool failNextAccept = false;
  int issueCount = 0;
  int revokeCount = 0;

  @override
  Future<PartnerLinkContext> loadPartnerContext() async => context;

  @override
  Future<void> createDraftSpace(String operationId) async {
    context = const PartnerLinkContext(
      space: PartnerSpaceSummary(
        id: 'space-a',
        state: PartnerSpaceState.draft,
        authorizationEpoch: 1,
      ),
    );
  }

  @override
  Future<IssuedPartnerInvitation> issueInvitation({
    required String operationId,
    required String spaceId,
    required int expectedEpoch,
    required String recipientEmail,
  }) async {
    issueCount++;
    final expiresAt = DateTime.utc(2026, 11, 3);
    context = PartnerLinkContext(
      space: context.space,
      invitation: PartnerInvitationSummary(
        id: 'invite-a',
        state: PartnerInvitationState.pending,
        recipientHint: 'p•••@example.invalid',
        expiresAt: expiresAt,
      ),
    );
    return IssuedPartnerInvitation(
      invitationId: 'invite-a',
      recipientHint: 'p•••@example.invalid',
      expiresAt: expiresAt,
      oneTimeToken: 'a' * 64,
    );
  }

  @override
  Future<String> acceptInvitation({
    required String operationId,
    required String oneTimeToken,
  }) async {
    acceptedOperationIds.add(operationId);
    if (failNextAccept) {
      failNextAccept = false;
      throw const PartnerInvitationFailure();
    }
    acceptedToken = oneTimeToken;
    context = const PartnerLinkContext(
      space: PartnerSpaceSummary(
        id: 'space-a',
        state: PartnerSpaceState.paired,
        authorizationEpoch: 2,
      ),
    );
    return 'space-a';
  }

  @override
  Future<void> revokeInvitation({
    required String operationId,
    required String invitationId,
  }) async {
    revokeCount++;
    context = PartnerLinkContext(space: context.space);
  }
}

void main() {
  testWidgets(
    'draft owner creates a one-time invitation and sees pending status',
    (tester) async {
      final auth = FakeAuthRepository();
      final partner = FakePartnerRepository()
        ..context = const PartnerLinkContext(
          space: PartnerSpaceSummary(
            id: 'space-a',
            state: PartnerSpaceState.draft,
            authorizationEpoch: 1,
          ),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            partnerInvitationRepositoryProvider.overrideWithValue(partner),
          ],
          child: const MaterialApp(home: PartnerLinkingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'partner@example.invalid',
      );
      await tester.tap(find.text('Create invitation'));
      await tester.pumpAndSettle();
      expect(partner.issueCount, 1);
      expect(
        find.byKey(const ValueKey('partner-one-time-code')),
        findsOneWidget,
      );
      expect(find.textContaining('p•••@example.invalid'), findsWidgets);
      expect(find.textContaining('Share only with'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.dispose();
    },
  );

  testWidgets('an unpaired account can accept a code and sees paired status', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    final partner = FakePartnerRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          partnerInvitationRepositoryProvider.overrideWithValue(partner),
        ],
        child: const MaterialApp(home: PartnerLinkingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Accept an invitation'), findsOneWidget);
    await tester.ensureVisible(find.text('Accept invitation'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'A' * 64);
    await tester.tap(find.text('Accept invitation'));
    await tester.pumpAndSettle();
    expect(partner.acceptedToken, 'a' * 64);
    expect(find.text('You’re linked'), findsOneWidget);
    expect(
      find.text('Your couple space is active for both of you.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.dispose();
  });

  testWidgets('accept retries reuse the same idempotency operation', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    final partner = FakePartnerRepository()..failNextAccept = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          partnerInvitationRepositoryProvider.overrideWithValue(partner),
        ],
        child: const MaterialApp(home: PartnerLinkingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Accept invitation'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'b' * 64);
    await tester.tap(find.text('Accept invitation'));
    await tester.pumpAndSettle();
    expect(partner.acceptedOperationIds, hasLength(1));
    expect(find.textContaining('invitation is unavailable'), findsOneWidget);
    await tester.ensureVisible(find.text('Accept invitation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept invitation'));
    await tester.pumpAndSettle();
    expect(partner.acceptedOperationIds, hasLength(2));
    expect(partner.acceptedOperationIds[0], partner.acceptedOperationIds[1]);
    expect(find.text('You’re linked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.dispose();
  });
}
