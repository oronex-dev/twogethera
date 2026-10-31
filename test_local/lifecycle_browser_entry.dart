import 'package:flutter_test/flutter_test.dart';

import '../test/support/lifecycle_real_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerLifecycleTests();
}
