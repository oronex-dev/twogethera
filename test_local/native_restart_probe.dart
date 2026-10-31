// Local debug-only runtime probe. Never used by lib/main.dart or release builds.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/app/twogethera_app.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/data/local_auth_clients.dart';
import 'package:twogethera/features/authentication/data/supabase_auth_repository.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';

Future<void> main() async {
  if (!kDebugMode || kIsWeb) {
    throw StateError('Native local debug probe only');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    const String.fromEnvironment('CP005A_FIXTURE'),
  ) as Map<String, dynamic>;
  final broker = FunctionsClient('${fixture['control']}/functions/v1', {
    'X-Local-Proof': fixture['nonce'] as String,
  });
  Future<dynamic> send(String action, [Map<String, dynamic>? body]) async {
    final response = await broker.invoke(action, body: body);
    if (response.status != 200) throw StateError('Local probe broker denied');
    final data = response.data;
    return data is String ? jsonDecode(data) : data;
  }

  // Each actual OS process creates a new repository and an empty SDK RAM store.
  final clients = LocalAuthClients(
    url: fixture['url'] as String,
    publicKey: fixture['key'] as String,
  );
  final repository = SupabaseAuthRepository(createClients: () => clients);
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TwogetheraApp(),
    ),
  );
  try {
    final phase = (await send('restart-phase') as Map)['phase'];
    final controller = container.read(authControllerProvider.notifier);
    final router = container.read(appRouterProvider);
    if (phase == 'first') {
      await controller.signIn(
        fixture['email'] as String,
        fixture['password'] as String,
      );
      final state = container.read(authControllerProvider);
      if (state.phase != AuthPhase.authenticated ||
          state.context?.userId != fixture['userId']) {
        throw StateError('Local probe sign-in/context failed');
      }
      router.go('/account');
      await WidgetsBinding.instance.endOfFrame;
      final session = clients.validSession();
      // Tokens travel only to the nonce-protected loopback test controller RAM
      // for exact storage scanning; never printed or written to a result file.
      await send('restart-ready', {
        'userId': state.context!.userId,
        'protected':
            router.routeInformationProvider.value.uri.path == '/account',
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken,
      });
      // Deliberately do NOT clear/dispose/sign out. The host kills this process
      // while the real session is valid, preserving the application data folder.
    } else if (phase == 'second') {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (container.read(authControllerProvider).phase != AuthPhase.signedOut) {
        throw StateError('Unexpected automatic authentication on relaunch');
      }
      router.go('/account');
      await WidgetsBinding.instance.endOfFrame;
      var denied = false;
      try {
        await repository.accountContext();
      } on AuthFailure catch (error) {
        denied = error.problem == AuthProblem.expired;
      }
      await send('restart-result', {
        'passed':
            denied &&
            container.read(authControllerProvider).context == null &&
            router.routeInformationProvider.value.uri.path == '/auth/local',
      });
    } else {
      throw StateError('Unexpected local probe phase');
    }
  } catch (_) {
    // Do not surface raw SDK errors, credentials or Session objects.
    await send('restart-result', {'passed': false});
  }
}
