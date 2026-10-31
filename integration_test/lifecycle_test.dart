import 'package:integration_test/integration_test.dart';

import '../test/support/lifecycle_real_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerLifecycleTests();
}
