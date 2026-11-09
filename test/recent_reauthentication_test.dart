import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/authentication/presentation/recent_reauthentication_dialog.dart';

import 'authentication_test.dart' show FakeAuthRepository, setup;

class _RecentAuthFake extends FakeAuthRepository
    implements RecentReauthenticationRepository {
  final attempts = <String>[];

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    attempts.add(password);
    if (password != 'CorrectPass123!') {
      throw const AuthFailure(AuthProblem.reauthenticationFailed);
    }
  }
}

void main() {
  testWidgets('reauth dialog retries safely and does not display password', (
    tester,
  ) async {
    final repository = _RecentAuthFake();
    final container = setup(repository);
    addTearDown(container.dispose);
    addTearDown(repository.dispose);

    var verified = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  verified = await requestRecentPasswordReauthentication(
                    context,
                    ref,
                  );
                },
                child: const Text('Sensitive action'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Sensitive action'));
    await tester.pumpAndSettle();
    final passwordField = find.byType(TextField);
    await tester.enterText(passwordField, 'wrong-password');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Verify and retry'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Verify and retry'));
    await tester.pumpAndSettle();
    expect(repository.attempts.length, 1);
    expect(
      find.text(
        'Password verification failed. Check your password and try again.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
    expect(repository.attempts, ['wrong-password']);

    await tester.enterText(passwordField, 'CorrectPass123!');
    await tester.tap(find.text('Verify and retry'));
    await tester.pumpAndSettle();
    expect(verified, isTrue);
    expect(repository.attempts, ['wrong-password', 'CorrectPass123!']);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
