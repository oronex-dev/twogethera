import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/presentation/callback_query_parameters.dart';

void main() {
  group('callbackQueryParameters', () {
    test('reads parameters from the hash-routed URI', () {
      final values = callbackQueryParameters(
        Uri.parse('/auth/callback?token_hash=hash123&type=recovery'),
      );
      expect(values, {
        'token_hash': ['hash123'],
        'type': ['recovery'],
      });
    });

    test('reads parameters before the browser fragment', () {
      final values = callbackQueryParameters(
        Uri.parse('/auth/callback'),
        browserUri: Uri.parse(
          'https://beta.example/?token_hash=hash123&type=signup#/auth/callback',
        ),
      );
      expect(values, {
        'token_hash': ['hash123'],
        'type': ['signup'],
      });
    });

    test('retains duplicate parameters so caller validation rejects them', () {
      final values = callbackQueryParameters(
        Uri.parse('/auth/callback?type=signup'),
        browserUri: Uri.parse(
          'https://beta.example/?token_hash=hash123&type=recovery#/auth/callback',
        ),
      );
      expect(values['type'], ['signup', 'recovery']);
    });
  });
}
