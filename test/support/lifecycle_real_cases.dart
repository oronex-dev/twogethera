import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/app/twogethera_app.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/data/local_auth_clients.dart';
import 'package:twogethera/features/authentication/data/supabase_auth_repository.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';

import 'browser_storage.dart';

/// Transport instrumentation forwards genuine HTTP bytes. It never invents an
/// Auth response: interruption connects to an unused local port; delayed tests
/// buffer an actual completed Auth response until after server logout.
class WireGate {
  bool offlineRefresh = false;
  bool offlineLogout = false;
  String? holdGrant;
  int refreshes = 0;
  final statuses = <String>[];
  final started = Completer<void>();
  final release = Completer<void>();
  Map<String, dynamic>? actualResponse;
}

class RealWire extends http.BaseClient {
  RealWire(this.gate);
  final WireGate gate;
  final _delegate = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final grant = request.url.queryParameters['grant_type'];
    if (grant == 'refresh_token') gate.refreshes++;
    if ((gate.offlineRefresh && grant == 'refresh_token') ||
        (gate.offlineLogout && request.url.path.endsWith('/logout'))) {
      final bytes = await request.finalize().toBytes();
      final failed =
          http.Request(
              request.method,
              request.url.replace(host: '127.0.0.1', port: 1),
            )
            ..headers.addAll(request.headers)
            ..bodyBytes = bytes;
      return _delegate.send(failed);
    }
    final response = await _delegate.send(request);
    gate.statuses.add(
      '${request.url.path.split('/').last}:${grant ?? '-'}:${response.statusCode}',
    );
    if (gate.holdGrant != null && grant == gate.holdGrant) {
      final bytes = await response.stream.toBytes();
      gate.actualResponse =
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (!gate.started.isCompleted) gate.started.complete();
      await gate.release.future.timeout(const Duration(seconds: 6));
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        headers: response.headers,
        request: response.request,
      );
    }
    return response;
  }

  @override
  void close() => _delegate.close();
}

