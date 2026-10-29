import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/local_auth_config.dart';
import '../data/local_auth_clients.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';

enum AuthPhase { signedOut, loading, authenticated, error }

class AuthViewState {
  const AuthViewState(this.phase, {this.context, this.problem});
  final AuthPhase phase;
  final AccountContext? context;
  final AuthProblem? problem;
}

final authClientFactoryProvider = Provider<LocalAuthClients Function()>((ref) {
  final config = ref.watch(localAuthConfigProvider);
  return () {
    if (config == null) throw const AuthFailure(AuthProblem.configuration);
    return LocalAuthClients(
      url: config.endpoint.toString(),
      publicKey: config.publicKey,
    );
  };
});
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = SupabaseAuthRepository(
    createClients: ref.watch(authClientFactoryProvider),
  );
  ref.onDispose(() => unawaited(repository.dispose()));
  return repository;
});
final authControllerProvider = NotifierProvider<AuthController, AuthViewState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthViewState> {
  int _version = 0;
  bool _busy = false;
  bool _alive = true;
  @override
  AuthViewState build() {
    _alive = true;
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.changes.listen((signal) {
      if (!_alive) return;
      if (signal == AuthSignal.expired ||
          (signal == AuthSignal.cleared && !_busy)) {
        _version++;
        state = AuthViewState(
          AuthPhase.signedOut,
          problem: signal == AuthSignal.expired ? AuthProblem.expired : null,
        );
      } else if (signal == AuthSignal.signedIn && !_busy) {
        unawaited(reloadContext());
      }
    });
    ref.onDispose(() {
      _alive = false;
      _version++;
      unawaited(subscription.cancel());
    });
    return const AuthViewState(AuthPhase.signedOut);
  }

  Future<void> signIn(String email, String password) => _run(() async {
    final repository = ref.read(authRepositoryProvider);
    await repository.signIn(email.trim(), password);
    return repository.accountContext();
  });
  Future<void> reloadContext() =>
      _run(() => ref.read(authRepositoryProvider).accountContext());

  Future<void> _run(Future<AccountContext> Function() action) async {
    if (_busy) return;
    _busy = true;
    final version = ++_version;
    state = const AuthViewState(AuthPhase.loading);
    try {
      final context = await action();
      if (_alive && version == _version) {
        state = AuthViewState(AuthPhase.authenticated, context: context);
      }
    } on AuthFailure catch (error) {
      if (_alive && version == _version) {
        state = AuthViewState(
          error.problem == AuthProblem.expired
              ? AuthPhase.signedOut
              : AuthPhase.error,
          problem: error.problem,
        );
      }
    } catch (_) {
      if (_alive && version == _version) {
        state = const AuthViewState(
          AuthPhase.error,
          problem: AuthProblem.unavailable,
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> clearLocalSession() async {
    _version++;
    state = const AuthViewState(AuthPhase.signedOut);
    await ref.read(authRepositoryProvider).clearLocalSession();
  }
}
