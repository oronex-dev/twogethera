import 'dart:js_interop';

@JS('history.replaceState')
external void _replaceState(JSAny? data, String title, String url);
@JS('location.pathname')
external String get _pathname;

/// Replace the current entry before verification; no credential is retained in
/// this entry's query or fragment. This is not erasure of external mail history.
void scrubCallbackLocation(String destination) =>
    _replaceState(null, '', '$_pathname#$destination');
