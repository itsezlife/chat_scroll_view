# Changelog

All notable changes to `rich_clipboard` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

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
