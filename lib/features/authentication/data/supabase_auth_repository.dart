import 'dart:async';

import 'package:supabase/supabase.dart';

import '../domain/auth_repository.dart';
import 'local_auth_clients.dart';

class SupabaseAuthRepository implements LifecycleAuthRepository {
  SupabaseAuthRepository({required this._createClients});
  final LocalAuthClients Function() _createClients;
  final _changes = StreamController<AuthSignal>.broadcast(sync: true);
  LocalAuthClients? _clients;
  StreamSubscription<AuthState>? _subscription;
  Timer? _expiry;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _refresh;
  @override
  Stream<AuthSignal> get changes => _changes.stream;

  LocalAuthClients _open() {
    if (_disposed) throw const AuthFailure(AuthProblem.expired);
    if (_clients != null) return _clients!;
    final clients = _clients = _createClients();
    _subscription = clients.auth.onAuthStateChange.listen(
      (event) {
        if (_clients != clients || _disposed) return;
        // Peer SDK broadcasts never authorize this adapter or replace its token.
        if (event.fromBroadcast) return;
        // SDK events are observed but never commit authority. Only an owned
        // operation's response, checked against its generation, may do that.
      },
      onError: (Object _, StackTrace _) {
        // Operations classify network/credential errors; no raw SDK diagnostics.
      },
    );
    return clients;
  }

