import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/app/twogethera_app.dart';

void main() {
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets('Home fits width $width with enlarged text', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const ProviderScope(child: TwogetheraApp()));
      await tester.pumpAndSettle();
      expect(find.text('Your shared space'), findsOneWidget);
      expect(
        find.text('Sign in to see your shared plans and milestones.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Appearance navigation and all theme modes work', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TwogetheraApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Make yourself at home'), findsOneWidget);
    await tester.ensureVisible(find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Dark'))).brightness,
      Brightness.dark,
    );
    await tester.ensureVisible(find.text('Light'));
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Light'))).brightness,
      Brightness.light,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.ensureVisible(find.text('System default'));
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('System default'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Your shared space'), findsOneWidget);
  });

  testWidgets('Unknown routes offer a working way home', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appRouterProvider).go('/missing');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TwogetheraApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Page not found'), findsOneWidget);
    await tester.tap(find.text('Go home'));
    await tester.pumpAndSettle();
    expect(find.text('Your shared space'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home passes accessible tap target and label checks', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(const ProviderScope(child: TwogetheraApp()));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
