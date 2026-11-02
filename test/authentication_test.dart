import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/app/twogethera_app.dart';
import 'package:twogethera/core/config/local_auth_config.dart';
import 'package:twogethera/core/config/supabase_runtime_config.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/data/local_auth_clients.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';

/// Isolated fake for controller/widgets ONLY. Not backend-security evidence.
class FakeAuthRepository implements AuthRepository {
  final events = StreamController<AuthSignal>.broadcast(sync: true);
  AuthProblem? failure;
  Completer<AccountContext>? pending;
  int logins = 0;
  @override
  Stream<AuthSignal> get changes => events.stream;
  @override
  Future<void> signIn(String email, String password) async {
    logins++;
    if (failure != null) throw AuthFailure(failure!);
    events.add(AuthSignal.signedIn);
  }

  @override
  Future<AccountContext> accountContext() async {
    if (failure != null) throw AuthFailure(failure!);
    if (pending != null) return pending!.future;
    return const AccountContext(userId: 'synthetic-user', spaces: []);
  }

  @override
  Future<void> clearLocalSession() async => events.add(AuthSignal.cleared);
  @override
  Future<void> dispose() async => events.close();
}

String publicFixtureKey(String role) =>
    'fixture.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.not-a-signature';
LocalAuthConfig config() => LocalAuthConfig(
  endpoint: Uri.parse('http://127.0.0.1:58321'),
  publicKey: publicFixtureKey('anon'),
);

