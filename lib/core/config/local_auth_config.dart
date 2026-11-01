import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Public, debug-only configuration. Never accepts hosted endpoints or admin keys.
class LocalAuthConfig {
  const LocalAuthConfig({required this.endpoint, required this.publicKey});
  final Uri endpoint;
  final String publicKey;

  /// The committed membership foundation is exposed through `public` on the
  /// root local project; earlier auth lifecycle proofs use their isolated API.
  String get dataSchema => endpoint.port == 54321 ? 'public' : 'cp004b2';

  static LocalAuthConfig? fromEnvironment() => parse(
    enabled: kDebugMode && const bool.fromEnvironment('LOCAL_AUTH_ENABLED'),
    environment: const String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    ),
    url: const String.fromEnvironment('LOCAL_SUPABASE_URL'),
    publicKey: const String.fromEnvironment('LOCAL_SUPABASE_ANON_KEY'),
    android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  );

  static LocalAuthConfig? parse({
    required bool enabled,
    required String environment,
    required String url,
    required String publicKey,
    bool android = false,
  }) {
    if (!enabled || environment != 'development') return null;
    final uri = Uri.tryParse(
      url.isEmpty ? 'http://${android ? '10.0.2.2' : '127.0.0.1'}:58321' : url,
    );
    if (uri == null ||
        uri.scheme != 'http' ||
        !{'127.0.0.1', 'localhost', '::1', '10.0.2.2'}.contains(uri.host) ||
        !{54321, 55321, 56321, 58321}.contains(uri.port) ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    try {
      final parts = publicKey.split('.');
      if (parts.length != 3 || publicKey.length > 4096) return null;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is! Map || claims['role'] != 'anon') return null;
    } catch (_) {
      return null;
    }
    return LocalAuthConfig(
      endpoint: uri.replace(path: ''),
      publicKey: publicKey,
    );
  }

  @override
  String toString() => 'LocalAuthConfig(local development only)';
}

final localAuthConfigProvider = Provider<LocalAuthConfig?>(
  (ref) => LocalAuthConfig.fromEnvironment(),
);
