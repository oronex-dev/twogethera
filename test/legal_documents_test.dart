import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/app/twogethera_app.dart';
import 'package:twogethera/features/legal/presentation/legal_document_screen.dart';
import 'package:twogethera/shared/widgets/adaptive_shell.dart';

void main() {
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('legal drafts reflow at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: LegalDocumentScreen(type: LegalDocumentType.privacy),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('DRAFT — REQUIRES LEGAL REVIEW'), findsOneWidget);
      expect(find.text('Account and profile information'), findsOneWidget);
      expect(
        find.text('Retention, unlinking, and account deletion'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: LegalDocumentScreen(type: LegalDocumentType.terms),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Terms of service'), findsOneWidget);
      expect(find.text('Service terms not yet defined'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('legal routes use one header and navigate back correctly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    router.go('/privacy');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TwogetheraApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(AdaptiveShell), findsNothing);

    router.push('/terms');
    await tester.pumpAndSettle();
    expect(find.text('Terms of service'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/privacy');

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Your shared space'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
