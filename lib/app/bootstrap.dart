import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_error_handler.dart';
import 'twogethera_app.dart';

void bootstrap() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppErrorHandler.report(
        details.exception,
        details.stack ?? StackTrace.current,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppErrorHandler.report(error, stack);
      return true;
    };
    ErrorWidget.builder = (_) => const Material(
      child: Center(
        child: Text('Something went wrong. Please restart Twogethera.'),
      ),
    );
    runApp(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.fromEnvironment()),
        ],
        child: const TwogetheraApp(),
      ),
    );
  }, AppErrorHandler.report);
}
