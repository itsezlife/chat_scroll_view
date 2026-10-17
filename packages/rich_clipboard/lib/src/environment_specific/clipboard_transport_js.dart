import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Puts [plain] and [html] on the clipboard as one item, replacing what was
/// there. A browser without `ClipboardItem` gets the plain text alone; a
/// browser that refuses the write (no user gesture, no focus) fails it.
Future<void> $writeClipboard({
  required String plain,
  required String html,
}) async {
  final clipboard = web.window.navigator.clipboard;
  if (!globalContext.has('ClipboardItem')) {
    await clipboard.writeText(plain).toDart;
    return;
  }
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
}

/// The clipboard's plain text and HTML, either null when absent, and with
/// [media] its images, each as `bytes` with its `mimeType` (a browser has no
/// files on the clipboard to give); null when it holds none of them.
///
/// A browser without `read` gives the plain text alone; a browser that
/// refuses the read (a permission the user did not give) fails it.
Future<({String? plain, String? html, List<Map<Object?, Object?>> media})?>
$readClipboard({required bool media}) async {
  final clipboard = web.window.navigator.clipboard;
  if (!(clipboard as JSObject).has('read')) {
    final plain = (await clipboard.readText().toDart).toDart;
    return plain.isEmpty
        ? null
        : (plain: plain, html: null, media: const <Map<Object?, Object?>>[]);
  }
  final items = (await clipboard.read().toDart).toDart;
  if (items.isEmpty) return null;
  Future<web.Blob?> blobOf(web.ClipboardItem item, String type) async =>
      item.types.toDart.any((held) => held.toDart == type)
      ? await item.getType(type).toDart
      : null;
  Future<String?> textOf(String type) async =>
      switch (await blobOf(items.first, type)) {
        final blob? => (await blob.text().toDart).toDart,
        null => null,
      };

  final plain = await textOf('text/plain');
  final html = await textOf('text/html');
  final images = <Map<Object?, Object?>>[];
  if (media) {
    for (final item in items) {
      for (final type in item.types.toDart.map((type) => type.toDart)) {
        if (!type.startsWith('image/')) continue;
        final blob = await item.getType(type).toDart;
        final buffer = await blob.arrayBuffer().toDart;
        images.add({'bytes': buffer.toDart.asUint8List(), 'mimeType': type});
      }
    }
  }
  if (plain == null && html == null && images.isEmpty) return null;
  return (plain: plain, html: html, media: images);
}
