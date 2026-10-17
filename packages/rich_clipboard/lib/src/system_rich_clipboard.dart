import 'package:content_model/content_model.dart';
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
  Future<ClipboardText?> read() async {
    final held = await environment_specific.$readClipboard();
    if (held == null) return null;
    final rich = switch (held.html) {
      final html? when html.trim().isNotEmpty => RichTextHtml.decode(html),
      _ => null,
    };
    final plain = held.plain ?? rich?.plain;
    if (plain == null) return null;
    return ClipboardText(plain, rich: rich);
  }
}
