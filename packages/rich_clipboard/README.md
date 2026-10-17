# rich_clipboard

The `RichClipboard` adapter from `content_model` ([ADR 032](../../docs/adr/032-rich-clipboard.md)):
rich text on the system clipboard as plain text, which any app pastes, and
HTML, which keeps every entity for a paste into the app and gives other apps
the formatting they understand.

It holds platform code, so only the host depends on it: packages are handed
the `RichClipboard` seam (`scripts/check` enforces this).

## Types

| Type | Role |
| --- | --- |
| `SystemRichClipboard` | The adapter: one clipboard item with the text's plain text and its HTML. |
| `RichTextHtml` | The HTML codec: `encode` a `RichText` losslessly, `decode` this app's HTML and other apps'. |

## Platforms

| Platform | Plain text | HTML | Verified |
| --- | --- | --- | --- |
| Android | the clip's text | `ClipData.newHtmlText` (read off the main thread) | contract on a device |
| iOS | `public.utf8-plain-text` | `public.html` (one `items` read per paste, one paste prompt) | contract on the simulator |
| macOS | `.string` | `.html` | contract on the real pasteboard |
| web | `text/plain` | `text/html` through `ClipboardItem`; plain where the browser has no `ClipboardItem` or `read` | not yet run |
| Windows | `CF_UNICODETEXT` | `HTML Format` (CF_HTML) | built in CI, not run on a device |
| Linux | GTK text targets | `text/html` (UTF-16 HTML read too) | built in CI, not run on a device |

Media (`readWithMedia`, one read with the text): files a file manager
copied, with no text (their text is their names), else image data. macOS
file URLs or GIF / PNG / JPEG / TIFF (as PNG), checked on the real
pasteboard; iOS item images saved to temporary files; Android content URIs
copied into the app cache, as the reference client copies a pasted image;
Windows `CF_HDROP`, `PNG` or `CF_DIB` (as BMP); Linux URI lists or the GTK
image (as PNG); web `ClipboardItem` images. Saved files live in the system's
temporary or cache directory, which the system clears.

On the web, Flutter leaves a text field's clipboard keys to the browser, so
Ctrl/Cmd+V is the browser's plain paste; the menu's Paste reads through
`navigator.clipboard`, which the browser may ask permission for.

The contract runs on a device from the example:
`flutter test integration_test/rich_clipboard_test.dart -d <device>`. On
Android that uninstalls the example afterwards, data included.

## HTML

| Entity | Written | Also read |
| --- | --- | --- |
| bold, italic, underline, strike | `<b> <i> <u> <s>` | `strong h1-h6`, `em`, `ins`, `strike del`; CSS `font-weight`, `font-style`, `text-decoration` (also switching a style off) |
| spoiler | `<tg-spoiler>` | `<spoiler>`, `class="tg-spoiler"` |
| code | `<code>` | `tt kbd samp` |
| code block | `<pre>`, `<pre lang>` | `pre` with `lang`, `language`, `lng`, `data-language` or a `language-` class on its `code` |
| quote | `<blockquote>` | `<details>` |
| link | `<a href>` | its own: any scheme; other apps': `http https mailto tel tg ftp` only; never `javascript vbscript data file blob` |
| mention | `<span data-mention-id>` | in its own HTML only |
| inline content | `<span data-content-key>` over the alternative text | in its own HTML only; `<animated-emoji data-document-id>` as a document key from anyone |

Line breaks are `<br>`; other apps' block elements start and end lines and
their whitespace collapses as a browser collapses it. A style that covers all
of another app's text is dropped. Decoding never throws.

## Host contract

| The host | ADR |
| --- | --- |
| Wires one adapter and hands the `RichClipboard` seam to the composer and its own copy actions | [032](../../docs/adr/032-rich-clipboard.md), [031](../../docs/adr/031-localization-accessibility-and-input.md) |
| Resolves inline content keys a paste brings in that it cannot describe | [032](../../docs/adr/032-rich-clipboard.md), [023](../../docs/adr/023-data-layering-and-persistence.md) |
| Checks a pasted mention's id against who can be mentioned before sending: any page can mark its HTML as this app's own | [032](../../docs/adr/032-rich-clipboard.md) |
