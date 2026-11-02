enum AuthSignal { signedIn, cleared, expired, recoveryVerified }

enum AuthProblem {
  invalidCredentials,
  unavailable,
  denied,
  expired,
  configuration,
  emailUnconfirmed,
  invalidLink,
  recoveryRequired,
  passwordRejected,
}

class AuthFailure implements Exception {
  const AuthFailure(this.problem);
  final AuthProblem problem;
  String get message => switch (problem) {
    AuthProblem.invalidCredentials =>
      'Sign-in could not be completed. Check your email and password.',
    AuthProblem.unavailable =>
      'Authentication is temporarily unavailable. Try again shortly.',
    AuthProblem.denied => 'This account cannot access shared data. Contact support if you think this is an error.',
    AuthProblem.expired =>
      'Local access expired. Refresh explicitly or sign in again.',
    AuthProblem.configuration => 'Local authentication is disabled or not configured for this debug build.',
    AuthProblem.emailUnconfirmed => 'Confirm your email before signing in.',
    AuthProblem.invalidLink =>
      'This verification link is invalid, expired, or already used.',
    AuthProblem.recoveryRequired =>
      'Complete password recovery, then sign in again.',
    AuthProblem.passwordRejected => 'The password change could not be completed. Use a new password of at least 16 characters.',
  };
  @override
  String toString() => message;
}

class SpaceContext {
  const SpaceContext({
    required this.id,
    required this.state,
    required this.epoch,
  });
  final String id;
  final String state;
  final int epoch;
}

class AccountContext {
  const AccountContext({
    required this.userId,
    required this.spaces,
    this.displayName,
    this.email,
  });
  final String userId;
  final List<SpaceContext> spaces;

  /// Display-only Auth metadata, never used to grant access.
  final String? displayName;
  final String? email;
}

abstract interface class AuthRepository {
  Stream<AuthSignal> get changes;
  Future<void> signIn(String email, String password);
  Future<AccountContext> accountContext();

  /// Discards this process's session. Does NOT call server logout or revoke JWTs.
  Future<void> clearLocalSession();
  Future<void> dispose();
}

/// Local/debug lifecycle only. No persistent recovery or automatic refresh.
abstract interface class LifecycleAuthRepository implements AuthRepository {
  Future<void> refreshSession();
  Future<void> signOut();
  Future<void> register(String email, String password);
  Future<void> requestRecovery(String email);
  Future<void> verifyLink(String link, {required bool recovery});
  Future<void> updatePassword(String password);
}

/// Supported Auth operations used by the account creation/confirmation forms.
abstract interface class AuthExperienceRepository
    implements LifecycleAuthRepository {
  Future<void> registerProfile(
    String email,
    String password,
    String displayName,
  );
  Future<void> resendVerification(String email);
}
