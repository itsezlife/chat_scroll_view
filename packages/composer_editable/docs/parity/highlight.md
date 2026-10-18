---
type: Composer Selection Concept
title: Selection highlight (composer)
description: >-
  The selection highlight is the engine's: Flutter paints the selected boxes
  with the editable's selection width style, and the editable's painter slot is
  free for the host.
tags: [telegram, composer, highlight, composer_editable]
timestamp: 2026-10-18T12:00:00.000Z
content_hash: composer-highlight-v2
---

# Highlight

The highlight is stock `RenderEditable` paint. `selectionColor` is the
selection color, `selectionWidthStyle` defaults to `BoxWidthStyle.max` on
native platforms (completed lines span the full width, as in a platform edit
field), and `getBoxesForSelection` / `getEndpointsForSelection` are stock.
`ExtendedRenderEditable.painter` is not used by the package, so a host may set
one.

Why stock: the composer in Telegram Android is a platform `EditText`, so its
highlight is the platform's `Layout.getSelectionPath`, which fills a completed
line to the edge. The message-bubble helper paints glyph-bounded middle lines
instead; that is a different surface and not a reference here. A package-owned
highlight would also need to swap `selectionWidthStyle` on the render object and
write to its visibility notifiers, which is coupling to `RenderEditable`
internals for a look the platform does not have.

## Handle and toolbar visibility

`ExtendedRenderEditable` publishes three notifiers at the end of each paint,
where reading its size is legal in every build mode:

| Notifier | True when |
| -------- | --------- |
| `startHandleInViewport` | any part of the start caret is inside the text area |
| `endHandleInViewport` | any part of the end caret is inside the text area |
| `selectionIntersectsViewport` | either handle is visible, or a selection box overlaps the text area |

The first two widen stock `selectionStartInViewport` / `selectionEndInViewport`
(stock asks only about the top edge of the caret, so a handle on a line that is
cropped at the top would hide). The third keeps the toolbar for a select-all
over text taller than the field, where both ends are off screen and the middle
is not.

## Code map

`render_editable.dart` (`ExtendedRenderEditable`), `text_selection.dart`
(`ExtendedTextSelectionOverlay` listens to the notifiers).