void registerLifecycleTests() {
  final f = jsonDecode(
    const String.fromEnvironment('CP005A_FIXTURE'),
  ) as Map<String, dynamic>;
  GoTrueClient auth() => GoTrueClient(
    url: '${f['url']}/auth/v1',
    headers: {'apikey': f['key'] as String},
    autoRefreshToken: false,
    asyncStorage: MemoryAuthStorage(),
  );
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
      ((await control('mail', {'kind': kind})) as Map)['link'] as String;
  Future<void> auditSession(LocalAuthClients clients) async {
    if (f['native'] != true) return;
    final session = clients.acceptedSession!;
    // Nonce-protected host controller keeps these exact live values only in RAM.
    await control('audit', {
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken!,
    });
  }

  Future<void> failure(Future<void> action, AuthProblem problem) async {
    AuthProblem? actual;
    try {
      await action;
    } on AuthFailure catch (error) {
      actual = error.problem;
    }
    expect(
      actual == problem,
      isTrue,
      reason: 'Expected sanitized lifecycle failure category: ${problem.name}',
    );
  }

  Future<bool> refreshDenied(String token) async {
    final client = auth();
    try {
      await client.refreshSession(token);
      return false;
    } on AuthException catch (error) {
      // An unavailable Auth service is not proof of credential revocation.
      if (error is AuthApiException &&
          {'400', '401'}.contains(error.statusCode)) {
        debugPrint(
          'Revoked refresh rejected by Auth HTTP ${error.statusCode}.',
        );
        return true;
      }
      rethrow;
    } finally {
      client.dispose();
    }
  }

  Future<void> jwtStillAccepted(String token, String uid) async {
    final client = SupabaseClient(
      f['url'] as String,
      f['key'] as String,
      accessToken: () async => token,
      postgrestOptions: const PostgrestClientOptions(
        schema: 'cp004b2',
        retryEnabled: false,
      ),
    );
    try {
      final result = await client.rpc('account_context');
      expect(result is Map && result['user_id'] == uid, isTrue);
    } finally {
      await client.dispose();
    }
  }

  ({
    SupabaseAuthRepository repo,
    LocalAuthClients Function() current,
    List<RealWire> wires,
  })
  setup([WireGate? gate]) {
    LocalAuthClients? active;
    final wires = <RealWire>[];
    final repo = SupabaseAuthRepository(
      createClients: () {
        GoTrueClient? sdk;
        if (gate != null) {
          final wire = RealWire(gate);
          wires.add(wire);
          sdk = GoTrueClient(
            url: '${f['url']}/auth/v1',
            headers: {'apikey': f['key'] as String},
            autoRefreshToken: false,
            asyncStorage: MemoryAuthStorage(),
            httpClient: wire,
          );
        }
        return active = LocalAuthClients(
          url: f['url'] as String,
          publicKey: f['key'] as String,
          authClient: sdk,
        );
      },
    );
    addTearDown(() async {
      await repo.dispose();
      for (final wire in wires) {
        wire.close();
      }
    });
    return (repo: repo, current: () => active!, wires: wires);
  }

  Future<void> login(SupabaseAuthRepository repo) async =>
      repo.signIn(f['email'] as String, f['password'] as String);

  test(
    'REAL lifecycle: rotating single-flight refresh and current-session logout',
    () async {
      final s = setup(WireGate());
      final gate = s.wires;
      await login(s.repo);
      await s.repo.accountContext();
      final before = s.current().acceptedSession!.refreshToken!;
      final a = s.repo.refreshSession(), b = s.repo.refreshSession();
      expect(identical(a, b), isTrue);
      await Future.wait([a, b]);
      expect(gate.first.gate.refreshes, 1);
      final accepted = s.current().acceptedSession!;
      await auditSession(s.current());
      expect(
        accepted.refreshToken != before,
        isTrue,
        reason: 'Real Auth must rotate the refresh credential',
      );
      final peer = auth();
      final sameAccount = auth();
      try {
        final otherDevice = await sameAccount.signInWithPassword(
          email: f['email'] as String,
          password: f['password'] as String,
        );
        final otherDeviceRefresh = otherDevice.session!.refreshToken!;
        final peerResponse = await peer.signInWithPassword(
          email: f['resetEmail'] as String,
          password: f['password'] as String,
        );
        final peerRefresh = peerResponse.session!.refreshToken!;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final context = await s.repo.accountContext();
        expect(context.userId, f['userId']);
        await s.repo.signOut();
        await failure(
          s.repo.accountContext().then((_) {}),
          AuthProblem.expired,
        );
        expect(await refreshDenied(accepted.refreshToken!), isTrue);
        expect(
          (await sameAccount.refreshSession(otherDeviceRefresh)).session !=
              null,
          isTrue,
          reason: 'Current-session logout must preserve a second device session for the same account',
        );
        final other = await peer.refreshSession(peerRefresh);
        expect(
          other.session?.user.id == peerResponse.user!.id,
          isTrue,
          reason: 'Local logout must not revoke another account/session',
        );
        await jwtStillAccepted(accepted.accessToken, context.userId);
      } finally {
        peer.dispose();
        sameAccount.dispose();
      }
    },
  );

  testWidgets(
    'REAL lifecycle: refresh observes suspension and protected-route denial',
    (tester) async {
      final s = setup();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(s.repo)],
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TwogetheraApp(),
          ),
        );
        await tester.runAsync(
          () => container
              .read(authControllerProvider.notifier)
              .signIn(f['email'] as String, f['password'] as String),
        );
        await tester.pumpAndSettle();
        container.read(appRouterProvider).go('/account');
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await control('suspend');
          await container
              .read(authControllerProvider.notifier)
              .refreshSession();
        });
        await tester.pumpAndSettle();
        expect(container.read(authControllerProvider).suspended, isTrue);
        expect(container.read(authControllerProvider).context, isNull);
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
          await control('restore');
          await container.read(authControllerProvider.notifier).reloadContext();
        });
        await tester.pumpAndSettle();
        expect(
          container.read(authControllerProvider).phase,
          AuthPhase.authenticated,
        );
        await tester.runAsync(
          () => container.read(authControllerProvider.notifier).signOut(),
        );
        await tester.pumpAndSettle();
        expect(container.read(authControllerProvider).context, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      }
    },
  );

  test(
    'REAL lifecycle: network interruption versus invalid refresh credentials',
    () async {
      final gate = WireGate();
      final s = setup(gate);
      await login(s.repo);
      gate.offlineRefresh = true;
      await failure(s.repo.refreshSession(), AuthProblem.unavailable);
      await failure(s.repo.accountContext().then((_) {}), AuthProblem.expired);
      gate.offlineRefresh = false;
      await login(s.repo);
      final session = s.current().acceptedSession!;
      s.current().acceptSession(
        Session.fromJson({
          ...session.toJson(),
          'refresh_token': 'invalid-local-negative-credential',
        })!,
      );
      await failure(s.repo.refreshSession(), AuthProblem.expired);
      await failure(s.repo.accountContext().then((_) {}), AuthProblem.expired);
    },
  );

  test('REAL lifecycle: offline logout clears RAM but cannot claim server revocation', () async {
    final gate = WireGate();
    final s = setup(gate);
    await login(s.repo);
    final refresh = s.current().acceptedSession!.refreshToken!;
    gate.offlineLogout = true;
    await failure(s.repo.signOut(), AuthProblem.unavailable);
    await failure(s.repo.accountContext().then((_) {}), AuthProblem.expired);
    final probe = auth();
    try {
      final response = await probe.refreshSession(refresh);
      expect(
        response.session != null,
        isTrue,
        reason:
            'An unreachable logout endpoint cannot revoke server credentials',
      );
      await probe.admin.signOut(
        response.session!.accessToken,
        scope: SignOutScope.local,
      );
    } finally {
      probe.dispose();
    }
  });

  test('REAL lifecycle: delayed genuine refresh response after logout cannot restore authority', () async {
    final gate = WireGate()..holdGrant = 'refresh_token';
    final s = setup(gate);
    await login(s.repo);
    final pending = s.repo.refreshSession().then(
      (_) => false,
      onError: (_) => true,
    );
    await gate.started.future.timeout(const Duration(seconds: 5));
    await s.repo.signOut();
    gate.release.complete();
    expect(await pending, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await failure(s.repo.accountContext().then((_) {}), AuthProblem.expired);
    expect(
      await refreshDenied(gate.actualResponse!['refresh_token'] as String),
      isTrue,
      reason: 'Server logout must revoke the genuinely rotated session family',
    );
  });

  test('REAL lifecycle: delayed password sign-in after local logout remains unauthenticated', () async {
    final gate = WireGate()..holdGrant = 'password';
    final s = setup(gate);
    final pending = login(s.repo).then((_) => false, onError: (_) => true);
    await gate.started.future.timeout(const Duration(seconds: 5));
    await s.repo.signOut();
    gate.release.complete();
    expect(await pending, isTrue);
    await failure(s.repo.accountContext().then((_) {}), AuthProblem.expired);
    // Retire only this test's late issued Auth session, never another user.
    final client = auth();
    try {
      await client.admin.signOut(
        gate.actualResponse!['access_token'] as String,
        scope: SignOutScope.local,
      );
    } finally {
      client.dispose();
    }
  });

  test('REAL lifecycle: signup, captured confirmation, single-use verification and authenticated context', () async {
    final before = await persistenceSnapshot();
    final s = setup();
    await s.repo.register(f['signupEmail'] as String, f['password'] as String);
    await failure(s.repo.accountContext().then((_) {}), AuthProblem.expired);
    await failure(
      s.repo.signIn(f['signupEmail'] as String, f['password'] as String),
      AuthProblem.emailUnconfirmed,
    );
    final link = await mail('signup');
    await s.repo.verifyLink(link, recovery: false);
    final context = await s.repo.accountContext();
    expect(context.userId == s.current().acceptedSession!.user.id, isTrue);
    await auditSession(s.current());
    await failure(
      s.repo.verifyLink(link, recovery: false),
      AuthProblem.invalidLink,
    );
    await failure(s.repo.accountContext().then((_) {}), AuthProblem.expired);
    expect(
      await persistenceSnapshot() == before,
      isTrue,
      reason: 'Email flow must not alter browser persistence',
    );
  });

  test(
    'REAL lifecycle: genuine expired confirmation and invalid link rejected',
    () async {
      final s = setup();
      await s.repo.register(
        f['expiredEmail'] as String,
        f['password'] as String,
      );
      final link = await mail('expired');
      await control('expire-signup');
      await failure(
        s.repo.verifyLink(link, recovery: false),
        AuthProblem.invalidLink,
      );
      final invalid = Uri.parse(link)
          .replace(
            queryParameters: {
              'token': 'invalid-negative-link',
              'type': 'signup',
            },
          )
          .toString();
      await failure(
        s.repo.verifyLink(invalid, recovery: false),
        AuthProblem.invalidLink,
      );
    },
  );

  test('REAL lifecycle: generic recovery, pinned password change, global refresh revocation and fresh sign-in', () async {
    final before = await persistenceSnapshot();
    final s = setup();
    await s.repo.signIn(f['resetEmail'] as String, f['password'] as String);
    final old = s.current().acceptedSession!;
    await s.repo.accountContext();
    await s.repo.requestRecovery(f['unknownEmail'] as String);
    await s.repo.requestRecovery(f['resetEmail'] as String);
    final link = await mail('recovery');
    await s.repo.verifyLink(link, recovery: true);
    await failure(
      s.repo.accountContext().then((_) {}),
      AuthProblem.recoveryRequired,
    );
    await auditSession(s.current());
    // A peer's SDK broadcast must not redirect the password update to that user.
    final peer = auth();
    try {
      await peer.signInWithPassword(
        email: f['email'] as String,
        password: f['password'] as String,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await s.repo.updatePassword(f['newPassword'] as String);
    } finally {
      peer.dispose();
    }
    await failure(s.repo.accountContext().then((_) {}), AuthProblem.expired);
    expect(await refreshDenied(old.refreshToken!), isTrue);
    await jwtStillAccepted(old.accessToken, old.user.id);
    await failure(
      s.repo.signIn(f['resetEmail'] as String, f['password'] as String),
      AuthProblem.invalidCredentials,
    );
    await s.repo.signIn(f['resetEmail'] as String, f['newPassword'] as String);
    expect((await s.repo.accountContext()).userId == old.user.id, isTrue);
    final main = auth();
    try {
      expect(
        (await main.signInWithPassword(
              email: f['email'] as String,
              password: f['password'] as String,
            )).session !=
            null,
        isTrue,
      );
    } finally {
      main.dispose();
    }
    await s.repo.signOut();
    expect(
      await persistenceSnapshot() == before,
      isTrue,
      reason: 'Recovery must not write browser storage',
    );
  });

  test(
    'REAL lifecycle: expired and invalid genuine recovery links fail closed',
    () async {
      final s = setup();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await s.repo.requestRecovery(f['resetEmail'] as String);
      final link = await mail('recovery');
      await control('expire-recovery');
      await failure(
        s.repo.verifyLink(link, recovery: true),
        AuthProblem.invalidLink,
      );
      final invalid = Uri.parse(link)
          .replace(
            queryParameters: {
              'token': 'invalid-negative-link',
              'type': 'recovery',
            },
          )
          .toString();
      await failure(
        s.repo.verifyLink(invalid, recovery: true),
        AuthProblem.invalidLink,
      );
      await failure(s.repo.accountContext().then((_) {}), AuthProblem.expired);
    },
  );

  test('REAL lifecycle: stale failed sign-in cannot clear a newer authenticated session', () async {
    final gate = WireGate()..holdGrant = 'password';
    final s = setup(gate);
    final stale = failure(
      s.repo.signIn(f['email'] as String, 'deliberately-invalid-test-password'),
      AuthProblem.expired,
    );
    await gate.started.future;
    await s.repo.signOut();
    gate.holdGrant = null;
    await login(s.repo);
    final uid = (await s.repo.accountContext()).userId;
    gate.release.complete();
    await stale;
    expect((await s.repo.accountContext()).userId == uid, isTrue);
    await s.repo.signOut();
  });

  test('REAL lifecycle: expired access permits explicit refresh and expired-access logout revokes refresh', () async {
    LocalAuthClients? shortClients;
    final gate = WireGate();
    final wire = RealWire(gate);
    final repo = SupabaseAuthRepository(
      createClients: () => shortClients = LocalAuthClients(
        url: f['expiryUrl'] as String,
        publicKey: f['expiryKey'] as String,
        authClient: GoTrueClient(
          url: '${f['expiryUrl']}/auth/v1',
          headers: {'apikey': f['expiryKey'] as String},
          autoRefreshToken: false,
          asyncStorage: MemoryAuthStorage(),
          httpClient: wire,
        ),
      ),
    );
    try {
      await repo.signIn(
        f['expiryEmail'] as String,
        f['expiryPassword'] as String,
      );
      Future<void> expire() async {
        final expiry = shortClients!.acceptedSession!.expiresAt!;
        final duration =
            DateTime.fromMillisecondsSinceEpoch(expiry * 1000)
                .difference(DateTime.now()) +
            const Duration(milliseconds: 200);
        await Future<void>.delayed(
          duration.isNegative ? Duration.zero : duration,
        );
        await failure(repo.accountContext().then((_) {}), AuthProblem.expired);
        expect(shortClients!.acceptedSession!.isExpired, isTrue);
      }

      await expire();
      await repo.refreshSession();
      expect(
        gate.statuses.where((s) => s == 'token:refresh_token:200').length,
        1,
      );
      expect(shortClients!.validSession().user.id.isNotEmpty, isTrue);
      final refresh = shortClients!.acceptedSession!.refreshToken!;
      await expire();
      await repo.signOut();
      expect(
        gate.statuses.where((s) => s == 'token:refresh_token:200').length,
        2,
      );
      expect(gate.statuses.contains('token:refresh_token:400'), isFalse);
      final probe = GoTrueClient(
        url: '${f['expiryUrl']}/auth/v1',
        headers: {'apikey': f['expiryKey'] as String},
        autoRefreshToken: false,
        asyncStorage: MemoryAuthStorage(),
      );
      try {
        var denied = false;
        try {
          await probe.refreshSession(refresh);
        } on AuthException catch (error) {
          denied =
              error is AuthApiException &&
              {'400', '401'}.contains(error.statusCode);
          if (denied) {
            debugPrint(
              'Expired-logout refresh rejected by Auth HTTP ${error.statusCode}.',
            );
          }
        }
        expect(denied, isTrue);
      } finally {
        probe.dispose();
      }
    } finally {
      debugPrint(
        'Short-lived Auth status trace (no credentials): ${gate.statuses}',
      );
      await repo.dispose();
      wire.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