ProviderContainer setup(FakeAuthRepository repository) => ProviderContainer(
  overrides: [
    authRepositoryProvider.overrideWithValue(repository),
    localAuthConfigProvider.overrideWithValue(config()),
  ],
);
Future<void> show(
  WidgetTester tester,
  ProviderContainer container,
  String route,
) async {
  container.read(appRouterProvider).go(route);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const TwogetheraApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('configuration rejects hosted URLs, secrets, bad ports and disabled environments', () {
    for (final url in [
      'https://example.supabase.co',
      'http://127.0.0.1:59321',
      'http://127.0.0.1:58321?token=x',
      'http://u:p@127.0.0.1:58321',
    ]) {
      expect(
        LocalAuthConfig.parse(
          enabled: true,
          environment: 'development',
          url: url,
          publicKey: publicFixtureKey('anon'),
        ),
        isNull,
      );
    }
    for (final role in ['authenticated', 'service_role']) {
      expect(
        LocalAuthConfig.parse(
          enabled: true,
          environment: 'development',
          url: '',
          publicKey: publicFixtureKey(role),
        ),
        isNull,
      );
    }
    expect(
      LocalAuthConfig.parse(
        enabled: false,
        environment: 'development',
        url: '',
        publicKey: publicFixtureKey('anon'),
      ),
      isNull,
    );
    expect(
      LocalAuthConfig.parse(
        enabled: true,
        environment: 'production',
        url: '',
        publicKey: publicFixtureKey('anon'),
      ),
      isNull,
    );
  });
  test('root local membership API uses the public schema', () {
    final root = LocalAuthConfig.parse(
      enabled: true,
      environment: 'development',
      url: 'http://127.0.0.1:54321',
      publicKey: publicFixtureKey('anon'),
    )!;
    expect(root.dataSchema, 'public');
    final lifecycle = config();
    expect(lifecycle.dataSchema, 'cp004b2');
  });
  test('Android maps to Mac host alias; web and iOS map to loopback', () {
    for (final android in [false, true]) {
      final value = LocalAuthConfig.parse(
        enabled: true,
        environment: 'development',
        url: '',
        publicKey: publicFixtureKey('anon'),
        android: android,
      )!;
      expect(value.endpoint.host, android ? '10.0.2.2' : '127.0.0.1');
      expect(value.toString(), isNot(contains(value.publicKey)));
    }
  });
  test('hosted config requires HTTPS origins and a client-only key', () {
    final publishableKey = 'sb_publishable_${List.filled(40, 'p').join()}';
    final valid = SupabaseRuntimeConfig.parseHosted(
      environment: BackendEnvironment.production,
      url: 'https://project-ref.supabase.co',
      publishableKey: publishableKey,
      webBaseUrl: 'https://beta.twogethera.com',
    );
    expect(valid, isNotNull);
    expect(
      valid!.authCallbackUrl,
      Uri.parse('https://beta.twogethera.com/#/auth/callback'),
    );
    expect(valid.toString(), isNot(contains('sb_publishable_')));
    expect(
      SupabaseRuntimeConfig.parseHosted(
        environment: BackendEnvironment.staging,
        url: 'https://project-ref.supabase.co',
        publishableKey: publicFixtureKey('anon'),
        webBaseUrl: 'https://staging.twogethera.com/',
      ),
      isNotNull,
    );
    for (final invalid in [
      (
        'http://project-ref.supabase.co',
        'https://beta.twogethera.com',
        publishableKey,
      ),
      (
        'https://localhost:54321',
        'https://beta.twogethera.com',
        publishableKey,
      ),
      (
        'https://project-ref.supabase.co/path',
        'https://beta.twogethera.com',
        publishableKey,
      ),
      (
        'https://project-ref.supabase.co',
        'http://beta.twogethera.com',
        publishableKey,
      ),
      (
        'https://project-ref.supabase.co',
        'https://beta.twogethera.com/path',
        publishableKey,
      ),
      (
        'https://project-ref.supabase.co',
        'https://beta.twogethera.com',
        'sb_secret_${List.filled(40, 's').join()}',
      ),
      (
        'https://project-ref.supabase.co',
        'https://beta.twogethera.com',
        publicFixtureKey('service_role'),
      ),
    ]) {
      expect(
        SupabaseRuntimeConfig.parseHosted(
          environment: BackendEnvironment.production,
          url: invalid.$1,
          webBaseUrl: invalid.$2,
          publishableKey: invalid.$3,
        ),
        isNull,
      );
    }
  });
  test('memory storage is per-instance and clears without disk', () async {
    final first = MemoryAuthStorage();
    final second = MemoryAuthStorage();
    await first.setItem(key: 'fixture', value: 'synthetic-value');
    expect(await second.getItem(key: 'fixture'), isNull);
    first.clear();
    expect(await first.getItem(key: 'fixture'), isNull);
  });
  test(
    'injected repository transitions through loading to authorized context',
    () async {
      final repository = FakeAuthRepository();
      final container = setup(repository);
      addTearDown(container.dispose);
      addTearDown(repository.dispose);
      final seen = <AuthPhase>[];
      container.listen(
        authControllerProvider,
        (_, state) => seen.add(state.phase),
        fireImmediately: true,
      );
      await container
          .read(authControllerProvider.notifier)
          .signIn('test@example.invalid', 'fixture');
      expect(seen, [
        AuthPhase.signedOut,
        AuthPhase.loading,
        AuthPhase.authenticated,
      ]);
      expect(repository.logins, 1);
      expect(
        container.read(authControllerProvider).context!.userId,
        'synthetic-user',
      );
    },
  );
  for (final problem in [
    AuthProblem.invalidCredentials,
    AuthProblem.unavailable,
    AuthProblem.denied,
    AuthProblem.expired,
  ]) {
    test(
      'controller handles $problem without retained context or raw error',
      () async {
        final repository = FakeAuthRepository()..failure = problem;
        final container = setup(repository);
        addTearDown(container.dispose);
        addTearDown(repository.dispose);
        await container
            .read(authControllerProvider.notifier)
            .signIn('test@example.invalid', 'fixture');
        final state = container.read(authControllerProvider);
        expect(
          state.phase,
          problem == AuthProblem.expired
              ? AuthPhase.signedOut
              : AuthPhase.error,
        );
        expect(state.context, isNull);
        expect(state.problem, problem);
      },
    );
  }
  test('session expiry invalidates controller context', () async {
    final repository = FakeAuthRepository();
    final container = setup(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await container
        .read(authControllerProvider.notifier)
        .signIn('test@example.invalid', 'fixture');
    repository.events.add(AuthSignal.expired);
    expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
    expect(container.read(authControllerProvider).context, isNull);
  });
  test('late response cannot restore access after local clear', () async {
    final repository = FakeAuthRepository()
      ..pending = Completer<AccountContext>();
    final container = setup(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    final request = container
        .read(authControllerProvider.notifier)
        .signIn('test@example.invalid', 'fixture');
    await Future<void>.delayed(Duration.zero);
    await container.read(authControllerProvider.notifier).clearLocalSession();
    repository.pending!.complete(
      const AccountContext(userId: 'late', spaces: []),
    );
    await request;
    expect(container.read(authControllerProvider).phase, AuthPhase.signedOut);
    expect(container.read(authControllerProvider).context, isNull);
  });
  testWidgets('anonymous protected route redirects to local sign-in', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    final container = setup(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await show(tester, container, '/account');
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/auth/local',
    );
    expect(find.text('Local account verified'), findsNothing);
    container.read(appRouterProvider).go('/planner');
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/auth/local',
    );
    expect(
      container
          .read(appRouterProvider)
          .routeInformationProvider
          .value
          .uri
          .queryParameters['next'],
      '/planner',
    );
  });
  testWidgets(
    'loading stays stable then authenticated route opens; suspension closes it',
    (tester) async {
      final repository = FakeAuthRepository()
        ..pending = Completer<AccountContext>();
      final container = setup(repository);
      addTearDown(container.dispose);
      addTearDown(repository.dispose);
      await show(tester, container, '/auth/local');
      final request = container
          .read(authControllerProvider.notifier)
          .signIn('test@example.invalid', 'fixture');
      await tester.pump();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/auth/local',
      );
      repository.pending!.complete(
        const AccountContext(userId: 'synthetic-user', spaces: []),
      );
      await request;
      await tester.pumpAndSettle();
      expect(find.text('Local account verified'), findsOneWidget);
      repository.failure = AuthProblem.denied;
      await container.read(authControllerProvider.notifier).reloadContext();
      await tester.pumpAndSettle();
      expect(find.text('Local account verified'), findsNothing);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/auth/local',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets('local form fits $width at 200% text with dark theme', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final repository = FakeAuthRepository();
      final container = setup(repository);
      addTearDown(container.dispose);
      addTearDown(repository.dispose);
      await show(tester, container, '/auth/local');
      expect(tester.takeException(), isNull);
      expect(find.text('Sign in locally'), findsOneWidget);
    });
  }
  testWidgets(
    'expiry redirects an authorized account without revealing stale context',
    (tester) async {
      final repository = FakeAuthRepository();
      final container = setup(repository);
      addTearDown(container.dispose);
      addTearDown(repository.dispose);
      await container
          .read(authControllerProvider.notifier)
          .signIn('test@example.invalid', 'fixture');
      await show(tester, container, '/account');
      expect(find.byKey(const ValueKey('account-verified')), findsOneWidget);
      repository.events.add(AuthSignal.expired);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('account-verified')), findsNothing);
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
  for (final dark in [false, true]) {
    testWidgets(
      'local authentication accessibility in ${dark ? "dark" : "light"} mode',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final handle = tester.ensureSemantics();
        final repository = FakeAuthRepository();
        final container = setup(repository);
        addTearDown(container.dispose);
        addTearDown(repository.dispose);
        await show(tester, container, '/auth/local');
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      },
    );
  }
}
