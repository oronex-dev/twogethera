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
      'Sign-in could not be completed. Check your synthetic credentials.',
    AuthProblem.unavailable =>
      'The local backend is unavailable. Try again when it is running.',
    AuthProblem.denied =>
      'This account cannot access the local proof. No shared data was loaded.',
    AuthProblem.expired =>
      'Local access expired. Refresh explicitly or sign in again.',
    AuthProblem.configuration => 'Local authentication is disabled or not configured for this debug build.',
    AuthProblem.emailUnconfirmed => 'Confirm the account using the local development mailbox before signing in.',
    AuthProblem.invalidLink =>
      'This local verification link is invalid, expired, or already used.',
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
  const AccountContext({required this.userId, required this.spaces});
  final String userId;
  final List<SpaceContext> spaces;
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
