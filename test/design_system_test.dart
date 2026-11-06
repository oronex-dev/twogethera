import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/app/theme/theme_mode_controller.dart';
import 'package:twogethera/app/twogethera_app.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/dashboard/domain/dashboard_preferences.dart';

Finder get pageScroll => find.descendant(
  of: find.byKey(const ValueKey('page-scroll')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

class _UnpairedNavigationAuth
    implements AuthRepository, DashboardPreferencesRepository {
  final _events = StreamController<AuthSignal>.broadcast(sync: true);

  @override
  Stream<AuthSignal> get changes => _events.stream;
  @override
  Future<void> signIn(String email, String password) async =>
      _events.add(AuthSignal.signedIn);
  @override
  Future<AccountContext> accountContext() async =>
      const AccountContext(userId: 'nav-user', spaces: []);
  @override
  Future<void> clearLocalSession() async => _events.add(AuthSignal.cleared);
  @override
  Future<void> dispose() => _events.close();
  @override
  Future<DashboardPreferences?> loadDashboardPreferences(String userId) async =>
      null;
  @override
  Future<void> saveDashboardPreferences(
    String userId,
    DashboardPreferences preferences,
  ) async {}
}

Future<ProviderContainer> open(
  WidgetTester tester, {
  String path = '/',
  double width = 390,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container
      .read(themeModeProvider.notifier)
      .setMode(dark ? ThemeMode.dark : ThemeMode.light);
  container.read(appRouterProvider).go(path);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const TwogetheraApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final width in [320.0, 768.0, 1440.0]) {
    for (final path in ['/', '/studio', '/settings']) {
      testWidgets('$path fits $width at 200% text in dark mode', (
        tester,
      ) async {
        await open(tester, path: path, width: width, scale: 2, dark: true);
        expect(tester.takeException(), isNull);
        final pageContent = switch (path) {
          '/' => 'Your shared space',
          '/studio' => 'Small details. A shared feeling.',
          _ => 'Make yourself at home',
        };
        expect(find.text(pageContent), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [390.0, 800.0, 1440.0]) {
    testWidgets('Adaptive navigation works at $width', (tester) async {
      final container = await open(tester, width: width);
      expect(
        find.byType(NavigationBar),
        width < 600 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(NavigationRail),
        width >= 600 && width < 1100 ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Design Studio').last);
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/studio',
      );
      expect(find.text('Small details. A shared feeling.'), findsOneWidget);
      if (width < 600) {
        expect(find.byType(NavigationBar), findsNothing);
      } else if (width < 1100) {
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          isNull,
        );
      } else {
        expect(
          (tester.widget<ListTile>(find.widgetWithText(ListTile, 'Summary')))
              .selected,
          isFalse,
        );
      }
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance').last);
      await tester.pumpAndSettle();
      expect(find.text('Make yourself at home'), findsOneWidget);
      if (width < 600) {
        expect(find.byType(NavigationBar), findsNothing);
      } else if (width < 1100) {
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .selectedIndex,
          isNull,
        );
      } else {
        expect(
          (tester.widget<ListTile>(find.widgetWithText(ListTile, 'Summary')))
              .selected,
          isFalse,
        );
      }
    });
  }

  testWidgets('Large-text mobile drawer opens all destinations', (
    tester,
  ) async {
    final container = await open(tester, width: 320, scale: 2);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('Bucket List'), findsOneWidget);
    expect(find.text('Important Dates'), findsOneWidget);
    expect(find.text('Plans & Calendar'), findsOneWidget);
    await tester.tap(find.text('Bucket List'));
    await tester.pumpAndSettle();
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/auth/local',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back and TogetherMark both return to Summary safely', (
    tester,
  ) async {
    final container = await open(tester, path: '/settings', width: 900);
    final router = container.read(appRouterProvider);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Your shared space'), findsOneWidget);

    router.push('/settings');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');

    router.go('/studio');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Go to Summary'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Your shared space'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Search and direct planner links retain their route context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _UnpairedNavigationAuth();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    addTearDown(auth.dispose);
    final router = container.read(appRouterProvider);
    await container
        .read(authControllerProvider.notifier)
        .signIn('nav@example.invalid', 'synthetic');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TwogetheraApp(),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/planner?tab=1&type=date&item=date-1');
    await tester.pumpAndSettle();
    expect(find.text('Important Dates'), findsOneWidget);
    expect(find.text('A space for two'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'tab': '1',
      'type': 'date',
      'item': 'date-1',
    });

    await tester.tap(find.byTooltip('Search your shared planner'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/search');
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.text('Link your partner to search shared planner data.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Studio selection, feedback and reset are real preview interactions',
    (tester) async {
      final container = await open(tester, path: '/studio');
      await tester.scrollUntilVisible(
        find.text('Lavender accent'),
        200,
        scrollable: pageScroll,
      );
      await tester.tap(find.text('Lavender accent'));
      await tester.pumpAndSettle();
      expect(find.text('A softer shade of together.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(Switch),
        150,
        scrollable: pageScroll,
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.scrollUntilVisible(
        find.text('Try a short note'),
        150,
        scrollable: pageScroll,
      );
      await tester.enterText(find.byType(TextField), 'Just a preview');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.scrollUntilVisible(
        find.text('Preview feedback'),
        150,
        scrollable: pageScroll,
      );
      await tester.tap(find.text('Preview feedback'));
      await tester.pumpAndSettle();
      expect(
        find.text('A small moment, beautifully acknowledged.'),
        findsOneWidget,
      );
      container.read(appRouterProvider).go('/');
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/studio');
      await tester.pumpAndSettle();
      expect(find.text('Just a preview'), findsNothing);
      expect(find.text('A warm little welcome.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Desktop navigation is reachable and activated with keyboard', (
    tester,
  ) async {
    await open(tester, width: 1440);
    var focusedStudio = false;
    for (var i = 0; i < 24; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
        element,
      ) {
        final widget = element.widget;
        if (widget is ListTile &&
            widget.title is Text &&
            (widget.title! as Text).data == 'Design Studio') {
          focusedStudio = true;
        }
        return !focusedStudio;
      });
      if (focusedStudio) {
        break;
      }
    }
    expect(focusedStudio, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Small details. A shared feeling.'), findsOneWidget);
  });

  testWidgets('Summary remains the signed-out landing page without overflow', (
    tester,
  ) async {
    await open(tester, width: 320, scale: 2);
    expect(find.text('Your shared space'), findsOneWidget);
    expect(
      find.text('Sign in to see your shared plans and milestones.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final path in ['/', '/studio', '/settings']) {
      testWidgets(
        '$path accessibility guidelines in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await open(tester, path: path, dark: dark);
            for (var page = 0; page < 3; page++) {
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
              await expectLater(tester, meetsGuideline(textContrastGuideline));
              await tester.drag(pageScroll, const Offset(0, -600));
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          } finally {
            handle.dispose();
          }
        },
      );
    }
  }
}
