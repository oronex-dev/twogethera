import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/design_studio/presentation/design_studio_screen.dart';
import '../../shared/widgets/adaptive_shell.dart';
import '../../shared/widgets/responsive_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
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
