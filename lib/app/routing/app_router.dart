import 'package:flutter/material.dart';
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
import '../../features/shared_planner/presentation/global_search_screen.dart';
import '../../features/budget/presentation/budget_screen.dart';
import '../../features/memories/presentation/memories_screen.dart';
import '../../shared/widgets/responsive_page.dart';

String? _safeNextRoute(String? value) {
  if (value == null || value.isEmpty || value.length > 512) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasAuthority || uri.hasFragment || uri.path.isEmpty) {
    return null;
  }
  if (uri.path == '/partner' ||
      uri.path == '/account' ||
      uri.path == '/budget' ||
      uri.path == '/memories' ||
      uri.path == '/') {
    return uri.path;
  }
  if (uri.path == '/search') return '/search';
  if (uri.path != '/planner') return null;

  final allowed = {'tab', 'type', 'item', 'create', 'request'};
  if (uri.queryParameters.keys.any((key) => !allowed.contains(key))) {
    return '/planner';
  }
  final tab = uri.queryParameters['tab'];
  if (tab != null && !{'0', '1', '2'}.contains(tab)) return '/planner';
  final type = uri.queryParameters['type'];
  final item = uri.queryParameters['item'];
  if ((type == null) != (item == null) ||
      (type != null && !{'bucket', 'date', 'plan', 'task'}.contains(type)) ||
      (item != null && (item.isEmpty || item.length > 128))) {
    return '/planner';
  }
  final create = uri.queryParameters['create'];
  if (create != null && !{'bucket', 'date', 'plan'}.contains(create)) {
    return '/planner';
  }
  final request = uri.queryParameters['request'];
  if (request != null &&
      (create == null ||
          request.length > 64 ||
          !RegExp(r'^[0-9-]+$').hasMatch(request))) {
    return '/planner';
  }
  final query = <String, String>{};
  if (tab != null) query['tab'] = tab;
  if (type != null) query['type'] = type;
  if (item != null) query['item'] = item;
  if (create != null) query['create'] = create;
  if (request != null) query['request'] = request;
  return Uri(
    path: '/planner',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, route) {
      if (route.uri.path == '/auth/callback') return null;
      final phase = ref.read(authControllerProvider).phase;
      final authenticated = phase == AuthPhase.authenticated;
      if (phase == AuthPhase.recovering &&
          (route.uri.path == '/account' || route.uri.path == '/auth/local')) {
        return '/auth/recovery';
      }
      if (route.uri.path == '/account' && !authenticated) {
        return '/auth/local?next=%2Faccount';
      }
      if (route.uri.path == '/partner' && !authenticated) {
        return '/auth/local?next=%2Fpartner';
      }
      if ((route.uri.path == '/planner' ||
              route.uri.path == '/search' ||
              route.uri.path == '/budget' ||
              route.uri.path == '/memories') &&
          !authenticated) {
        return '/auth/local?next=${Uri.encodeComponent(route.uri.toString())}';
      }
      if (route.uri.path.startsWith('/auth/') && authenticated) {
        return _safeNextRoute(route.uri.queryParameters['next']) ?? '/';
      }
      return null;
    },
    routes: [
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
        builder: (context, state) => const LocalLifecycleScreen(recovery: true),
      ),
      GoRoute(
        path: '/auth/local',
        builder: (context, state) => LocalAuthScreen(
          nextRoute: _safeNextRoute(state.uri.queryParameters['next']),
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
      ShellRoute(
        builder: (context, state, child) => AdaptiveShell(
          path: state.uri.path,
          queryParameters: state.uri.queryParameters,
          child: child,
        ),
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
          GoRoute(
            path: '/search',
            builder: (context, state) => const GlobalSearchScreen(),
          ),
          GoRoute(
            path: '/planner',
            builder: (context, state) =>
                const SharedPlannerScreen(embedded: true),
          ),
          GoRoute(
            path: '/budget',
            builder: (context, state) => const BudgetScreen(),
          ),
          GoRoute(
            path: '/memories',
            builder: (context, state) => const MemoriesScreen(),
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
