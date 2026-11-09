import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/app/routing/app_router.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';

class _SignedOutAuthController extends AuthController {
  @override
  AuthViewState build() => const AuthViewState(AuthPhase.signedOut);
}

void main() {
  testWidgets('deferred Memories route redirects to Summary', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_SignedOutAuthController.new),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.go('/memories');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Page not found'), findsNothing);
  });
}
