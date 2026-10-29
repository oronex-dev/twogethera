import 'dart:developer' as developer;

abstract final class AppErrorHandler {
  /// Local diagnostics only; no external reporting or user data collection.
  static void report(Object error, StackTrace stack) {
    developer.log(
      'An unexpected application error occurred.',
      name: 'twogethera',
      level: 1000,
    );
  }
}
