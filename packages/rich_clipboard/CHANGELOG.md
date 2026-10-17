# Changelog

All notable changes to `rich_clipboard` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `SystemRichClipboard.attach`: on the web the browser's own copy, cut and
  paste of a focused text field (its keys and its menu) are taken over through
  their DOM events, whose data needs no permission: a copy puts the HTML next
  to the plain text, a paste reads it (and pasted files) back. Before, they
  carried plain text only, so custom emoji copied in the composer came back
  as plain emoji.

- `RichTextHtml`: the conversion between `RichText` and the HTML the
  clipboard carries (ADR 032). `encode` is lossless for every entity: the
  standard elements for styles, quotes and links, `<tg-spoiler>` for
  spoilers, and `data-` attributes for mentions and inline content. `decode`
  reads its own HTML exactly, other apps' HTML as far as entities can say it
  (elements, CSS weights, styles and decorations, block elements as lines,
  collapsed whitespace, followable links only), and the reference clients'
  `animated-emoji`, `spoiler`, `tg-spoiler` and `details`. A style over all of
  another app's text is dropped. It never throws.
- `SystemRichClipboard`: the `RichClipboard` over the system clipboard, one
  item with the plain text and the HTML. Native code for Android, iOS, macOS,
  Windows and Linux behind the `rich_clipboard` method channel; the web goes
  through `navigator.clipboard`. Windows and Linux are built in CI and not yet
  run on a device.
- Code blocks: written as `<pre>` / `<pre lang>`, read from `pre` with
  `lang`, `language`, `lng`, `data-language` or a `language-` class on its
  `code`. A `pre` is no longer read as inline code.
- `SystemRichClipboard.readWithMedia`: the text and the media in one
  platform read (one paste prompt on iOS); files a file manager copied, with
  no text, else image data. macOS: file URLs, else GIF, PNG, JPEG or TIFF as
  PNG. iOS: item images (GIF, PNG, JPEG, HEIC, WebP, or a `UIImage` as PNG)
  saved to temporary files off the main thread. Android: the clip's content
  URIs copied into the app cache under their names, off the main thread, as
  the reference client copies a pasted image; an image item's URI is not
  read as text. Windows: `CF_HDROP` paths, else the `PNG` format or `CF_DIB`
  as BMP. Linux: the URI list as paths, else the image as PNG. Web:
  `ClipboardItem` images.
- Decoding trusts `data-mention-id` and `data-content-key` only in HTML
  marked as this app's own: a page could otherwise put a mention over any
  name. This app's own links keep any scheme, or none; no link keeps
  `javascript`, `vbscript`, `data`, `file` or `blob`.
- Encoding and decoding take time linear in the size of the text.
- This app's own HTML is read from its marked element alone: Windows' HTML
  Format wraps a copy in a document with line breaks around the fragment,
  which came back as an empty line before and after the text (found by the
  contract run on Windows in CI).
- On the web, a browser without `ClipboardItem` or `read` falls back to plain
  text; a browser that refuses a write or a read fails it, rather than
  falling back silently.
