import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twogethera/core/config/local_auth_config.dart';
import 'package:twogethera/core/config/app_config.dart';
import 'package:twogethera/features/authentication/presentation/auth_callback_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/authentication/domain/password_policy.dart';
import 'package:twogethera/features/authentication/presentation/auth_components.dart';
import 'package:twogethera/app/theme/theme_mode_controller.dart';
import 'package:twogethera/features/dashboard/domain/dashboard_preferences.dart';

import 'auth_lifecycle_test.dart' show LifecycleFake;
import 'authentication_test.dart' show setup, show, config;

// UI/controller doubles only. Genuine Supabase results are a separate suite.
class ExperienceFake extends LifecycleFake
    implements
        AuthExperienceRepository,
        DashboardPreferencesRepository,
        PrivateBetaAccountLifecycleRepository {
  int registrations = 0, resends = 0, resets = 0;
  int coupleClosures = 0, accountDeletions = 0;
  AuthProblem? lifecycleFailure;
  final order = <String>[];
  @override
  Future<void> registerProfile(
    String email,
    String password,
    String displayName,
  ) async {
    registrations++;
  }

  @override
  Future<void> resendVerification(String email) async {
    resends++;
  }

  @override
  Future<void> updatePassword(String password) async {
    resets++;
    await super.updatePassword(password);
  }

  @override
  Future<void> clearLocalSession() async {
    order.add('clear');
    await super.clearLocalSession();
  }

  @override
  Future<void> verifyLink(String link, {required bool recovery}) async {
    order.add(link.isEmpty ? 'invalid' : 'verify');
    if (link.isEmpty) throw const AuthFailure(AuthProblem.invalidLink);
    await super.verifyLink(link, recovery: recovery);
  }

  @override
  Future<DashboardPreferences?> loadDashboardPreferences(String userId) async =>
      null;

  @override
  Future<void> saveDashboardPreferences(
    String userId,
    DashboardPreferences preferences,
  ) async {}

  @override
  Future<void> closeCoupleSpace(String operationId) async {
    if (lifecycleFailure case final failure?) throw AuthFailure(failure);
    coupleClosures++;
    events.add(AuthSignal.cleared);
  }

  @override
  Future<void> deleteAccount(String operationId) async {
    if (lifecycleFailure case final failure?) throw AuthFailure(failure);
    accountDeletions++;
    events.add(AuthSignal.cleared);
  }
}

