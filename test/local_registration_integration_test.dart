import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:twogethera/core/config/local_auth_config.dart';
import 'package:twogethera/features/authentication/data/local_auth_clients.dart';
import 'package:twogethera/features/authentication/data/supabase_auth_repository.dart';

const _signInEmail = String.fromEnvironment('LOCAL_TEST_EMAIL');
const _signInPassword = String.fromEnvironment('LOCAL_TEST_PASSWORD');

Future<String> _mailpitConfirmationLink(String recipient) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    for (var attempt = 0; attempt < 20; attempt++) {
      final messagesRequest = await client.getUrl(
        Uri.parse('http://127.0.0.1:54324/api/v1/messages'),
      );
      final messagesResponse = await messagesRequest.close();
      if (messagesResponse.statusCode != 200) {
        throw StateError('Local confirmation mailbox is unavailable.');
      }
      final payload = jsonDecode(
        await messagesResponse.transform(utf8.decoder).join(),
      ) as Map;
      final messages = payload['messages'] as List;
      final matching = messages.where(
        (message) => jsonEncode((message as Map)['To']).contains(recipient),
      );
      for (final message in matching) {
        final id = (message as Map)['ID'] as String;
        final detailRequest = await client.getUrl(
          Uri.parse('http://127.0.0.1:54324/api/v1/message/$id'),
        );
        final detailResponse = await detailRequest.close();
        if (detailResponse.statusCode != 200) continue;
        final detail = jsonDecode(
          await detailResponse.transform(utf8.decoder).join(),
        ) as Map;
        final body = '${detail['Text'] ?? ''}\n${detail['HTML'] ?? ''}'
            .replaceAll('&amp;', '&');
        for (final match in RegExp(r'https?://[^\s"<>]+').allMatches(body)) {
          final candidate = match.group(0)!.replaceAll(RegExp(r'[),.;]+$'), '');
          final uri = Uri.tryParse(candidate);
          if (uri?.host == '127.0.0.1' &&
              uri?.port == 54321 &&
              uri?.path == '/auth/v1/verify' &&
              uri?.queryParameters['type'] == 'signup' &&
              uri?.queryParameters.containsKey('token') == true) {
            return candidate;
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('Local confirmation email was not captured.');
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('public signup is disabled for the two-account private beta', () async {
    final config = LocalAuthConfig.fromEnvironment();
    if (config == null) {
      markTestSkipped('Run with the local-only Supabase Dart defines.');
      return;
    }
    expect(config.endpoint, Uri.parse('http://127.0.0.1:54321'));

    final repository = SupabaseAuthRepository(
      createClients: () => LocalAuthClients(
        url: config.endpoint.toString(),
        publicKey: config.publicKey,
        schema: config.dataSchema,
      ),
      allowRealAccounts: false,
    );
    try {
      final email =
          'local-registration-${DateTime.now().microsecondsSinceEpoch}@example.invalid';
      await repository.registerProfile(email, 'Abcdef1!', 'Local QA');
      final confirmation = await _mailpitConfirmationLink(email);
      await repository.verifyLink(confirmation, recovery: false);
      final account = await repository.accountContext();
      expect(account.email, email);
      await repository.signOut();
      await repository.signIn(email, 'Abcdef1!');
      final signedInAccount = await repository.accountContext();
      expect(signedInAccount.email, email);
    } finally {
      await repository.dispose();
    }
  }, skip: 'Signup is disabled by the approved Private Beta V1 policy.');

  test('local password policy proof requires the isolated signup test environment', () async {
    final config = LocalAuthConfig.fromEnvironment();
    if (config == null) {
      markTestSkipped('Run with the local-only Supabase Dart defines.');
      return;
    }
    final clients = LocalAuthClients(
      url: config.endpoint.toString(),
      publicKey: config.publicKey,
      schema: config.dataSchema,
    );
    try {
      await expectLater(
        clients.auth.signUp(
          email:
              'local-weak-password-${DateTime.now().microsecondsSinceEpoch}@example.invalid',
          password: 'Abcdef12',
        ),
        throwsA(isA<AuthException>()),
      );
    } finally {
      await clients.dispose();
    }
  }, skip: 'Public signup is disabled by the approved Private Beta V1 policy.');

  test(
    'verified synthetic account signs in through local Supabase Auth',
    () async {
      final config = LocalAuthConfig.fromEnvironment();
      if (config == null || _signInEmail.isEmpty || _signInPassword.isEmpty) {
        markTestSkipped('Run with local-only sign-in fixture defines.');
        return;
      }
      expect(config.endpoint, Uri.parse('http://127.0.0.1:54321'));

      final repository = SupabaseAuthRepository(
        createClients: () => LocalAuthClients(
          url: config.endpoint.toString(),
          publicKey: config.publicKey,
          schema: config.dataSchema,
        ),
        allowRealAccounts: false,
      );
      try {
        await repository.signIn(_signInEmail, _signInPassword);
        final account = await repository.accountContext();
        expect(account.email, _signInEmail);
        expect(account.spaces, isEmpty);
      } finally {
        await repository.signOut();
        await repository.dispose();
      }
    },
  );
}
