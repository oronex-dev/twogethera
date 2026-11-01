import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:http/http.dart' as http;
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/app/twogethera_app.dart';
import 'package:twogethera/core/config/local_auth_config.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/data/local_auth_clients.dart';
import 'package:twogethera/features/authentication/data/supabase_auth_repository.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';

import 'browser_storage.dart';

/// Observes real HTTP without replacing responses or printing body values.
class ExperienceWire extends http.BaseClient {
  ExperienceWire(this.fixture);
  final Map<String, dynamic> fixture;
  final _client = http.Client();
  final trace = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path.split('/').last;
    if ((path == 'token' || path == 'recover') && request is http.Request) {
      final body = jsonDecode(request.body) as Map;
      final email = body['email'];
      final category = email == fixture['email']
          ? 'main'
          : email == fixture['resetEmail']
          ? 'reset'
          : email == fixture['unknownEmail']
          ? 'unknown'
          : 'other';
      final password = body['password'];
      trace.add(
        '$path:$category:passwordMatchesFixture=${password == fixture['password'] || password == fixture['newPassword']}',
      );
    }
    final response = await _client.send(request);
    trace.add('$path:HTTP${response.statusCode}');
    return response;
  }

  @override
  void close() => _client.close();
}

/// Genuine local Auth + PostgREST via the user-facing forms. The nonce-protected
/// host broker only reads this run's synthetic mailbox and sets fixed test gates.
void registerAuthExperienceTests() {
  final f = jsonDecode(
    const String.fromEnvironment('CP005A_FIXTURE'),
  ) as Map<String, dynamic>;
  Future<dynamic> control(String action, [Map<String, dynamic>? body]) async {
    final client = FunctionsClient('${f['control']}/functions/v1', {
      'X-Local-Proof': f['nonce'] as String,
    });
    try {
      final result = await client.invoke(action, body: body);
      expect(result.status, 200);
      return result.data;
    } finally {
      await client.dispose();
    }
  }

  Future<String> mail(String kind) async =>
      (await control('mail', {'kind': kind}) as Map)['link'] as String;
  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> enter(WidgetTester t, String name, String value) async {
    await t.ensureVisible(key(name));
    await t.pumpAndSettle();
    await t.enterText(key(name), value);
    await t.pumpAndSettle();
    expect(
      t.widget<TextFormField>(key(name)).controller!.text == value,
      isTrue,
      reason:
          'Native field value must match supplied fixture; values suppressed',
    );
  }

  Future<void> tap(WidgetTester t, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await t.ensureVisible(find.text(label));
    await t.pumpAndSettle();
    await t.runAsync(() => t.tap(find.text(label)));
    await t.pump();
  }

  Future<void> settled(WidgetTester t, ProviderContainer c) async {
    await t.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 18));
      while ({
            AuthPhase.loading,
            AuthPhase.refreshing,
          }.contains(c.read(authControllerProvider).phase) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await t.pumpAndSettle();
    debugPrint(
      'UX state: ${c.read(authControllerProvider).phase.name}; problem: ${c.read(authControllerProvider).problem?.name ?? "none"}',
    );
    expect(
      {
        AuthPhase.loading,
        AuthPhase.refreshing,
      }.contains(c.read(authControllerProvider).phase),
      isFalse,
    );
  }

  ({
    ProviderContainer c,
    SupabaseAuthRepository repo,
    LocalAuthClients Function() clients,
  })
  setup() {
    LocalAuthClients? active;
    final wires = <ExperienceWire>[];
    final repo = SupabaseAuthRepository(
      createClients: () {
        final wire = ExperienceWire(f);
        wires.add(wire);
        return active = LocalAuthClients(
          url: f['url'] as String,
          publicKey: f['key'] as String,
          authClient: GoTrueClient(
            url: '${f['url']}/auth/v1',
            headers: {'apikey': f['key'] as String},
            autoRefreshToken: false,
            asyncStorage: MemoryAuthStorage(),
            httpClient: wire,
          ),
        );
      },
    );
    final c = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        localAuthConfigProvider.overrideWithValue(
          LocalAuthConfig(
            endpoint: Uri.parse(f['url'] as String),
            publicKey: f['key'] as String,
          ),
        ),
      ],
    );
    addTearDown(() {
      for (final wire in wires) {
        debugPrint('UX genuine HTTP trace (no values): ${wire.trace}');
        wire.close();
      }
    });
    return (c: c, repo: repo, clients: () => active!);
  }

  Future<void> mount(WidgetTester t, ProviderContainer c, String route) async {
    c.read(appRouterProvider).go(route);
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const TwogetheraApp()),
    );
    await t.pumpAndSettle();
  }

  Future<void> audit(WidgetTester t, LocalAuthClients clients) async {
    if (f['native'] == true) {
      await t.runAsync(
        () => control('audit', {
          'accessToken': clients.acceptedSession!.accessToken,
          'refreshToken': clients.acceptedSession!.refreshToken!,
        }),
      );
    }
  }

  Future<void> close(
    WidgetTester t,
    ProviderContainer c,
    SupabaseAuthRepository repo,
  ) async {
    await t.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await t.runAsync(repo.dispose);
  }

  testWidgets(
    'REAL UX: sign-in, safe invalid credentials, authorized profile, suspension and sign-out',
    (t) async {
      final s = setup();
      final before = await t.runAsync(persistenceSnapshot);
      try {
        await mount(t, s.c, '/account');
        expect(key('account-verified'), findsNothing);
        await enter(t, 'auth-email', f['email'] as String);
        await enter(t, 'auth-password', 'invalid synthetic password');
        await tap(t, 'Sign in locally');
        await settled(t, s.c);
        expect(
          s.c.read(authControllerProvider).problem,
          AuthProblem.invalidCredentials,
        );
        await enter(t, 'auth-password', f['password'] as String);
        await tap(t, 'Sign in locally');
        await settled(t, s.c);
        expect(key('account-verified'), findsOneWidget);
        expect(
          s.c.read(authControllerProvider).context!.userId == f['userId'],
          isTrue,
        );
        expect(find.text(f['email'] as String), findsOneWidget);
        await audit(t, s.clients());
        await t.runAsync(() => control('suspend'));
        await tap(t, 'Check server access');
        await settled(t, s.c);
        expect(key('account-verified'), findsNothing);
        expect(s.c.read(authControllerProvider).suspended, isTrue);
        await t.runAsync(() async {
          await control('restore');
          await s.c.read(authControllerProvider.notifier).reloadContext();
        });
        await t.pumpAndSettle();
        expect(key('account-verified'), findsOneWidget);
        await tap(t, 'Sign out');
        await settled(t, s.c);
        expect(key('account-verified'), findsNothing);
        expect(s.c.read(authControllerProvider).context, isNull);
        expect(
          await t.runAsync(persistenceSnapshot) == before,
          isTrue,
          reason: 'Browser storage unchanged; values suppressed',
        );
      } finally {
        await close(t, s.c, s.repo);
      }
    },
  );

  testWidgets(
    'REAL UX: named registration, genuine resend, scrubbed confirmation callback and profile',
    (t) async {
      final s = setup();
      try {
        await mount(t, s.c, '/auth/register');
        await enter(t, 'auth-display-name', 'River');
        await enter(t, 'lifecycle-email', f['signupEmail'] as String);
        await enter(t, 'lifecycle-password', f['password'] as String);
        await enter(t, 'auth-confirm-password', f['password'] as String);
        await tap(t, 'Create account');
        await settled(t, s.c);
        expect(
          s.c.read(authControllerProvider).phase,
          AuthPhase.awaitingConfirmation,
        );
        expect(
          s.c.read(appRouterProvider).routeInformationProvider.value.uri.path,
          '/auth/verify',
        );
        final first = await t.runAsync(() => mail('signup'));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2100)),
        );
        await enter(t, 'lifecycle-email', f['signupEmail'] as String);
        await tap(t, 'Resend confirmation');
        await settled(t, s.c);
        expect(
          s.c.read(authControllerProvider).notice,
          contains('If the address is eligible'),
        );
        final link = (await t.runAsync(() => mail('signup')))!;
        expect(
          link != first,
          isTrue,
          reason: 'New genuine mailbox message required',
        );
        final uri = Uri.parse(link);
        final hash =
            uri.queryParameters['token'] ?? uri.queryParameters['token_hash'];
        debugPrint(
          'Genuine link hash shape accepted: ${hash != null && RegExp(r"^(?:pkce_)?[a-fA-F0-9]{40,128}$").hasMatch(hash)}',
        );
        // Test router ingress and browser replacement, not OS mail association.
        s.c
            .read(appRouterProvider)
            .go(
              Uri(
                path: '/auth/callback',
                queryParameters: {'token_hash': hash!, 'type': 'signup'},
              ).toString(),
            );
        await t.runAsync(() => t.pump());
        await t.runAsync(() => t.pump());
        await settled(t, s.c);
        expect(s.c.read(authControllerProvider).phase, AuthPhase.authenticated);
        expect(
          locationOmits(hash),
          isTrue,
          reason: 'Callback token must be absent from current browser location',
        );
        expect(
          s.c
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .hasQuery,
          isFalse,
        );
        expect(find.text('River'), findsOneWidget);
        await audit(t, s.clients());
        await tap(t, 'Sign out');
        await settled(t, s.c);
      } finally {
        await close(t, s.c, s.repo);
      }
    },
  );

  testWidgets(
    'REAL UX: generic recovery, genuine callback, matching new passwords and fresh sign-in',
    (t) async {
      final s = setup();
      final before = await t.runAsync(persistenceSnapshot);
      try {
        await mount(t, s.c, '/auth/recovery');
        await enter(t, 'lifecycle-email', f['unknownEmail'] as String);
        await tap(t, 'Send recovery email');
        await settled(t, s.c);
        final notice = s.c.read(authControllerProvider).notice;
        await enter(t, 'lifecycle-email', f['resetEmail'] as String);
        await tap(t, 'Send recovery email');
        await settled(t, s.c);
        expect(s.c.read(authControllerProvider).notice, notice);
        final link = (await t.runAsync(() => mail('recovery')))!;
        final uri = Uri.parse(link);
        final hash =
            uri.queryParameters['token'] ?? uri.queryParameters['token_hash'];
        s.c
            .read(appRouterProvider)
            .go(
              Uri(
                path: '/auth/callback',
                queryParameters: {'token_hash': hash!, 'type': 'recovery'},
              ).toString(),
            );
        await t.runAsync(() => t.pump());
        await t.runAsync(() => t.pump());
        await settled(t, s.c);
        expect(s.c.read(authControllerProvider).phase, AuthPhase.recovering);
        expect(locationOmits(hash), isTrue);
        expect(key('account-verified'), findsNothing);
        await audit(t, s.clients());
        await enter(t, 'lifecycle-password', f['newPassword'] as String);
        await enter(t, 'auth-confirm-password', f['newPassword'] as String);
        await tap(t, 'Update password');
        await settled(t, s.c);
        expect(s.c.read(authControllerProvider).phase, AuthPhase.signedOut);
        expect(
          s.c.read(authControllerProvider).notice,
          contains('Password changed'),
        );
        await tap(t, 'Return to sign-in');
        await t.pumpAndSettle();
        await enter(t, 'auth-email', f['resetEmail'] as String);
        await enter(t, 'auth-password', f['newPassword'] as String);
        await tap(t, 'Sign in locally');
        await settled(t, s.c);
        expect(key('account-verified'), findsOneWidget);
        await tap(t, 'Sign out');
        await settled(t, s.c);
        expect(
          await t.runAsync(persistenceSnapshot) == before,
          isTrue,
          reason: 'Recovery leaves browser persistence unchanged',
        );
      } finally {
        await close(t, s.c, s.repo);
      }
    },
  );

  testWidgets(
    'REAL UX: expired confirmation and malformed mailbox links show safe retry guidance',
    (t) async {
      final s = setup();
      try {
        await t.runAsync(
          () => s.repo.registerProfile(
            f['expiredEmail'] as String,
            f['password'] as String,
            'Sky',
          ),
        );
        final link = (await t.runAsync(() => mail('expired')))!;
        await t.runAsync(() => control('expire-signup'));
        await mount(t, s.c, '/auth/verify');
        await enter(t, 'lifecycle-link', link);
        await tap(t, 'Verify confirmation link');
        await settled(t, s.c);
        expect(
          s.c.read(authControllerProvider).problem,
          AuthProblem.invalidLink,
        );
        expect(
          find.text(const AuthFailure(AuthProblem.invalidLink).message),
          findsOneWidget,
        );
        await enter(
          t,
          'lifecycle-link',
          'https://example.invalid/not-a-local-link',
        );
        await tap(t, 'Verify confirmation link');
        await settled(t, s.c);
        expect(
          s.c.read(authControllerProvider).problem,
          AuthProblem.invalidLink,
        );
        expect(s.c.read(authControllerProvider).context, isNull);
      } finally {
        await close(t, s.c, s.repo);
      }
    },
  );
}
