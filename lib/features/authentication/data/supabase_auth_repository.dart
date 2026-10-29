import 'dart:async';

import 'package:supabase/supabase.dart';

import '../domain/auth_repository.dart';
import 'local_auth_clients.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({required this._createClients});
  final LocalAuthClients Function() _createClients;
  final _changes = StreamController<AuthSignal>.broadcast(sync: true);
  LocalAuthClients? _clients;
  StreamSubscription<AuthState>? _subscription;
  Timer? _expiry;
  int _generation = 0;
  bool _disposed = false;
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
        if (event.event == AuthChangeEvent.signedOut) {
          unawaited(_discard(AuthSignal.cleared));
        } else if (clients.acceptedSession != null) {
          _observeAcceptedSession(clients);
        }
      },
      onError: (Object _, StackTrace _) {
        if (!_disposed) unawaited(_discard(AuthSignal.expired));
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
      unawaited(_discard(AuthSignal.expired));
    });
    _changes.add(AuthSignal.signedIn);
  }

  @override
  Future<void> signIn(String email, String password) async {
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
      await _discard(AuthSignal.cleared);
      throw AuthFailure(
        error.statusCode == '400' || error.statusCode == '401'
            ? AuthProblem.invalidCredentials
            : AuthProblem.unavailable,
      );
    } catch (error) {
      await _discard(AuthSignal.cleared);
      throw const AuthFailure(AuthProblem.unavailable);
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
      if (error.code == '42501') throw const AuthFailure(AuthProblem.denied);
      if (error.code == 'PGRST301' || error.code == 'PGRST303') {
        await _discard(AuthSignal.expired);
        throw const AuthFailure(AuthProblem.expired);
      }
      throw const AuthFailure(AuthProblem.unavailable);
    } on AuthException {
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
