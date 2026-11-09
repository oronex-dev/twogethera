/// Password rules shared by registration, password recovery, and repositories.
/// Keep in sync with Supabase Auth's local `password_requirements` setting.
const int minimumPasswordLength = 8;

const String passwordSpecialCharacters =
    r'''!@#$%^&*()_+-=[]{};':"\|<>?,./`~''';

class PasswordRequirements {
  const PasswordRequirements({
    required this.minimumLength,
    required this.uppercase,
    required this.lowercase,
    required this.number,
    required this.special,
  });

  final bool minimumLength;
  final bool uppercase;
  final bool lowercase;
  final bool number;
  final bool special;

  int get completedCount => [
    minimumLength,
    uppercase,
    lowercase,
    number,
    special,
  ].where((value) => value).length;

  bool get isComplete => completedCount == 5;

  String get strength => switch (completedCount) {
    <= 1 => 'Weak',
    <= 3 => 'Fair',
    4 => 'Good',
    _ => 'Strong',
  };
}

PasswordRequirements evaluatePassword(String? value) {
  final password = value ?? '';
  return PasswordRequirements(
    minimumLength: password.runes.length >= minimumPasswordLength,
    uppercase: RegExp(r'[A-Z]').hasMatch(password),
    lowercase: RegExp(r'[a-z]').hasMatch(password),
    number: RegExp(r'[0-9]').hasMatch(password),
    special: password.runes.any(
      (rune) => passwordSpecialCharacters.contains(String.fromCharCode(rune)),
    ),
  );
}

String? validateNewPassword(String? value) => evaluatePassword(value).isComplete
    ? null
    : 'Use 8 or more characters with uppercase, lowercase, a number, and a special character.';
