import 'package:integration_test/integration_test.dart';

import '../test/support/real_auth_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerRealAuthTests();
}
