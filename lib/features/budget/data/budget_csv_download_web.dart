import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool downloadBudgetCsv(String filename, String contents) {
  final body = web.document.body;
  if (body == null) return false;
  final blob = web.Blob(
    [('\uFEFF$contents').toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  body.append(link);
  link.click();
  link.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
