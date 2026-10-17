import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Puts [plain] and [html] on the clipboard as one item, replacing what was
/// there. A browser without `ClipboardItem` gets the plain text alone.
Future<void> $writeClipboard({
  required String plain,
  required String html,
}) async {
  final clipboard = web.window.navigator.clipboard;
  try {
    final item = web.ClipboardItem(
      {
            'text/plain': web.Blob(
              [plain.toJS].toJS,
              web.BlobPropertyBag(type: 'text/plain'),
            ),
            'text/html': web.Blob(
              [html.toJS].toJS,
              web.BlobPropertyBag(type: 'text/html'),
            ),
          }.jsify()!
          as JSObject,
    );
    await clipboard.write([item].toJS).toDart;
  } on Object {
    await clipboard.writeText(plain).toDart;
  }
}

/// The clipboard's plain text and HTML, either null when absent; null when it
/// holds neither. A browser that refuses the rich read (a permission it was
/// not given, no `read`) gives the plain text alone.
Future<({String? plain, String? html})?> $readClipboard() async {
  final clipboard = web.window.navigator.clipboard;
  try {
    final items = (await clipboard.read().toDart).toDart;
    if (items.isEmpty) return null;
    final item = items.first;
    final types = item.types.toDart.map((type) => type.toDart).toSet();
    Future<String?> textOf(String type) async {
      if (!types.contains(type)) return null;
      final blob = await item.getType(type).toDart;
      return (await blob.text().toDart).toDart;
    }

    final plain = await textOf('text/plain');
    final html = await textOf('text/html');
    if (plain == null && html == null) return null;
    return (plain: plain, html: html);
  } on Object {
    final plain = (await clipboard.readText().toDart).toDart;
    return plain.isEmpty ? null : (plain: plain, html: null);
  }
}
