import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/app/twogethera_app.dart';
import 'package:twogethera/core/config/local_auth_config.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/data/local_auth_clients.dart';
import 'package:twogethera/features/authentication/data/supabase_auth_repository.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';

import 'browser_storage.dart';

void registerRealAuthTests() {
  final fixture = jsonDecode(
    const String.fromEnvironment('CP005A_FIXTURE'),
  ) as Map<String, dynamic>;
  LocalAuthClients clients() => LocalAuthClients(
    url: fixture['url'] as String,
    publicKey: fixture['key'] as String,
  );
  Future<void> control(String action) async {
    // The test-only local broker controls one fixed synthetic account, no SQL/UID input.
    final client = FunctionsClient('${fixture['control']}/functions/v1', {
      'X-Local-Proof': fixture['nonce'] as String,
    });
    try {
      final response = await client.invoke(action);
      expect(response.status, 200);
    } finally {
      await client.dispose();
    }
  }

  // functions.invoke adds /functions/v1; use its fixed test-only broker route below.
  testWidgets(
    'REAL: UI login, protected context, suspension, restoration and no browser persistence',
    (tester) async {
      final before = await tester.runAsync(persistenceSnapshot);
      final repository = SupabaseAuthRepository(createClients: clients);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          localAuthConfigProvider.overrideWithValue(
            LocalAuthConfig(
              endpoint: Uri.parse(fixture['url'] as String),
              publicKey: fixture['key'] as String,
            ),
          ),
        ],
      );
      container.read(appRouterProvider).go('/account');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TwogetheraApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/auth/local',
      );
      await tester.runAsync(() async {
        await container
            .read(authControllerProvider.notifier)
            .signIn(fixture['email'] as String, 'incorrect synthetic password');
      });
      await tester.pumpAndSettle();
      expect(
        container.read(authControllerProvider).problem,
        AuthProblem.invalidCredentials,
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        fixture['email'] as String,
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        fixture['password'] as String,
      );
      await tester.ensureVisible(find.text('Sign in locally'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Sign in locally'));
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (container.read(authControllerProvider).phase !=
                AuthPhase.authenticated &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
      expect(
        container.read(authControllerProvider).phase,
        AuthPhase.authenticated,
      );
      expect(
        container.read(authControllerProvider).context!.userId,
        fixture['userId'],
      );
      expect(find.byKey(const ValueKey('account-verified')), findsOneWidget);
      await tester.runAsync(() async {
        await control('suspend');
        await container.read(authControllerProvider.notifier).reloadContext();
      });
      await tester.pumpAndSettle();
      expect(
        container.read(authControllerProvider).problem,
        AuthProblem.denied,
      );
      expect(container.read(authControllerProvider).context, isNull);
      expect(find.byKey(const ValueKey('account-verified')), findsNothing);
      await tester.runAsync(() async {
        await control('restore');
        await container.read(authControllerProvider.notifier).reloadContext();
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-verified')), findsOneWidget);
      if (fixture['native'] == true) {
        // Audit while the installed application still owns a live session;
        // Flutter's native test cleanup can uninstall it after the suite exits.
        await tester.runAsync(() => control('audit'));
      }
      final fresh = SupabaseAuthRepository(createClients: clients);
      await tester.runAsync(() async {
        var denied = false;
        try {
          await fresh.accountContext();
        } on AuthFailure catch (e) {
          denied = e.problem == AuthProblem.expired;
        }
        expect(
          denied,
          isTrue,
          reason: 'Fresh repository must not restore previous login',
        );
        await fresh.dispose();
        await container
            .read(authControllerProvider.notifier)
            .clearLocalSession();
      });
      await tester.pumpAndSettle();
      final after = await tester.runAsync(persistenceSnapshot);
      expect(
        before == after,
        isTrue,
        reason: 'Browser persistence changed; values deliberately suppressed',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.runAsync(repository.dispose);
    },
  );

  test('REAL: unreachable local backend yields a sanitized failure', () async {
    final repository = SupabaseAuthRepository(
      createClients: () => LocalAuthClients(
        url: 'http://127.0.0.1:1',
        publicKey: fixture['key'] as String,
      ),
    );
    var safe = false;
    try {
      await repository.signIn(
        fixture['email'] as String,
        fixture['password'] as String,
      );
    } on AuthFailure catch (error) {
      safe = error.problem == AuthProblem.unavailable;
    } finally {
      await repository.dispose();
    }
    expect(safe, isTrue);
  });

  testWidgets(
    'HTTP: UI renders while a controlled endpoint delays then fails',
    (tester) async {
      // This test uses a real delayed HTTP 503, not Supabase authorization evidence.
      final repository = SupabaseAuthRepository(
        createClients: () => LocalAuthClients(
          url: fixture['unavailableUrl'] as String,
          publicKey: fixture['nonce'] as String,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          localAuthConfigProvider.overrideWithValue(
            LocalAuthConfig(
              endpoint: Uri.parse(fixture['url'] as String),
              publicKey: fixture['key'] as String,
            ),
          ),
        ],
      );
      try {
        container.read(appRouterProvider).go('/auth/local');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TwogetheraApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final pending = container
              .read(authControllerProvider.notifier)
              .signIn(
                fixture['email'] as String,
                fixture['password'] as String,
              );
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(
            container.read(authControllerProvider).phase,
            AuthPhase.loading,
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.text('Checking local access…'), findsOneWidget);
          await pending;
        });
        await tester.pumpAndSettle();
        expect(
          container.read(authControllerProvider).problem,
          AuthProblem.unavailable,
        );
        expect(container.read(authControllerProvider).context, isNull);
        expect(find.text('Sign in locally'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.runAsync(repository.dispose);
      }
    },
  );

  test('REAL: genuine short-lived Auth JWT expires without refresh; adapter and server deny it', () async {
    LocalAuthClients? active;
    final repository = SupabaseAuthRepository(
      createClients: () => active = LocalAuthClients(
        url: fixture['expiryUrl'] as String,
        publicKey: fixture['expiryKey'] as String,
      ),
    );
    final expired = Completer<void>();
    final subscription = repository.changes.listen((event) {
      if (event == AuthSignal.expired && !expired.isCompleted) {
        expired.complete();
      }
    });
    await repository.signIn(
      fixture['expiryEmail'] as String,
      fixture['expiryPassword'] as String,
    );
    final token = active!.validSession().accessToken;
    final ownUser = active!.validSession().user.id;
    final peer = GoTrueClient(
      url: '${fixture['url']}/auth/v1',
      headers: {'apikey': fixture['key'] as String},
      autoRefreshToken: false,
      asyncStorage: MemoryAuthStorage(),
    );
    await peer.signInWithPassword(
      email: fixture['email'] as String,
      password: fixture['password'] as String,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(
      active!.validSession().user.id == ownUser,
      isTrue,
      reason: 'Peer sign-in must not replace the explicitly accepted session',
    );
    peer.dispose();
    await expired.future.timeout(const Duration(seconds: 90));
    var localDenied = false;
    try {
      await repository.accountContext();
    } on AuthFailure catch (e) {
      localDenied = e.problem == AuthProblem.expired;
    }
    expect(localDenied, isTrue);
    final probe = SupabaseClient(
      fixture['expiryUrl'] as String,
      fixture['expiryKey'] as String,
      postgrestOptions: const PostgrestClientOptions(
        schema: 'cp004b1',
        retryEnabled: false,
      ),
      accessToken: () async => token,
    );
    // The pinned server permits verifier clock tolerance; poll actual HTTP denial
    // rather than assuming the client expiry timer and server rejection coincide.
    var serverDenied = false;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (!serverDenied && DateTime.now().isBefore(deadline)) {
      try {
        await probe.rpc('whoami');
      } on PostgrestException catch (error) {
        serverDenied = {'PGRST301', 'PGRST303'}.contains(error.code);
        if (!serverDenied) {
          throw const AuthFailure(AuthProblem.unavailable);
        }
      }
      if (!serverDenied) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    expect(
      serverDenied,
      isTrue,
      reason: 'Actual expired user token must fail verification',
    );
    await subscription.cancel();
    await repository.dispose();
    await probe.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
