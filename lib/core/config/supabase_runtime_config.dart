import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_auth_config.dart';

enum BackendEnvironment { development, staging, production }

/// Client-only Supabase settings. A publishable/anon key is public by design;
/// secret and service-role keys are rejected and must never reach Flutter.
class SupabaseRuntimeConfig {
  const SupabaseRuntimeConfig({
    required this.environment,
    required this.endpoint,
    required this.publishableKey,
    required this.webBaseUrl,
    this.developmentSchema = 'public',
  });

  final BackendEnvironment environment;
  final Uri endpoint;
  final String publishableKey;
  final Uri? webBaseUrl;
  final String developmentSchema;

  bool get isDevelopment => environment == BackendEnvironment.development;

  /// The app uses Flutter's hash URL strategy, so the callback route belongs
  /// in the fragment rather than at a server path on the web origin.
  Uri? get authCallbackUrl => webBaseUrl?.resolve('/#/auth/callback');

  static SupabaseRuntimeConfig? fromEnvironment({
    bool debug = kDebugMode,
    String environment = const String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    ),
    String url = const String.fromEnvironment('SUPABASE_URL'),
    String publishableKey = const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    ),
    String legacyAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
    String webBaseUrl = const String.fromEnvironment('APP_WEB_URL'),
  }) {
    if (environment == 'development') return null;
    final parsedEnvironment = switch (environment) {
      'staging' => BackendEnvironment.staging,
      'production' => BackendEnvironment.production,
      _ => null,
    };
    if (parsedEnvironment == null) return null;
    return parseHosted(
      environment: parsedEnvironment,
      url: url,
      publishableKey: publishableKey.isNotEmpty
          ? publishableKey
          : legacyAnonKey,
      webBaseUrl: webBaseUrl,
    );
  }

  static SupabaseRuntimeConfig? fromLocal(LocalAuthConfig config) =>
      SupabaseRuntimeConfig(
        environment: BackendEnvironment.development,
        endpoint: config.endpoint,
        publishableKey: config.publicKey,
        webBaseUrl: null,
        developmentSchema: config.dataSchema,
      );

  static SupabaseRuntimeConfig? parseHosted({
    required BackendEnvironment environment,
    required String url,
    required String publishableKey,
    required String webBaseUrl,
  }) {
    if (environment == BackendEnvironment.development) return null;
    final endpoint = Uri.tryParse(url.trim());
    final app = Uri.tryParse(webBaseUrl.trim());
    if (!_validHostedOrigin(endpoint) ||
        !_validHostedOrigin(app) ||
        !_validClientKey(publishableKey)) {
      return null;
    }
    return SupabaseRuntimeConfig(
      environment: environment,
      endpoint: endpoint!,
      publishableKey: publishableKey,
      webBaseUrl: app!,
    );
  }

  static bool _validHostedOrigin(Uri? value) {
    if (value == null ||
        value.scheme != 'https' ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        (value.port != 443 && value.hasPort) ||
        (value.path.isNotEmpty && value.path != '/') ||
        value.hasQuery ||
        value.hasFragment) {
      return false;
    }
    final host = value.host.toLowerCase();
    return host != 'localhost' &&
        host != '127.0.0.1' &&
        host != '::1' &&
        !RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host) &&
        !host.contains(':') &&
        !host.endsWith('.invalid') &&
        !host.endsWith('.test') &&
        !host.endsWith('.example');
  }

  static bool _validClientKey(String value) {
    final key = value.trim();
    if (key.isEmpty || key != value || key.contains(RegExp(r'\s'))) {
      return false;
    }
    if (key.startsWith('sb_publishable_')) return key.length >= 32;
    if (key.startsWith('sb_secret_') || key.startsWith('service_role')) {
      return false;
    }
    try {
      final parts = key.split('.');
      if (parts.length != 3) return false;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return claims is Map && claims['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  @override
  String toString() =>
      'SupabaseRuntimeConfig(${environment.name}, endpoint=${endpoint.origin}, key=[redacted])';
}

final supabaseRuntimeConfigProvider = Provider<SupabaseRuntimeConfig?>((ref) {
  final local = ref.watch(localAuthConfigProvider);
  if (local != null) return SupabaseRuntimeConfig.fromLocal(local);
  return SupabaseRuntimeConfig.fromEnvironment();
});
