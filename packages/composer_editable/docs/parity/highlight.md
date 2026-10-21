---
type: Composer Selection Concept
title: Selection highlight (composer)
description: >-
  The selection highlight is the engine's boxes painted as one gapless shape by
  the editable itself, and the editable's painter slot is free for the host.
tags: [telegram, composer, highlight, composer_editable]
timestamp: 2026-10-18T12:00:00.000Z
content_hash: composer-highlight-v3
---

# Highlight

The boxes are stock and the paint is the editable's: `ExtendedRenderEditable`
fills the selected boxes as one shape, under the text, and the editable's
`painter` slot is free for a host. `selectionColor` is the selection color (none
without focus, as in stock), `selectionHeightStyle` and `selectionWidthStyle`
size the boxes (`BoxWidthStyle.max` by default on native platforms, so completed
lines span the full width, as in a platform edit field), and
`getBoxesForSelection` / `getEndpointsForSelection` are stock.

## Why one shape

Stock draws a rect per box, and a translucent highlight then seams between
lines. No `BoxHeightStyle` avoids it: the engine rounds each line's height, so
the boxes of a line end a fraction of a pixel (0.2 logical pixels at 16 px text
with a line height of 1.3) above the next line's top whichever style asks for
the line spacing, `max`, `strut` and the `includeLineSpacing*` styles included.
Boxes that do meet seam too: a shared edge is rarely on a device pixel, and the
two partial coverages of its pixel composite to less than the colour paints
elsewhere.

`selectionHighlightPath` returns one `Path` and bridges each gap narrower than
half a line between a box and the box under it, over the width the two share. A
path is filled as one coverage, so shared edges and overlaps paint once; the
bridge closes the engine's gap; a last line shorter than the one above keeps its
step; a break of half a line or more stays a break. The shape stops at the
editable's box, so a scrolled selection does not leak into the field's padding.
Mixed font sizes (a code span), right-to-left runs and inline atoms need no
case of their own: the bridge is geometric, per box, not a grouping of lines.

Plain rects, no rounded joins: the reference composer is a platform
`EditText`, whose highlight is `Layout.getSelectionPath`, a path of one rect per
line that abuts the next (line top to line bottom), drawn once. The message-bubble
helper paints glyph-bounded middle lines instead; that is a different surface
and not a reference here.

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

`selection_highlight.dart` (`selectionHighlightPath`), `render_editable.dart`
(`ExtendedRenderEditable`, the paint and the notifiers), `text_selection.dart`
(`ExtendedTextSelectionOverlay` listens to the notifiers).
