import 'package:flutter_test/flutter_test.dart' show setUp, tearDown;
import 'package:integration_test/integration_test.dart';

import '../test/support/auth_experience_real_cases.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Native test runners may initialize the binding before main. Register the
  // framework's controlled keyboard on that binding for each test. Real HTTP
  // remains enabled; these tests do not claim OS-keyboard/IME acceptance.
  setUp(binding.testTextInput.register);
  tearDown(binding.testTextInput.unregister);
  registerAuthExperienceTests();
}
