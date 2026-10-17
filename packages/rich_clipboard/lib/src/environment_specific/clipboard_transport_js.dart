import 'dart:async';
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

/// Takes over the browser's own copy, cut and paste of a focused text field
/// (its keys and its menu), which reach the page as events whose clipboard
/// data needs no permission. Returns the call that stops.
///
/// [onCopy] answers the plain text and HTML a copy (or with `cut`, a cut)
/// puts on the clipboard instead of the browser's, or null to let the
/// browser's go ahead. When [takesPaste], a paste is the app's: [onPaste] is
/// handed the plain text, HTML and files it carries.
void Function() $listenClipboardEvents({
  required ({String plain, String html})? Function({required bool cut}) onCopy,
  required bool Function() takesPaste,
  required void Function(
    ({String? plain, String? html, List<Map<Object?, Object?>> media}) held,
  )
  onPaste,
}) {
  void copied(web.Event event, {required bool cut}) {
    if (event case final web.ClipboardEvent clipboardEvent) {
      final data = clipboardEvent.clipboardData;
      if (data == null) return;
      final copy = onCopy(cut: cut);
      if (copy == null) return;
      data
        ..setData('text/plain', copy.plain)
        ..setData('text/html', copy.html);
      event.preventDefault();
    }
  }

  void pasted(web.Event event) {
    if (event case final web.ClipboardEvent clipboardEvent) {
      final data = clipboardEvent.clipboardData;
      if (data == null || !takesPaste()) return;
      event.preventDefault();
      // The data is readable only while the event is dispatched; the files'
      // contents are read after.
      String? textOf(String type) => switch (data.getData(type)) {
        '' => null,
        final text => text,
      };
      final plain = textOf('text/plain');
      final html = textOf('text/html');
      final files = [
        for (var i = 0; i < data.files.length; i++) ?data.files.item(i),
      ];
      unawaited(() async {
        final media = <Map<Object?, Object?>>[
          for (final file in files)
            {
              'bytes': (await file.arrayBuffer().toDart).toDart.asUint8List(),
              'mimeType': file.type.isEmpty
                  ? 'application/octet-stream'
                  : file.type,
              'name': file.name,
            },
        ];
        onPaste((plain: plain, html: html, media: media));
      }());
    }
  }

  final onCopyEvent = ((web.Event event) => copied(event, cut: false)).toJS;
  final onCutEvent = ((web.Event event) => copied(event, cut: true)).toJS;
  final onPasteEvent = pasted.toJS;
  final document = web.document
    ..addEventListener('copy', onCopyEvent, true.toJS)
    ..addEventListener('cut', onCutEvent, true.toJS)
    ..addEventListener('paste', onPasteEvent, true.toJS);
  return () {
    document
      ..removeEventListener('copy', onCopyEvent, true.toJS)
      ..removeEventListener('cut', onCutEvent, true.toJS)
      ..removeEventListener('paste', onPasteEvent, true.toJS);
  };
}
