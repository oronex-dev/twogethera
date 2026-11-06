import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';

import 'routing/app_router.dart';
import 'theme/app_theme.dart';
import '../features/appearance/application/appearance_controller.dart';
import '../features/appearance/domain/appearance_preferences.dart';
import '../features/authentication/application/auth_controller.dart';

class TwogetheraApp extends ConsumerStatefulWidget {
  const TwogetheraApp({super.key});

  @override
  ConsumerState<TwogetheraApp> createState() => _TwogetheraAppState();
}

class _TwogetheraAppState extends ConsumerState<TwogetheraApp> {
  String? _boundUserId;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final appearance = ref.watch(appearanceControllerProvider);
    final userId = auth.phase == AuthPhase.authenticated
        ? auth.context?.userId
        : null;

    if (userId != null && userId != _boundUserId) {
      _boundUserId = userId;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(authControllerProvider).context?.userId == userId) {
          ref.read(appearanceControllerProvider.notifier).load(userId);
        }
      });
    } else if (userId == null && _boundUserId != null) {
      _boundUserId = null;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(authControllerProvider).phase != AuthPhase.authenticated) {
          ref.read(appearanceControllerProvider.notifier).clearAccount();
        }
      });
    }

    final preferences = appearance.userId == null || appearance.userId == userId
        ? appearance.preferences
        : const AppearancePreferences();
    final waitingForAppearance =
        userId != null && (appearance.userId != userId || appearance.loading);
    return MaterialApp.router(
      title: 'Twogethera',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(preferences),
      darkTheme: AppTheme.dark(preferences),
      themeMode: preferences.mode,
      themeAnimationDuration: const Duration(milliseconds: 280),
      themeAnimationCurve: Curves.easeInOutCubic,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        if (!waitingForAppearance) return child ?? const SizedBox.shrink();
        final dark =
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        final foreground = dark
            ? const Color(0xFFE6E8EC)
            : const Color(0xFF353A42);
        return ColoredBox(
          color: dark ? const Color(0xFF15171B) : const Color(0xFFF6F7F8),
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: 'Loading your personal appearance',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading your personal appearance…',
                    style: TextStyle(color: foreground),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
