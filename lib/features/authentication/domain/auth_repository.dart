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
  emailAlreadyRegistered,
  registrationRejected,
  reauthenticationRequired,
  reauthenticationFailed,
  lifecycleUnavailable,
}

class AuthFailure implements Exception {
  const AuthFailure(this.problem);
  final AuthProblem problem;

  static AuthFailure registrationResponse({
    required String? code,
    required bool transient,
  }) => AuthFailure(switch (code) {
    'email_exists' ||
    'user_already_exists' => AuthProblem.emailAlreadyRegistered,
    'weak_password' => AuthProblem.passwordRejected,
    _ when transient => AuthProblem.unavailable,
    _ => AuthProblem.registrationRejected,
  });

  String get message => switch (problem) {
    AuthProblem.invalidCredentials =>
      'Sign-in could not be completed. Check your email and password.',
    AuthProblem.unavailable =>
      'Authentication is temporarily unavailable. Try again shortly.',
    AuthProblem.denied => 'This account cannot access shared data. Contact support if you think this is an error.',
    AuthProblem.expired =>
      'Local access expired. Refresh explicitly or sign in again.',
    AuthProblem.configuration => 'Local authentication is unavailable in this debug build. Check the local development configuration and restart the app.',
    AuthProblem.emailUnconfirmed => 'Confirm your email before signing in.',
    AuthProblem.invalidLink =>
      'This verification link is invalid, expired, or already used.',
    AuthProblem.recoveryRequired =>
      'Complete password recovery, then sign in again.',
    AuthProblem.passwordRejected => 'Use at least 8 characters with uppercase, lowercase, a number, and a special character.',
    AuthProblem.emailAlreadyRegistered => 'An account already exists for this address. Sign in, or use Confirm your email if it is still unconfirmed.',
    AuthProblem.registrationRejected => 'We could not create the account. Check the details and try again, or sign in if you already registered.',
    AuthProblem.reauthenticationRequired =>
      'Verify your password again to continue this sensitive action.',
    AuthProblem.reauthenticationFailed =>
      'Password verification failed. Check your password and try again.',
    AuthProblem.lifecycleUnavailable => 'The account action could not be completed. Your shared space may already be closed; sign in and check its status before retrying.',
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

/// Destructive Private Beta V1 account lifecycle commands. Implementations
/// must keep their authorization in Supabase RPC/Edge Function boundaries.
abstract interface class PrivateBetaAccountLifecycleRepository {
  Future<void> closeCoupleSpace(String operationId);
  Future<void> deleteAccount(String operationId);
}

abstract interface class PrivacyRemovalRepository {
  Future<void> requestPrivacyRemoval({
    required String table,
    required String recordId,
    String? field,
    bool removeRecord = true,
  });
}

/// A fresh password grant is required before privacy removal or account
/// deletion. Implementations must bind it to the currently authenticated user.
abstract interface class RecentReauthenticationRepository {
  Future<void> reauthenticateWithPassword(String password);
}
