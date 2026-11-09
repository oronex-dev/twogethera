import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/authentication/domain/password_policy.dart';

import 'authentication_test.dart' show FakeAuthRepository, setup, show;

/// Isolated controller/widget fake; never counted as Auth or database evidence.
class LifecycleFake extends FakeAuthRepository
    implements LifecycleAuthRepository {
  Completer<void>? refreshWait;
  Completer<void>? logoutWait;
  bool logoutFailure = false;
  int refreshCalls = 0;
  int logoutCalls = 0;
  @override
  Future<void> refreshSession() async {
    refreshCalls++;
    await refreshWait?.future;
  }

  @override
  Future<void> signOut() async {
    logoutCalls++;
    events.add(AuthSignal.cleared);
    await logoutWait?.future;
    if (logoutFailure) throw const AuthFailure(AuthProblem.unavailable);
  }

  @override
  Future<void> register(String email, String password) async {}
  @override
  Future<void> requestRecovery(String email) async {}
  @override
  Future<void> verifyLink(String link, {required bool recovery}) async {
    events.add(recovery ? AuthSignal.recoveryVerified : AuthSignal.signedIn);
  }

  @override
  Future<void> updatePassword(String password) async {
    if (validateNewPassword(password) != null) {
      throw const AuthFailure(AuthProblem.passwordRejected);
    }
    events.add(AuthSignal.cleared);
  }
}

void main() {
  test('refreshing never exposes the previous account projection', () async {
    final fake = LifecycleFake();
    final container = setup(fake);
    addTearDown(container.dispose);
    addTearDown(fake.dispose);
    final controller = container.read(authControllerProvider.notifier);
    await controller.signIn('a@example.invalid', 'synthetic');
    fake.refreshWait = Completer<void>();
    final pending = controller.refreshSession();
    expect(container.read(authControllerProvider).phase, AuthPhase.refreshing);
    expect(container.read(authControllerProvider).context, isNull);
    fake.events.add(AuthSignal.expired);
    expect(container.read(authControllerProvider).phase, AuthPhase.refreshing);
    fake.refreshWait!.complete();
    await pending;
    expect(
      container.read(authControllerProvider).phase,
      AuthPhase.authenticated,
    );
  });

  test('logout invalidates a delayed refresh/context result', () async {
    final fake = LifecycleFake();
    final container = setup(fake);
    addTearDown(container.dispose);
    addTearDown(fake.dispose);
    final controller = container.read(authControllerProvider.notifier);
    await controller.signIn('a@example.invalid', 'synthetic');
    fake.refreshWait = Completer<void>();
    final refresh = controller.refreshSession();
    await controller.signOut();
    fake.refreshWait!.complete();
    await refresh;
    expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
    expect(container.read(authControllerProvider).context, isNull);
  });

  test('late logout failure cannot overwrite a newer sign-in', () async {
    final fake = LifecycleFake()
      ..logoutWait = Completer<void>()
      ..logoutFailure = true;
    final container = setup(fake);
    addTearDown(container.dispose);
    addTearDown(fake.dispose);
    final controller = container.read(authControllerProvider.notifier);
    await controller.signIn('a@example.invalid', 'synthetic');
    final logout = controller.signOut();
    await controller.signIn('a@example.invalid', 'synthetic');
    fake.logoutWait!.complete();
    await logout;
    expect(
      container.read(authControllerProvider).phase,
      AuthPhase.authenticated,
    );
    expect(container.read(authControllerProvider).notice, isNull);
  });

  test(
    'offline logout has no account data and discloses unconfirmed revocation',
    () async {
      final fake = LifecycleFake()..logoutFailure = true;
      final container = setup(fake);
      addTearDown(container.dispose);
      addTearDown(fake.dispose);
      final controller = container.read(authControllerProvider.notifier);
      await controller.signIn('a@example.invalid', 'synthetic');
      await controller.signOut();
      final state = container.read(authControllerProvider);
      expect(state.phase, AuthPhase.signedOut);
      expect(state.context, isNull);
      expect(state.recoverableNetworkFailure, isTrue);
      expect(state.notice, contains('could not be confirmed'));
    },
  );

  test(
    'registration waits for verification and does not authorize on request',
    () async {
      final fake = LifecycleFake();
      final container = setup(fake);
      addTearDown(container.dispose);
      addTearDown(fake.dispose);
      final controller = container.read(authControllerProvider.notifier);
      await controller.register('a@example.invalid', 'synthetic');
      expect(
        container.read(authControllerProvider).phase,
        AuthPhase.awaitingConfirmation,
      );
      expect(container.read(authControllerProvider).context, isNull);
      await controller.verifyLink('fake-unit-link', recovery: false);
      expect(
        container.read(authControllerProvider).phase,
        AuthPhase.authenticated,
      );
    },
  );

  test(
    'known and unknown recovery requests have the same public notice',
    () async {
      final fake = LifecycleFake();
      final container = setup(fake);
      addTearDown(container.dispose);
      addTearDown(fake.dispose);
      final controller = container.read(authControllerProvider.notifier);
      await controller.requestRecovery('known@example.invalid');
      final notice = container.read(authControllerProvider).notice;
      await controller.requestRecovery('absent@example.invalid');
      expect(container.read(authControllerProvider).notice, notice);
      expect(
        container.read(authControllerProvider).phase,
        AuthPhase.recoveryRequested,
      );
      expect(container.read(authControllerProvider).context, isNull);
    },
  );

  testWidgets(
    'recovery is not an authenticated account route, reset requires fresh sign-in',
    (tester) async {
      final fake = LifecycleFake();
      final container = setup(fake);
      addTearDown(container.dispose);
      addTearDown(fake.dispose);
      final controller = container.read(authControllerProvider.notifier);
      await controller.verifyLink('fake-unit-link', recovery: true);
      await show(tester, container, '/account');
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/auth/recovery',
      );
      expect(find.byKey(const ValueKey('account-verified')), findsNothing);
      await controller.updatePassword('short');
      await tester.pumpAndSettle();
      expect(
        container.read(authControllerProvider).phase,
        AuthPhase.recovering,
      );
      expect(
        container.read(authControllerProvider).problem,
        AuthProblem.passwordRejected,
      );
      await controller.updatePassword('NewPass123!');
      await tester.pumpAndSettle();
      expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
      expect(container.read(authControllerProvider).context, isNull);
    },
  );

  testWidgets(
    'cancel recovery signs out and leaves the route without a redirect loop',
    (tester) async {
      final fake = LifecycleFake();
      final container = setup(fake);
      addTearDown(container.dispose);
      addTearDown(fake.dispose);
      await container
          .read(authControllerProvider.notifier)
          .verifyLink('fake-unit-link', recovery: true);
      await show(tester, container, '/auth/recovery');
      await tester.tap(find.byTooltip('Back to sign-in'));
      await tester.pumpAndSettle();
      expect(fake.logoutCalls, 1);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/auth/local',
      );
    },
  );

  for (final route in ['/auth/register', '/auth/verify', '/auth/recovery']) {
    for (final width in [320.0, 768.0, 1440.0]) {
      testWidgets('$route fits $width at 200% text', (tester) async {
        final fake = LifecycleFake();
        final container = setup(fake);
        addTearDown(container.dispose);
        addTearDown(fake.dispose);
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await show(tester, container, route);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
