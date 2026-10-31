import 'dart:convert';

import 'package:supabase/supabase.dart';

import '../domain/auth_repository.dart';

/// SDK storage seam for PKCE only; no disk/browser implementation is installed.
/// Password login sessions live in GoTrueClient's own RAM, never in this map.
class MemoryAuthStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = {};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }

  void clear() => _values.clear();
}

class LocalAuthClients {
  LocalAuthClients({
    required String url,
    required String publicKey,
    GoTrueClient? authClient,
  }) : endpoint = Uri.parse(url) {
    auth =
        authClient ??
        GoTrueClient(
          url: '$url/auth/v1',
          headers: {'apikey': publicKey},
          autoRefreshToken: false,
          asyncStorage: storage,
        );
    data = SupabaseClient(
      url,
      publicKey,
      // The pinned Supabase SDK constructs an internal GoTrueClient even with
      // accessToken supplied. Disable its ticker too: otherwise a web broadcast
      // can seed that hidden client and rotate our refresh token behind us.
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: storage,
      ),
      postgrestOptions: const PostgrestClientOptions(
        schema: 'cp004b2',
        retryEnabled: false,
        requestTimeout: Duration(seconds: 8),
      ),
      // Avoid SupabaseClient.getSession(): that can refresh on demand even when
      // autoRefreshToken is false. Its internal Auth instance is unused.
      accessToken: () async => validSession().accessToken,
    );
  }
  final storage = MemoryAuthStorage();
  final Uri endpoint;
  late final GoTrueClient auth;
  Session? _acceptedSession;
  bool recoveryOnly = false;
  Session? get acceptedSession => _acceptedSession;
  void acceptSession(Session session, {bool recovery = false}) {
    _acceptedSession = session;
    recoveryOnly = recovery;
  }

  void clearAcceptedSession() {
    _acceptedSession = null;
    recoveryOnly = false;
  }

  /// SDK updateUser reads currentSession. Seed our accepted RAM snapshot and
  /// invoke updateUser in the SAME stack before a peer BroadcastChannel event
  /// can run. The pinned SDK setter has no await on its valid-session branch.
  Future<void> updatePasswordPinned(String password) async {
    final session = _acceptedSession;
    if (session == null || !recoveryOnly || session.isExpired) {
      throw const AuthFailure(AuthProblem.recoveryRequired);
    }
    final seeded = auth.setInitialSession(jsonEncode(session.toJson()));
    final updated = auth.updateUser(UserAttributes(password: password));
    await seeded;
    final response = await updated;
    if (response.user?.id != session.user.id) {
      throw const AuthFailure(AuthProblem.denied);
    }
  }

  late final SupabaseClient data;

  Session validSession() {
    if (recoveryOnly) throw const AuthFailure(AuthProblem.recoveryRequired);
    final session = _acceptedSession;
    final expiry = session?.expiresAt;
    if (session == null ||
        expiry == null ||
        DateTime.now().millisecondsSinceEpoch >= expiry * 1000) {
      throw const AuthFailure(AuthProblem.expired);
    }
    return session;
  }

  Future<void> dispose() async {
    clearAcceptedSession();
    auth.dispose();
    storage.clear();
    await data.dispose();
  }
}
