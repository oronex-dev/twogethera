enum AuthSignal { signedIn, cleared, expired }

enum AuthProblem {
  invalidCredentials,
  unavailable,
  denied,
  expired,
  configuration,
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
    AuthProblem.expired => 'Your local session expired. Sign in again.',
    AuthProblem.configuration => 'Local authentication is disabled or not configured for this debug build.',
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
