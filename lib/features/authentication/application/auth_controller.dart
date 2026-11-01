import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/local_auth_config.dart';
import '../data/local_auth_clients.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';
import '../../partner_linking/domain/partner_invitation_repository.dart';

enum AuthPhase {
  signedOut,
  loading,
  authenticated,
  error,
  refreshing,
  recovering,
  awaitingConfirmation,
  recoveryRequested,
}

class AuthViewState {
  const AuthViewState(this.phase, {this.context, this.problem, this.notice});
  final AuthPhase phase;
  final AccountContext? context;
  final AuthProblem? problem;
  final String? notice;
  bool get suspended => problem == AuthProblem.denied;
  bool get expired => problem == AuthProblem.expired;
  bool get recoverableNetworkFailure => problem == AuthProblem.unavailable;
}

final authClientFactoryProvider = Provider<LocalAuthClients Function()>((ref) {
  final config = ref.watch(localAuthConfigProvider);
  return () {
    if (config == null) throw const AuthFailure(AuthProblem.configuration);
    return LocalAuthClients(
      url: config.endpoint.toString(),
      publicKey: config.publicKey,
      schema: config.dataSchema,
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
final partnerInvitationRepositoryProvider =
    Provider<PartnerInvitationRepository>((ref) {
      final repository = ref.watch(authRepositoryProvider);
      if (repository is PartnerInvitationRepository) {
        return repository as PartnerInvitationRepository;
      }
      throw const AuthFailure(AuthProblem.configuration);
    });
final authControllerProvider = NotifierProvider<AuthController, AuthViewState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthViewState> {
  int _version = 0;
  bool _busy = false;
  bool _alive = true;
  int _lease = 0;
  @override
  AuthViewState build() {
    _alive = true;
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.changes.listen((signal) {
      if (!_alive) return;
      if (signal == AuthSignal.recoveryVerified && !_busy) {
        _version++;
        state = const AuthViewState(AuthPhase.recovering);
        return;
      }
      if (signal == AuthSignal.expired && state.phase == AuthPhase.refreshing) {
        state = const AuthViewState(
          AuthPhase.refreshing,
          problem: AuthProblem.expired,
        );
        return;
      }
      if (signal == AuthSignal.cleared &&
          state.phase == AuthPhase.signedOut &&
          !_busy) {
        return;
      }
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

  LifecycleAuthRepository get _lifecycle {
    final repository = ref.read(authRepositoryProvider);
    if (repository is! LifecycleAuthRepository) {
      throw const AuthFailure(AuthProblem.configuration);
    }
    return repository;
  }

  Future<void> refreshSession() => _run(() async {
    await _lifecycle.refreshSession();
    return _lifecycle.accountContext();
  }, during: AuthPhase.refreshing);

  Future<void> register(String email, String password, {String? displayName}) =>
      _run(
        () async {
          if (displayName == null) {
            await _lifecycle.register(email.trim(), password);
          } else {
            final repository = _lifecycle;
            if (repository is! AuthExperienceRepository) {
              throw const AuthFailure(AuthProblem.configuration);
            }
            await repository.registerProfile(
              email.trim(),
              password,
              displayName,
            );
          }
          return null;
        },
        success: AuthPhase.awaitingConfirmation,
        notice: 'If the request is eligible, check the local development mailbox for confirmation.',
      );

  Future<void> resendVerification(String email) => _run(
    () async {
      final repository = _lifecycle;
      if (repository is! AuthExperienceRepository) {
        throw const AuthFailure(AuthProblem.configuration);
      }
      await repository.resendVerification(email.trim());
      return null;
    },
    success: AuthPhase.awaitingConfirmation,
    notice: 'If the address is eligible, a new confirmation message will appear in the local development mailbox. Use the newest link.',
  );

  Future<void> requestRecovery(String email) => _run(
    () async {
      await _lifecycle.requestRecovery(email.trim());
      return null;
    },
    success: AuthPhase.recoveryRequested,
    notice: 'If the address is eligible, a reset message will appear in the local development mailbox.',
  );

  Future<void> verifyLink(String link, {required bool recovery}) =>
      _run(() async {
        await _lifecycle.verifyLink(link, recovery: recovery);
        return recovery ? null : await _lifecycle.accountContext();
      }, success: recovery ? AuthPhase.recovering : AuthPhase.authenticated);

  Future<void> updatePassword(String password) => _run(
    () async {
      await _lifecycle.updatePassword(password);
      return null;
    },
    success: AuthPhase.signedOut,
    notice: 'Password changed. Sign in again. Auth refresh sessions were revoked; issued access tokens may last until expiry.',
    recoveringOnPasswordError: true,
  );

  Future<void> signOut() async {
    final version = ++_version;
    _lease++;
    _busy = false;
    state = const AuthViewState(AuthPhase.signedOut);
    try {
      await _lifecycle.signOut();
    } catch (_) {
      if (_alive && version == _version) {
        state = const AuthViewState(
          AuthPhase.signedOut,
          problem: AuthProblem.unavailable,
          notice: 'Local memory was cleared. Server sign-out could not be confirmed; issued credentials may remain valid.',
        );
      }
    }
  }

  Future<void> _run(
    Future<AccountContext?> Function() action, {
    AuthPhase during = AuthPhase.loading,
    AuthPhase success = AuthPhase.authenticated,
    String? notice,
    bool recoveringOnPasswordError = false,
  }) async {
    if (_busy) return;
    _busy = true;
    final version = ++_version;
    final lease = ++_lease;
    state = AuthViewState(during);
    try {
      final context = await action();
      if (_alive && version == _version) {
        state = AuthViewState(success, context: context, notice: notice);
      }
    } on AuthFailure catch (error) {
      if (_alive && version == _version) {
        state = AuthViewState(
          error.problem == AuthProblem.expired
              ? AuthPhase.signedOut
              : recoveringOnPasswordError &&
                    error.problem == AuthProblem.passwordRejected
              ? AuthPhase.recovering
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
      if (lease == _lease) _busy = false;
    }
  }

  Future<void> clearLocalSession() async {
    _version++;
    _lease++;
    _busy = false;
    state = const AuthViewState(AuthPhase.signedOut);
    await ref.read(authRepositoryProvider).clearLocalSession();
  }
}
