# ADR 032: Rich clipboard

A copy puts two forms of one rich text on the system clipboard, plain text and
HTML that keeps every entity; a paste into the app reads the HTML back. The
seam lives in `content_model`, the platform code in an adapter package, and
every copy and paste surface goes through the seam.

**Status**: Accepted
**Date**: 2026-10-17
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
| Codec | `RichTextHtml` in the adapter package, lossless for every entity: standard elements for styles, quotes and links; `data-` attributes for mentions and inline content, which other apps read as text. It also reads web HTML (elements and CSS weights and styles) and the reference clients' tags (`animated-emoji`, `spoiler`, `tg-spoiler`, `details`). A style covering the whole of another app's text is dropped. Parsing uses `package:html`: tolerant parsing of real web HTML is a domain of its own. |
| Plain text | `RichText.plain`: inline content as its alternative text, links as their visible text, spoilers revealed, no markup, hidden link URLs not appended (the mobile clients' rule). |
| Adapter | `packages/rich_clipboard`, the workspace's first Flutter plugin package: macOS and iOS (`public.html`), Android (`ClipData.newHtmlText`), web (`ClipboardItem`), Windows (`HTML Format`), Linux (GTK `text/html`). The dependency lint keeps it out of every package that only needs the seam. |
| Paste | Rich when the clipboard has it, else plain; "paste as plain text" always plain. Quotes pasted inside a quote are unwrapped. Entities that do not fit fall back to plain text. A custom emoji the host cannot describe is inserted bare and resolved later. |
| Surfaces | Composer copy, cut and paste; message Copy (one or several); the selection bar; text-selection Copy (the viewport hands the copy to the host); the emoji panel's Copy on a custom emoji; code-block Copy. Presentation packages are handed the seam and never reach a platform channel ([ADR 031](031-localization-accessibility-and-input.md)). |

## Consequences

- One rich channel cannot carry what HTML cannot say losslessly to other apps:
  a mention or custom emoji pasted into another app is its text.
- Pasting from another Telegram client keeps what that client put in HTML;
  the iOS private type and the desktop field tags are not read.
- Windows and Linux are built in CI but not run on a device until someone
  does.
