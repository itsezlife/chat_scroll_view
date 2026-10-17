import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:rich_clipboard/src/environment_specific/clipboard_transport.dart'
    as environment_specific;
import 'package:rich_clipboard/src/rich_text_html.dart';

/// The [RichClipboard] over the system clipboard: one item with the text's
/// plain text and its HTML ([RichTextHtml]).
///
/// A read takes the rich text from the clipboard's HTML, whichever app wrote
/// it, and the plain text from its plain text (from the HTML's text when
/// there is none). The platforms:
///
/// | Platform | Plain text | HTML |
/// | --- | --- | --- |
/// | Android | the clip's text | `ClipData.newHtmlText`, `getHtmlText` |
/// | iOS | `public.utf8-plain-text` | `public.html` |
/// | macOS | `NSPasteboard.PasteboardType.string` | `.html` |
/// | web | `text/plain` | `text/html` through `ClipboardItem`; plain only where the browser refuses |
/// | Windows | `CF_UNICODETEXT` | the registered `HTML Format` (CF_HTML) |
/// | Linux | `UTF8_STRING` | `text/html` |
///
/// Reading the clipboard is subject to the platform's own rules: iOS may ask
/// the user to allow a paste, and a browser may refuse a read it was not
/// given permission for.
final class SystemRichClipboard implements RichClipboard {
  /// Creates the adapter. It holds no state: the clipboard is the system's.
  const SystemRichClipboard();

  @override
  Future<void> write(RichText text) => environment_specific.$writeClipboard(
    plain: text.plain,
    html: RichTextHtml.encode(text),
  );

  @override
  Future<ClipboardText?> read() async => (await _read(media: false)).text;

  @override
  Future<ClipboardContents> readWithMedia() => _read(media: true);

  @override
  void Function() attach(RichClipboardField field) =>
      environment_specific.$listenClipboardEvents(
        onCopy: ({required cut}) {
          if (!field.hasFocus) return null;
          final text = cut ? field.cutSelection() : field.copySelection();
          if (text == null) return null;
          return (plain: text.plain, html: RichTextHtml.encode(text));
        },
        takesPaste: () => field.hasFocus,
        onPaste: (held) => field.paste(_contentsOf(held)),
      );

  Future<ClipboardContents> _read({required bool media}) async {
    final held = await environment_specific.$readClipboard(media: media);
    if (held == null) return ClipboardContents.empty;
    return _contentsOf(held);
  }

  // What the platform held, as the seam says it.
  static ClipboardContents _contentsOf(
    ({String? plain, String? html, List<Map<Object?, Object?>> media}) held,
  ) {
    final rich = switch (held.html) {
      final html? when html.trim().isNotEmpty => RichTextHtml.decode(html),
      _ => null,
    };
    final plain = held.plain ?? rich?.plain;
    return ClipboardContents(
      text: plain == null ? null : ClipboardText(plain, rich: rich),
      media: [for (final item in held.media) ?_mediaOf(item)],
    );
  }

  // A platform's description of one image or file.
  static PastedMedia? _mediaOf(Map<Object?, Object?> item) =>
      switch ((item['bytes'], item['path'], item['mimeType'])) {
        (final Uint8List bytes, _, final String mimeType)
            when bytes.isNotEmpty =>
          PastedMedia.bytes(
            bytes,
            mimeType: mimeType,
            name: item['name'] as String?,
          ),
        (_, final String path, final mimeType) when path.isNotEmpty =>
          PastedMedia.file(path, mimeType: mimeType as String?),
        _ => null,
      };
}