Finder key(String value) => find.byKey(ValueKey(value));
Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  for (final environment in [
    AppEnvironment.development,
    AppEnvironment.staging,
    AppEnvironment.production,
  ]) {
    testWidgets('${environment.name} keeps public registration closed', (
      tester,
    ) async {
      final fake = ExperienceFake();
      final c = setup(fake, environment: environment);
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await show(tester, c, '/auth/register');
      expect(
        find.textContaining('New account registration is closed.'),
        findsOneWidget,
      );
      expect(key('lifecycle-password'), findsNothing);
    });
  }

  for (final entry in [
    (
      environment: AppEnvironment.development,
      expected: 'Local preview · Synthetic accounts only.',
    ),
    (environment: AppEnvironment.staging, expected: 'Private beta staging ·'),
    (
      environment: AppEnvironment.production,
      expected: 'For your privacy, sign in again',
    ),
  ]) {
    testWidgets('auth disclosure matches ${entry.environment.name}', (
      tester,
    ) async {
      final fake = ExperienceFake();
      final c = setup(fake, environment: entry.environment);
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await show(tester, c, '/auth/welcome');

      expect(find.textContaining(entry.expected), findsOneWidget);
      if (entry.environment == AppEnvironment.production) {
        expect(find.textContaining('Local preview'), findsNothing);
        expect(find.textContaining('Synthetic accounts only'), findsNothing);
      }
    });
  }

  testWidgets('welcome registration link explains closed private beta', (
    tester,
  ) async {
    final fake = ExperienceFake();
    final c = setup(fake);
    addTearDown(c.dispose);
    addTearDown(fake.dispose);
    await show(tester, c, '/auth/welcome');
    await tap(tester, 'Create account');
    expect(
      find.textContaining('New account registration is closed.'),
      findsOneWidget,
    );
    expect(key('auth-display-name'), findsNothing);
    expect(fake.registrations, 0);
  });

  test(
    'closing a couple clears local auth only after repository success',
    () async {
      final fake = ExperienceFake();
      final c = setup(fake);
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      final controller = c.read(authControllerProvider.notifier);
      await controller.signIn('partner@example.invalid', 'synthetic');
      expect(c.read(authControllerProvider).phase, AuthPhase.authenticated);

      fake.lifecycleFailure = AuthProblem.lifecycleUnavailable;
      expect(await controller.closeCoupleSpace(), isFalse);
      expect(c.read(authControllerProvider).phase, AuthPhase.authenticated);
      expect(fake.coupleClosures, 0);

      fake.lifecycleFailure = null;
      expect(await controller.closeCoupleSpace(), isTrue);
      expect(fake.coupleClosures, 1);
      expect(c.read(authControllerProvider).phase, AuthPhase.signedOut);
    },
  );
  testWidgets(
    'reduced motion disables feedback animation and keeps live semantics',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final fake = ExperienceFake();
      final c = setup(fake);
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await c
          .read(authControllerProvider.notifier)
          .resendVerification('a@example.invalid');
      await show(tester, c, '/auth/verify');
      expect(
        tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
        Duration.zero,
      );
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((s) => s.properties.liveRegion == true),
        isTrue,
      );
    },
  );
  testWidgets(
    'password visibility and keyboard submit are accessible and functional',
    (tester) async {
      final fake = ExperienceFake();
      final c = setup(fake);
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await show(tester, c, '/auth/local');
      await tester.enterText(key('auth-email'), 'river@example.invalid');
      await tester.enterText(key('auth-password'), 'synthetic');
      await tester.ensureVisible(find.byTooltip('Show password'));
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: key('auth-password'),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isFalse,
      );
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: key('auth-password'),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isTrue,
      );
      await tester.showKeyboard(key('auth-password'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(fake.logins, 1);
      expect(find.text('Your shared space'), findsOneWidget);
    },
  );
  testWidgets('verification resend has generic feedback and can retry', (
    tester,
  ) async {
    final fake = ExperienceFake();
    final c = setup(fake);
    addTearDown(c.dispose);
    addTearDown(fake.dispose);
    await show(tester, c, '/auth/verify');
    await tester.enterText(key('lifecycle-email'), 'river@example.invalid');
    await tap(tester, 'Resend confirmation');
    expect(fake.resends, 1);
    expect(
      c.read(authControllerProvider).notice,
      contains('If the address is eligible'),
    );
    expect(c.read(authControllerProvider).context, isNull);
  });
  testWidgets(
    'recovery mismatch never updates password; success asks for sign-in',
    (tester) async {
      final fake = ExperienceFake();
      final c = setup(fake);
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await c
          .read(authControllerProvider.notifier)
          .verifyLink('unit-only', recovery: true);
      await show(tester, c, '/auth/recovery');
      await tester.enterText(key('lifecycle-password'), 'FreshPass1!');
      await tester.enterText(key('auth-confirm-password'), 'OtherPass1!');
      await tester.pumpAndSettle();
      await tap(tester, 'Update password');
      expect(fake.resets, 0);
      await tester.enterText(key('auth-confirm-password'), 'FreshPass1!');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Update password'),
            )
            .onPressed,
        isNotNull,
      );
      await tap(tester, 'Update password');
      expect(fake.resets, 1);
      expect(
        c.read(authControllerProvider).notice,
        contains('Password changed'),
      );
      await tap(tester, 'Return to sign-in');
      expect(key('auth-email'), findsOneWidget);
    },
  );
  testWidgets(
    'callback scrubs before clearing and verification; no recovery account access',
    (tester) async {
      final fake = ExperienceFake();
      final c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
          localAuthConfigProvider.overrideWithValue(config()),
          callbackLocationScrubberProvider.overrideWithValue(
            (_) => fake.order.add('scrub'),
          ),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await show(
        tester,
        c,
        '/auth/callback?type=recovery&token_hash=pkce_${'a' * 56}',
      );
      expect(fake.order, ['scrub', 'clear', 'verify']);
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.toString(),
        '/auth/recovery',
      );
      expect(c.read(authControllerProvider).phase, AuthPhase.recovering);
      expect(key('account-verified'), findsNothing);
    },
  );
  testWidgets(
    'callback accepts Supabase query before the hash route and scrubs it first',
    (tester) async {
      final fake = ExperienceFake();
      final c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
          localAuthConfigProvider.overrideWithValue(config()),
          callbackBrowserUriProvider.overrideWithValue(
            Uri.parse(
              'https://beta.twogethera.com/?type=signup&token_hash=pkce_${'a' * 56}#/auth/callback',
            ),
          ),
          callbackLocationScrubberProvider.overrideWithValue(
            (_) => fake.order.add('scrub'),
          ),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await show(tester, c, '/auth/callback');
      expect(fake.order, ['scrub', 'clear', 'verify']);
      expect(c.read(authControllerProvider).phase, AuthPhase.authenticated);
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.toString(),
        '/',
      );
    },
  );
  testWidgets(
    'hash-route recovery callback reads outer token_hash and enters recovery only',
    (tester) async {
      final fake = ExperienceFake();
      final c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fake),
          localAuthConfigProvider.overrideWithValue(config()),
          callbackBrowserUriProvider.overrideWithValue(
            Uri.parse(
              'https://beta.twogethera.com/?type=recovery&token_hash=pkce_${'b' * 56}#/auth/callback',
            ),
          ),
          callbackLocationScrubberProvider.overrideWithValue(
            (_) => fake.order.add('scrub'),
          ),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await show(tester, c, '/auth/callback');
      expect(fake.order, ['scrub', 'clear', 'verify']);
      expect(c.read(authControllerProvider).phase, AuthPhase.recovering);
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.toString(),
        '/auth/recovery',
      );
      expect(key('account-verified'), findsNothing);
    },
  );
  testWidgets(
    'unsupported callback fails safely and removes query from route',
    (tester) async {
      final fake = ExperienceFake();
      final c = setup(fake);
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await show(tester, c, '/auth/callback?code=unsupported-unit-value');
      expect(fake.order, ['clear', 'invalid']);
      expect(c.read(authControllerProvider).problem, AuthProblem.invalidLink);
      expect(
        c.read(appRouterProvider).routeInformationProvider.value.uri.hasQuery,
        isFalse,
      );
    },
  );
  testWidgets('appearance selection and keyboard focus work without storage', (
    tester,
  ) async {
    final fake = ExperienceFake();
    final c = setup(fake);
    addTearDown(c.dispose);
    addTearDown(fake.dispose);
    await show(tester, c, '/auth/welcome');
    await tester.tap(find.byTooltip('Choose appearance'));
    await tester.pumpAndSettle();
    await tap(tester, 'Dark');
    expect(c.read(themeModeProvider), ThemeMode.dark);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });
  for (final dark in [false, true]) {
    for (final route in [
      '/auth/welcome',
      '/auth/register',
      '/auth/verify',
      '/auth/recovery',
      '/account',
    ]) {
      testWidgets('$route accessibility ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final handle = tester.ensureSemantics();
        final fake = ExperienceFake();
        final c = setup(fake);
        addTearDown(c.dispose);
        addTearDown(fake.dispose);
        if (route == '/account') {
          await c
              .read(authControllerProvider.notifier)
              .signIn('a@example.invalid', 'synthetic');
        }
        await show(tester, c, route);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }
  testWidgets('desktop split keeps form bounded and brand panel readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = ExperienceFake();
    final c = setup(fake);
    addTearDown(c.dispose);
    addTearDown(fake.dispose);
    await show(tester, c, '/auth/local');
    expect(find.text('A little closer.\nEvery day.'), findsOneWidget);
    expect(tester.getSize(find.byType(Form)).width, lessThanOrEqualTo(520));
    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets('welcome fits $width landscape at 200% with keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 480);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final fake = ExperienceFake();
      final c = setup(fake);
      addTearDown(c.dispose);
      addTearDown(fake.dispose);
      await show(tester, c, '/auth/welcome');
      expect(tester.takeException(), isNull);
      await tap(tester, 'Create account');
      expect(tester.takeException(), isNull);
    });
  }
  test(
    'local email and password validators preserve synthetic-only boundaries',
    () {
      expect(validateLocalEmail('real@example.com'), isNotNull);
      expect(validateLocalEmail('not-an-email'), isNotNull);
      expect(validateLocalEmail('invalid'), isNotNull);
      expect(validateLocalEmail('a@example.invalid'), isNull);
      expect(validateNewPassword('short'), isNotNull);
      expect(validateNewPassword('RiverPass1!'), isNull);
    },
  );
}
