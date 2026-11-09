import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/domain/password_policy.dart';

void main() {
  test('eight characters with all four character classes is accepted', () {
    expect('Abcdef1!'.runes.length, minimumPasswordLength);
    expect(evaluatePassword('Abcdef1!').isComplete, isTrue);
    expect(validateNewPassword('Abcdef1!'), isNull);
  });

  test('each password requirement is independently enforced', () {
    expect(evaluatePassword('Abcde1!').minimumLength, isFalse);
    expect(evaluatePassword('abcdef1!').uppercase, isFalse);
    expect(evaluatePassword('ABCDEF1!').lowercase, isFalse);
    expect(evaluatePassword('Abcdefg!').number, isFalse);
    expect(evaluatePassword('Abcdef12').special, isFalse);
    for (final weak in [
      'Abcde1!',
      'abcdef1!',
      'ABCDEF1!',
      'Abcdefg!',
      'Abcdef12',
    ]) {
      expect(validateNewPassword(weak), isNotNull, reason: weak);
    }
  });

  test('strength labels follow the number of live requirements met', () {
    expect(evaluatePassword('').strength, 'Weak');
    expect(evaluatePassword('riverpass').strength, 'Fair');
    expect(evaluatePassword('Riverpass').strength, 'Fair');
    expect(evaluatePassword('RiverPass1').strength, 'Good');
    expect(evaluatePassword('RiverPass1!').strength, 'Strong');
  });
}
