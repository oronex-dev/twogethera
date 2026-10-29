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
  LocalAuthClients({required String url, required String publicKey}) {
    auth = GoTrueClient(
      url: '$url/auth/v1',
      headers: {'apikey': publicKey},
      autoRefreshToken: false,
      asyncStorage: storage,
    );
    data = SupabaseClient(
      url,
      publicKey,
      postgrestOptions: const PostgrestClientOptions(
        schema: 'cp004b2',
        retryEnabled: false,
        requestTimeout: Duration(seconds: 8),
      ),
      // Avoid SupabaseClient.getSession(): that can refresh on demand even when
      // autoRefreshToken is false. This client has no separate Auth instance.
      accessToken: () async => validSession().accessToken,
    );
  }
  final storage = MemoryAuthStorage();
  late final GoTrueClient auth;
  Session? _acceptedSession;
  Session? get acceptedSession => _acceptedSession;
  void acceptSession(Session session) {
    _acceptedSession = session;
  }

  late final SupabaseClient data;

  Session validSession() {
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
    _acceptedSession = null;
    auth.dispose();
    storage.clear();
    await data.dispose();
  }
}
