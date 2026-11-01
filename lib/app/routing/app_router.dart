import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/design_studio/presentation/design_studio_screen.dart';
import '../../shared/widgets/adaptive_shell.dart';
import '../../features/authentication/application/auth_controller.dart';
import '../../features/authentication/presentation/local_auth_screen.dart';
import '../../features/authentication/presentation/auth_callback_screen.dart';
import '../../features/partner_linking/presentation/partner_linking_screen.dart';
import '../../features/shared_planner/presentation/shared_planner_screen.dart';
import '../../shared/widgets/responsive_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, route) {
      if (!kDebugMode) return null;
      if (route.uri.path == '/auth/callback') return null;
      final phase = ref.read(authControllerProvider).phase;
      final authenticated = phase == AuthPhase.authenticated;
      if (phase == AuthPhase.recovering &&
          (route.uri.path == '/account' || route.uri.path == '/auth/local')) {
        return '/auth/recovery';
      }
      if (route.uri.path == '/account' && !authenticated) return '/auth/local';
      if (route.uri.path == '/partner' && !authenticated) {
        return '/auth/local?next=%2Fpartner';
      }
      if (route.uri.path == '/planner' && !authenticated) {
        return '/auth/local?next=%2Fplanner';
      }
      if (route.uri.path.startsWith('/auth/') && authenticated) {
        if (route.uri.queryParameters['next'] == '/partner') return '/partner';
        if (route.uri.queryParameters['next'] == '/planner') return '/planner';
        return '/account';
      }
      return null;
    },
    routes: [
      if (kDebugMode) ...[
        GoRoute(
          path: '/auth/welcome',
          builder: (context, state) => const AuthWelcomeScreen(),
        ),
        GoRoute(
          path: '/auth/callback',
          builder: (context, state) => AuthCallbackScreen(uri: state.uri),
        ),
        GoRoute(
          path: '/auth/register',
          builder: (context, state) =>
              const LocalLifecycleScreen(registration: true),
        ),
        GoRoute(
          path: '/auth/verify',
          builder: (context, state) => const LocalLifecycleScreen(),
        ),
        GoRoute(
          path: '/auth/recovery',
          builder: (context, state) =>
              const LocalLifecycleScreen(recovery: true),
        ),
        GoRoute(
          path: '/auth/local',
          builder: (context, state) => LocalAuthScreen(
            nextRoute: switch (state.uri.queryParameters['next']) {
              '/partner' => '/partner',
              '/planner' => '/planner',
              _ => null,
            },
          ),
        ),
        GoRoute(
          path: '/account',
          builder: (context, state) => const LocalAccountScreen(),
        ),
        GoRoute(
          path: '/partner',
          builder: (context, state) => const PartnerLinkingScreen(),
        ),
        GoRoute(
          path: '/planner',
          builder: (context, state) => const SharedPlannerScreen(),
        ),
      ],
      ShellRoute(
        builder: (context, state, child) =>
            AdaptiveShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/studio',
            builder: (context, state) => const DesignStudioScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Twogethera')),
      body: ResponsivePage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const Text('This address is not available.'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
