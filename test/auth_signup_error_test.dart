import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';

void main() {
  test('duplicate signup codes map to a useful existing-account message', () {
    for (final code in ['email_exists', 'user_already_exists']) {
      final error = AuthFailure.registrationResponse(
        code: code,
        transient: false,
      );
      expect(error.problem, AuthProblem.emailAlreadyRegistered);
      expect(error.message, contains('Sign in'));
    }
  });

  test('weak password and other registration failures remain distinct', () {
    expect(
      AuthFailure.registrationResponse(
        code: 'weak_password',
        transient: false,
      ).problem,
      AuthProblem.passwordRejected,
    );
    expect(
      AuthFailure.registrationResponse(
        code: 'validation_failed',
        transient: false,
      ).problem,
      AuthProblem.registrationRejected,
    );
    expect(
      AuthFailure.registrationResponse(code: null, transient: true).problem,
      AuthProblem.unavailable,
    );
  });
}
