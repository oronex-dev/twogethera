import 'dart:convert';
import 'dart:js_interop';

@JS('localStorage')
external _Storage get _local;
@JS('sessionStorage')
external _Storage get _session;
@JS('document.cookie')
external String get _cookies;
@JS('indexedDB.databases')
external JSPromise<JSAny?> _databases();
@JS('JSON.stringify')
external String _stringify(JSAny? value);

extension type _Storage(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
}

Future<String> persistenceSnapshot() async {
  Map<String, String?> entries(_Storage storage) => {
    for (var i = 0; i < storage.length; i++)
      storage.key(i)!: storage.getItem(storage.key(i)!),
  };
  return jsonEncode({
    'local': entries(_local),
    'session': entries(_session),
    'cookies': _cookies,
    'indexedDB': _stringify(await _databases().toDart),
  });
}

@JS('location.href')
external String get _href;
bool locationOmits(String sensitive) => !_href.contains(sensitive);
