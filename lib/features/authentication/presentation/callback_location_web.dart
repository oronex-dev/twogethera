import 'dart:js_interop';

@JS('history.replaceState')
external void _replaceState(JSAny? data, String title, String url);
@JS('location.pathname')
external String get _pathname;
@JS('location.href')
external String get _href;

/// Replace the current entry before verification; no credential is retained in
/// this entry's query or fragment. This is not erasure of external mail history.
void scrubCallbackLocation(String destination) =>
    _replaceState(null, '', '$_pathname#$destination');

/// Full browser address, needed because a redirect can place its query before
/// the hash route. The caller uses only callback parameters and scrubs it
/// before making any verification request.
Uri? readCallbackBrowserUri() => Uri.tryParse(_href);
