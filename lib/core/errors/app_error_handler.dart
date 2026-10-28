import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

abstract final class AppErrorHandler {
  /// Local diagnostics only; no external reporting or user data collection.
  static void report(Object error, StackTrace stack) {
    developer.log(
      kDebugMode
          ? error.toString()
          : 'An unexpected application error occurred.',
      name: 'twogethera',
      level: 1000,
      error: kDebugMode ? error : null,
      stackTrace: kDebugMode ? stack : null,
    );
  }
}