  void _observeAcceptedSession(LocalAuthClients clients) {
    final session = clients.acceptedSession;
    final expiry = session?.expiresAt;
    if (expiry == null || _disposed || clients != _clients) return;
    _expiry?.cancel();
    final remaining = DateTime.fromMillisecondsSinceEpoch(expiry * 1000)
        .difference(DateTime.now());
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      // Keep the refresh credential in RAM for an explicit refresh only.
      // validSession still rejects every data request after access expiry.
      if (!_disposed && clients == _clients) _changes.add(AuthSignal.expired);
    });
    _changes.add(
      clients.recoveryOnly ? AuthSignal.recoveryVerified : AuthSignal.signedIn,
    );
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _discard(AuthSignal.cleared);
    if (!email.endsWith('@example.invalid')) {
      throw const AuthFailure(AuthProblem.invalidCredentials);
    }
    final clients = _open();
    final version = _generation;
    try {
      final response = await clients.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 8));
      if (_disposed || version != _generation || _clients != clients) {
        throw const AuthFailure(AuthProblem.expired);
      }
      final session = response.session;
      if (session == null) throw const AuthFailure(AuthProblem.expired);
      clients.acceptSession(session);
      clients.validSession();
      _observeAcceptedSession(clients);
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      _current(clients, version);
      await _discard(AuthSignal.cleared);
      throw AuthFailure(
        error.code == 'email_not_confirmed'
            ? AuthProblem.emailUnconfirmed
            : error.statusCode == '400' || error.statusCode == '401'
            ? AuthProblem.invalidCredentials
            : AuthProblem.unavailable,
      );
    } catch (error) {
      _current(clients, version);
      await _discard(AuthSignal.cleared);
      throw const AuthFailure(AuthProblem.unavailable);
    }
  }

  void _current(LocalAuthClients clients, int version) {
    if (_disposed || version != _generation || clients != _clients) {
      throw const AuthFailure(AuthProblem.expired);
    }
  }

  bool _transient(Object error) =>
      error is TimeoutException ||
      error is! AuthException ||
      error is AuthRetryableFetchException ||
      error.statusCode == null ||
      (int.tryParse(error.statusCode ?? '') ?? 0) >= 500;

  @override
  Future<void> refreshSession() {
    final pending = _refresh;
    if (pending != null) return pending;
    late final Future<void> operation;
    operation = _refreshOwned().whenComplete(() {
      if (identical(_refresh, operation)) _refresh = null;
    });
    _refresh = operation;
    return operation;
  }

  Future<void> _refreshOwned() async {
    final clients = _clients;
    final session = clients?.acceptedSession;
    if (clients == null || session?.refreshToken == null) {
      throw const AuthFailure(AuthProblem.expired);
    }
    if (clients.recoveryOnly) {
      throw const AuthFailure(AuthProblem.recoveryRequired);
    }
    final version = _generation;
    try {
      final result = await clients.auth
          .refreshSession(session!.refreshToken)
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
      final next = result.session;
      if (next == null || next.user.id != session.user.id) {
        throw const AuthFailure(AuthProblem.expired);
      }
      clients.acceptSession(next);
      clients.validSession();
      _observeAcceptedSession(clients);
    } catch (error) {
      if (version != _generation || clients != _clients || _disposed) {
        throw const AuthFailure(AuthProblem.expired);
      }
      // A lost response may have rotated the token on the server. Never retry
      // a possibly spent credential: fail closed and require explicit sign-in.
      await _discard(AuthSignal.expired);
      throw AuthFailure(
        _transient(error) ? AuthProblem.unavailable : AuthProblem.expired,
      );
    }
  }

  @override
  Future<void> signOut() => _logout(SignOutScope.local);

  Future<void> _logout(SignOutScope scope) async {
    final clients = _clients;
    final session = clients?.acceptedSession;
    // Detach authority BEFORE any server await; retain only the outbound
    // operation's credential until its bounded revocation request completes.
    _generation++;
    _expiry?.cancel();
    _clients = null;
    _refresh = null;
    final subscription = _subscription;
    _subscription = null;
    clients?.clearAcceptedSession();
    if (!_disposed) _changes.add(AuthSignal.cleared);
    await subscription?.cancel();
    if (clients == null) return;
    try {
      if (session != null) {
        var token = session.accessToken;
        if (session.isExpired) {
          final refreshed = await clients.auth
              .refreshSession(session.refreshToken)
              .timeout(const Duration(seconds: 8));
          token =
              refreshed.session?.accessToken ??
              (throw const AuthFailure(AuthProblem.expired));
        }
        // This is the same supported /logout operation used by SDK signOut.
        // Despite its SDK namespace, it uses the OWN USER JWT + public key,
        // never a service-role/admin credential or a peer's currentSession.
        await clients.auth.admin
            .signOut(token, scope: scope)
            .timeout(const Duration(seconds: 8));
      }
    } catch (_) {
      throw const AuthFailure(AuthProblem.unavailable);
    } finally {
      await clients.dispose();
    }
  }

  void _synthetic(String email) {
    if (!email.endsWith('@example.invalid')) {
      throw const AuthFailure(AuthProblem.invalidCredentials);
    }
  }

  @override
  Future<void> register(String email, String password) async {
    await _discard(AuthSignal.cleared);
    _synthetic(email);
    if (password.length < 16) {
      throw const AuthFailure(AuthProblem.passwordRejected);
    }
    final clients = _open();
    final version = _generation;
    try {
      final response = await clients.auth
          .signUp(email: email, password: password)
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
      if (response.session != null) {
        throw const AuthFailure(AuthProblem.configuration);
      }
    } on AuthFailure {
      rethrow;
    } catch (error) {
      throw AuthFailure(
        _transient(error)
            ? AuthProblem.unavailable
            : AuthProblem.passwordRejected,
      );
    }
  }

  @override
  Future<void> requestRecovery(String email) async {
    await _discard(AuthSignal.cleared);
    _synthetic(email);
    final clients = _open();
    final version = _generation;
    try {
      await clients.auth
          .resetPasswordForEmail(email)
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
    } on AuthFailure {
      rethrow;
    } catch (error) {
      if (_transient(error)) throw const AuthFailure(AuthProblem.unavailable);
      // Identical public response for absent/known addresses and auth API
      // account-specific request errors. No mailbox/existence information.
    }
  }

  @override
  Future<void> verifyLink(String link, {required bool recovery}) async {
    await _discard(AuthSignal.cleared);
    final clients = _open();
    final version = _generation;
    final uri = Uri.tryParse(link.trim());
    final type = recovery ? 'recovery' : 'signup';
    if (uri == null ||
        uri.scheme != 'http' ||
        !{'127.0.0.1', 'localhost', '10.0.2.2'}.contains(uri.host) ||
        uri.port != clients.endpoint.port ||
        uri.path != '/auth/v1/verify' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParameters['type'] != type ||
        link.length > 8192) {
      throw const AuthFailure(AuthProblem.invalidLink);
    }
    final hash =
        uri.queryParameters['token'] ?? uri.queryParameters['token_hash'];
    if (hash == null || hash.isEmpty) {
      throw const AuthFailure(AuthProblem.invalidLink);
    }
    try {
      final response = await clients.auth
          .verifyOTP(
            tokenHash: hash,
            type: recovery ? OtpType.recovery : OtpType.signup,
          )
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
      final session = response.session;
      if (session == null) throw const AuthFailure(AuthProblem.invalidLink);
      clients.acceptSession(session, recovery: recovery);
      _observeAcceptedSession(clients);
    } on AuthFailure {
      rethrow;
    } catch (error) {
      throw AuthFailure(
        _transient(error) ? AuthProblem.unavailable : AuthProblem.invalidLink,
      );
    }
  }

  @override
  Future<void> updatePassword(String password) async {
    if (password.length < 16) {
      throw const AuthFailure(AuthProblem.passwordRejected);
    }
    final clients = _clients;
    final version = _generation;
    if (clients == null || !clients.recoveryOnly) {
      throw const AuthFailure(AuthProblem.recoveryRequired);
    }
    try {
      await clients
          .updatePasswordPinned(password)
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
      // A password reset revokes all Auth refresh sessions, including this
      // recovery session; require fresh password sign-in afterward.
      await _logout(SignOutScope.global);
    } on AuthFailure {
      rethrow;
    } catch (error) {
      throw AuthFailure(
        _transient(error)
            ? AuthProblem.unavailable
            : AuthProblem.passwordRejected,
      );
    }
  }

  @override
  Future<AccountContext> accountContext() async {
    final clients = _clients;
    if (clients == null) throw const AuthFailure(AuthProblem.expired);
    final version = _generation;
    try {
      final session = clients.validSession();
      await clients.data.rpc('ensure_account');
      final result = await clients.data.rpc('account_context');
      if (version != _generation || _disposed || _clients != clients) {
        throw const AuthFailure(AuthProblem.expired);
      }
      clients.validSession();
      if (result is! Map ||
          result['user_id'] != session.user.id ||
          result['spaces'] is! List) {
        throw const AuthFailure(AuthProblem.denied);
      }
      final spaces = <SpaceContext>[];
      for (final row in result['spaces'] as List) {
        if (row is! Map ||
            row['space_id'] is! String ||
            !{'draft', 'paired'}.contains(row['state']) ||
            row['epoch'] is! int) {
          throw const AuthFailure(AuthProblem.denied);
        }
        spaces.add(
          SpaceContext(
            id: row['space_id'] as String,
            state: row['state'] as String,
            epoch: row['epoch'] as int,
          ),
        );
      }
      return AccountContext(
        userId: session.user.id,
        spaces: List.unmodifiable(spaces),
      );
    } on AuthFailure {
      rethrow;
    } on PostgrestException catch (error) {
      _current(clients, version);
      if (error.code == '42501') throw const AuthFailure(AuthProblem.denied);
      if (error.code == 'PGRST301' || error.code == 'PGRST303') {
        await _discard(AuthSignal.expired);
        throw const AuthFailure(AuthProblem.expired);
      }
      throw const AuthFailure(AuthProblem.unavailable);
    } on AuthException {
      _current(clients, version);
      await _discard(AuthSignal.expired);
      throw const AuthFailure(AuthProblem.expired);
    } catch (_) {
      throw const AuthFailure(AuthProblem.unavailable);
    }
  }

  Future<void> _discard(AuthSignal reason) async {
    _generation++;
    _expiry?.cancel();
    final clients = _clients;
    _clients = null;
    final subscription = _subscription;
    _subscription = null;
    _refresh = null;
    if (!_disposed) _changes.add(reason);
    await subscription?.cancel();
    await clients?.dispose();
  }

  @override
  Future<void> clearLocalSession() => _discard(AuthSignal.cleared);
  @override
  Future<void> dispose() async {
    _disposed = true;
    await _discard(AuthSignal.cleared);
    await _changes.close();
  }
}
