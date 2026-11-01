import 'dart:math';

enum PartnerSpaceState { draft, paired }

class PartnerSpaceSummary {
  const PartnerSpaceSummary({
    required this.id,
    required this.state,
    required this.authorizationEpoch,
  });

  final String id;
  final PartnerSpaceState state;
  final int authorizationEpoch;
}

enum PartnerInvitationState { pending, expired, revoked }

class PartnerInvitationSummary {
  const PartnerInvitationSummary({
    required this.id,
    required this.state,
    required this.recipientHint,
    required this.expiresAt,
  });

  final String id;
  final PartnerInvitationState state;
  final String recipientHint;
  final DateTime expiresAt;
}

class PartnerLinkContext {
  const PartnerLinkContext({this.space, this.invitation});

  final PartnerSpaceSummary? space;
  final PartnerInvitationSummary? invitation;
}

class IssuedPartnerInvitation {
  const IssuedPartnerInvitation({
    required this.invitationId,
    required this.recipientHint,
    required this.expiresAt,
    this.oneTimeToken,
    this.replayed = false,
  });

  final String invitationId;
  final String recipientHint;
  final DateTime expiresAt;

  /// Kept only by the caller in process memory; never persisted or logged.
  final String? oneTimeToken;
  final bool replayed;
}

abstract interface class PartnerInvitationRepository {
  Future<PartnerLinkContext> loadPartnerContext();
  Future<void> createDraftSpace(String operationId);
  Future<IssuedPartnerInvitation> issueInvitation({
    required String operationId,
    required String spaceId,
    required int expectedEpoch,
    required String recipientEmail,
  });
  Future<String> acceptInvitation({
    required String operationId,
    required String oneTimeToken,
  });
  Future<void> revokeInvitation({
    required String operationId,
    required String invitationId,
  });
}

class PartnerInvitationFailure implements Exception {
  const PartnerInvitationFailure();
  String get message =>
      'That invitation is unavailable. Check the code and account, then try again.';
}

/// Idempotency identifiers are not secrets. Use a CSPRNG so independently
/// submitted operations cannot accidentally collide.
String newPartnerOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
