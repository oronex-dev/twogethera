import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/supabase_runtime_config.dart';
import '../application/auth_controller.dart';
import 'callback_location.dart';
import 'callback_query_parameters.dart';

final callbackLocationScrubberProvider = Provider<void Function(String)>(
  (ref) => scrubCallbackLocation,
);
final callbackBrowserUriProvider = Provider<Uri?>(
  (ref) => readCallbackBrowserUri(),
);

/// Local hash-link ingress only. PKCE codes, implicit access tokens and OS mail
/// association are deliberately not advertised as supported capabilities.
class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key, required this.uri});
  final Uri uri;
  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consume());
  }

  Future<void> _consume() async {
    if (!mounted) return;
    final parameters = callbackQueryParameters(
      widget.uri,
      browserUri: ref.read(callbackBrowserUriProvider),
    );
    final recovery = parameters['type']?.singleOrNull == 'recovery';
    final target = recovery ? '/auth/recovery' : '/auth/verify';
    // Do not send anything until the address has been replaced. Unsupported
    // input also takes this path and fails with the same sanitized link error.
    ref.read(callbackLocationScrubberProvider)(target);
    final config = ref.read(supabaseRuntimeConfigProvider);
    final hash = parameters['token_hash']?.singleOrNull;
    final type = parameters['type']?.singleOrNull;
    final supported =
        parameters.length == 2 &&
        hash != null &&
        RegExp(r'^(?:pkce_)?[a-fA-F0-9]{40,128}$').hasMatch(hash) &&
        (type == 'signup' || type == 'recovery') &&
        widget.uri.fragment.isEmpty;
    final link = supported && config != null
        ? config.endpoint
              .replace(
                path: '/auth/v1/verify',
                queryParameters: {'token_hash': hash, 'type': type},
              )
              .toString()
        : '';
    final controller = ref.read(authControllerProvider.notifier);
    await controller.clearLocalSession();
    if (!mounted) return;
    // Loading starts synchronously, preventing an old account redirect.
    final pending = controller.verifyLink(link, recovery: recovery);
    context.go(target);
    await pending;
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: CircularProgressIndicator(
        semanticsLabel: 'Checking your email link',
      ),
    ),
  );
}
