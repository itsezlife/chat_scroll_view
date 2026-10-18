# ADR 032: Rich clipboard

A copy puts two forms of one rich text on the system clipboard, plain text and
HTML that keeps every entity; a paste into the app reads the HTML back. The
seam lives in `content_model`, the platform code in an adapter package, and
every copy and paste surface goes through the seam.

**Status**: Accepted
**Date**: 2026-10-17
**Amended**: 2026-10-18 — the paste drop order gains list items beside quotes and code blocks; plain text stays plain; the apply-formatting offer after a plain paste is a host affordance over the composer's paste report (row changed: Paste; triggers: [ADR 026](026-composer-model.md) Amendment, list items in [ADR 034](034-rich-text-wire-and-persistence.md))  
**Relates to**: [ADR 020](020-package-topology.md), [ADR 023](023-data-layering-and-persistence.md), [ADR 026](026-composer-model.md), [ADR 030](030-testing-policy.md), [ADR 031](031-localization-accessibility-and-input.md)

## Context

Every copy wrote plain text and the composer pasted plain text, so formatting,
links, mentions, spoilers, quotes and custom emoji did not survive a copy
inside the app. The three reference clients all put more than one form on the
clipboard: plain text for any app, and a rich form their own input reads back
(Android: `text/html` with `<animated-emoji data-document-id>`; iOS: a private
JSON type plus RTF; desktop: private field text and tags plus `text/html`).
The research, with file references into the checkouts, is in
`.scratch/rich-clipboard/research.md`.

## Decided

| Concern | Decision |
| ------- | -------- |
| Seam | `RichClipboard` in `content_model`: `write(RichText)`, `read()` → `ClipboardText` (the plain text, plus the `RichText` when the clipboard held a rich form; null for no text). `FakeRichClipboard` and `RichClipboardContract` in `testing.dart`. |
| Rich channel | HTML, on every platform. Android has no other text channel for custom data, the web clipboard takes only `text/plain` and `text/html` without a permission prompt, and HTML is what browsers and editors put on the clipboard. One channel means one codec. |
| Codec | `RichTextHtml` in the adapter package, lossless for every entity: standard elements for styles, quotes, links and lists (`ul` / `ol` / `li`, nested a level per depth); links to the `username:` and `hashtag:` schemes for detected usernames and hashtags; `data-` attributes for mentions and inline content, which other apps read as text. It also reads web HTML (elements, lists and CSS weights and styles) and the reference clients' tags (`animated-emoji`, `spoiler`, `tg-spoiler`, `details`). A style covering the whole of another app's text is dropped. Parsing uses `package:html`: tolerant parsing of real web HTML is a domain of its own. Encoding and decoding are linear in the text. |
| Trust | Mention ids, content keys, usernames and hashtags are read only from HTML marked as the app's own, and only links from it keep any scheme: a page could put a mention over any name. The mark is a claim any page can make, so the host checks a mention's id before sending, and no link keeps a scheme that runs code or carries a document (`javascript`, `vbscript`, `data`, `file`, `blob`). The reference clients' custom emoji tag is read from anyone, as they read it. |
| Plain text | `RichText.plain`: inline content as its alternative text, links as their visible text, spoilers revealed, no markup, hidden link URLs not appended (the mobile clients' rule). |
| Adapter | `packages/rich_clipboard`, the workspace's first Flutter plugin package: macOS and iOS (`public.html`), Android (`ClipData.newHtmlText`), web (`ClipboardItem`), Windows (`HTML Format`), Linux (GTK `text/html`). The dependency lint keeps it out of every package that only needs the seam. |
| Paste | Rich when the clipboard has it, else plain; "paste as plain text" always plain. Quotes pasted inside a quote are unwrapped. Entities that do not fit are dropped the broadest first (code blocks, quotes and list items, then styles, then links), the text always going in. Plain text stays plain: a paste that finds no rich form is never reinterpreted as markdown by the composer. The composer reports each paste (range, text, whether it was rich) through its interaction seam; a host may show an "apply formatting" offer after a plain paste whose text has markdown structure (`RichTextMarkdown.decode(text) != RichText.plain(text)`), dismissed by any edit and never blocking the paste, and applies it by replacing the pasted range with the decoded text. The offer is feedback UI and stays app-side. A paste whose text changed while the clipboard was read lands nowhere. A custom emoji the host cannot describe is inserted bare and resolved later. On the web, Flutter leaves a field's clipboard keys to the browser; `RichClipboard.attach` takes the browser's copy, cut and paste over through their DOM events, whose data needs no permission, and the app's menu reads through `navigator.clipboard`. |
| Media | `RichClipboard.readWithMedia()` gives the text and `PastedMedia` in one read, so iOS asks once per paste: image data with its type, or a file's path (a file copied in a file manager is not loaded whole, and comes without its names as text). The mobile adapters save images to files off the main thread, as the reference Android client does, rather than send them whole through the channel. A paste that finds media and a host that takes it (`ComposerController.onPastedMedia`) hands the media over and inserts no text, as the reference clients send pasted media; when the host does not send it, the text that came with it is pasted, as the reference desktop client does (an office app's range comes with a picture of it). A paste as plain text leaves media alone. A keyboard's inserted image takes the same path. |
| Surfaces | Composer copy, cut and paste; message Copy (one or several); the selection bar; text-selection Copy (the viewport hands the copy to the host); the emoji panel's Copy on a custom emoji; code-block Copy. Presentation packages are handed the seam and never reach a platform channel ([ADR 031](031-localization-accessibility-and-input.md)). A copy is confirmed (`ChatCopied`) once written; a failed write is reported and confirms nothing. |

## Consequences

- One rich channel cannot carry what HTML cannot say losslessly to other apps:
  a mention or custom emoji pasted into another app is its text.
- Pasting from another Telegram client keeps what that client put in HTML;
  the iOS private type and the desktop field tags are not read.
- Windows and Linux are built in CI but not run on a device until someone
  does.
