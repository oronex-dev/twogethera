import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppEnvironment { development, staging, production }

/// Public build configuration only. Dart defines must never contain secrets.
class AppConfig {
  const AppConfig({required this.environment});

  factory AppConfig.fromEnvironment() => AppConfig(
    environment: AppEnvironment.values.byName(
      const String.fromEnvironment('APP_ENV', defaultValue: 'development'),
    ),
  );

  final AppEnvironment environment;
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => const AppConfig(environment: AppEnvironment.development),
);
