# Divergences from Flutter SDK

## Vendored from

```
Flutter 3.41.7 • channel stable
Framework revision 90673a4eef (2026-02-18)
```

## Intentional changes (vs stock)

- Class renames: `TextField` → `ExtendedTextField`, `EditableText` →
  `ExtendedEditableText`, `EditableTextState` → `ExtendedEditableTextState`,
  `EditableTextContextMenuBuilder` → `ExtendedEditableTextContextMenuBuilder`.
- Selection gesture builder renamed to
  `ExtendedTextSelectionGestureDetectorBuilder` (+ Delegate) to avoid clashing
  with `package:flutter/widgets.dart` when both are imported.
- Imports rewritten to `package:flutter/src/...` for private Flutter pieces;
  local copies of `editable_text.dart`, `text_selection.dart`, and web-browser
  detection helpers.
- `TextEditingController` / `ToolbarOptions` /
  `ContentInsertionConfiguration` / `kDefaultContentInsertionMimeTypes` are
  **imported from stock** Flutter `editable_text.dart` (not duplicated), so
  they stay compatible with `RestorableTextEditingController` and the rest of
  the framework.
- Default context menu / spell-check suggestion chrome uses
  `AdaptiveTextSelectionToolbar.buttonItems` instead of
  `*.editableText(editableTextState: …)` APIs that require stock
  `EditableTextState`.
- Platform selection handle controls are **vendored locally**:
  - `lib/src/material/text_selection.dart`
  - `lib/src/material/desktop_text_selection.dart`
  - `lib/src/cupertino/text_selection.dart`
  - `lib/src/cupertino/desktop_text_selection.dart`  
    so `materialTextSelectionHandleControls` / Cupertino equivalents extend the
    local `TextSelectionControls` + `TextSelectionHandleControls` mixin.

## Bugfixes / behavior changes

### Scroll hide/show toolbar lifecycle (`ExtendedEditableText`)

Stock Flutter remounts the selection toolbar on scroll (`hideToolbar` on
`ScrollStart`, `showToolbar` on `ScrollEnd` via a post-frame callback). That
causes:

1. **flutter/flutter#185052** — post-frame show often never runs after a
   non-fling scroll (no frame scheduled when semantics are off).
2. **Custom menu state loss** — remounting drops swipe-back page / local
   controller state in app context menus.
3. **`scheduleFrame()` during an active frame** — naive workarounds throw
   `FlutterError: Build scheduled during frame`.

`ExtendedEditableText` instead **fades** the still-mounted toolbar via
`TextSelectionOverlay.suppressToolbarForScroll` (drives the existing
`toolbarVisible` opacity animation). On `ScrollEnd` it unsuppresses and calls
`updateForScroll()` so viewport flags restore visibility when the selection is
on-screen. No remount, no post-frame show, no `scheduleFrame`.

Toolbar visibility also treats a selection as on-screen when **any** selection
box overlaps the editable (not only when a selection endpoint is in view), so
select-all on tall text does not fade the menu out.

Because the faded toolbar stays mounted, and `Opacity` keeps its hit-test box at
any alpha, the wrapper drops the toolbar out of hit testing while the fade reads
zero — otherwise an invisible menu keeps swallowing gestures (scrolls included)
aimed at the content under it. The test reads the animation at hit-test time:
the visibility that drives the fade can change during paint, so the subtree must
not rebuild for it.

### Caret reveal (`ExtendedEditableText`)

`contentScrollPadding` insets the scrolled text inside the editable instead of
around it, so revealing a caret targets the line **plus** the inset band — an
edge line otherwise settles flush against the bounds. The band is dropped when
it and the line together outgrow the text area.

Ancestor scrollables are asked to reveal a rect clipped to the editable's own
box. Stock hands them the selection edge in editable coordinates, which for a
selection that reaches far outside the visible text (select-all over long text)
is thousands of pixels away — a page scrollable then scrolls to that point,
far past the field. The editable scrolls to the edge itself; ancestors only
have to keep the resulting line on screen.

### Nested overscroll handoff (`ExtendedEditableText`)

A multiline field inside a page `Scrollable` claims the vertical drag once it
can scroll. Outward motion at `0` / `maxScrollExtent` would otherwise be
discarded as empty overscroll (this fork also keeps `overscroll: false`, so
there is no glow).

With `delegateOverscrollToParent` (default on), the field uses an
`OverscrollHandoffScrollPosition`: unused edge `applyUserOffset` and
`goBallistic` go to the nearest same-axis ancestor, so the page keeps both
drag delta and fling velocity. Multiline fields force `ClampingScrollPhysics`
while this is on so bounce cannot move past the bound before handoff. Opt out
per field when nested page scroll is wrong for the surface.

### Selection width: hybrid

Stock `EditableText.defaultSelectionWidthStyle` is `BoxWidthStyle.max` on
non-web platforms, which extends the content end line to the full layout width.
Hybrid selection highlight instead uses full-width rects only on completed lines
and a glyph-tight rect on the content end line (see `CONTEXT.md`).

`ExtendedEditableText` disables the built-in highlight (`selectionColor: null`)
and paints via [HybridSelectionHighlightPainter] /
[computeHybridSelectionBoxes]:

- Completed lines: `BoxWidthStyle.max` (including empty newline gaps).
- Content end line (`selection.end - 1`): `BoxWidthStyle.tight`, unless an
  exclusive end uses empty-edge (below).

Soft-wrap and hard-break exclusive ends (`selection.end` at the start of the
next visual line) branch on **exclusive-end affinity** (must be plumbed through
handle drag — stock `TextSelection(...)` defaults to `downstream`). Flutter’s
`TextSelection.==` ignores affinity when non-collapsed, so affinity-only updates
are forced through the controller, `userUpdateTextEditingValue`, and
`ExtendedRenderEditable.selection`.

- `TextAffinity.upstream`: content end line **tight**; end handle at the last
  glyph on that line (empty trailing space does not pull the handle down).
- `TextAffinity.downstream`: content end line **max**; end handle empty-edge on
  the following line (`downstream` caret at `selection.end`). Soft-wrap max is
  expanded to layout width (engine `BoxWidthStyle.max` alone does not fill soft
  wraps the way hard breaks do).

When either handle drag leaves the exclusive end (`selection.end`) as the
**fixed base** (`extent <= fixedBase` and that offset is an exclusive line end),
affinity is **preserved** from drag-start (not overwritten by the moving
finger’s hit-test, and not forced to empty-edge merely because the selection is
reversed). A fixed start that merely sits at a visual line start does **not**
freeze affinity (`fixedExcl != null` alone is insufficient — that was the
false-preserve bug when dragging past a hard/soft line start toward a soft-wrap
exclusive end). When the exclusive end is the **moving extent**, hit-test
affinity updates exclusive-end mode (or a new enter does).

**Content-less exclusive end** (selection paints no glyphs on the content end
line — typically hard-break covering only the omitted `\n`): synthesize a
trailing box on that line (upstream tight at last glyph; downstream max to
layout width). Never leave hybrid boxes empty for a non-collapsed exclusive end.

Hard breaks omit the `\n` from the painted range so the engine does not emit a
leading box on the following line. Prior completed lines stay `max`.

Hybrid boxes are taken from the live `RenderEditable` layout by temporarily
swapping `selectionWidthStyle` outside paint. The **paint selection cache**
stores hybrid results only for the editable’s current `selection` (offsets +
affinity). Other `getBoxesForSelection` ranges (magnifier, line probes) compute
**ephemeral hybrid boxes** and must not overwrite that cache. Content-less
synthesize is scoped to the range being computed. Style must not be mutated
during paint (`debugDoingPaint`).

### Bidirectional selection handles

Stock Flutter on Android/desktop refuses to let a selection handle cross the
other (`Don't allow order swapping` in `TextSelectionGestureDetectorBuilder`).
Dragging is therefore unidirectional: you can only extend in the direction you
started.

Apple platforms already invert: the dragged handle becomes the extent and the
opposite end is anchored from `_dragStartSelection`.

`extended_text` uses that invert model on **all** platforms so both handles can
grow the selection either way (same idea as `MarkdownSelectable`).

While resizing a non-collapsed selection, the moving extent is nudged away from
the fixed base when they would coincide (`_avoidCollapseExtent`, same idea as
`_MarkdownSelectable._avoidCollapse`) so the selection never collapses to a
caret mid-drag. The nudge **bounces back** to the side the extent came from;
crossing past the other handle still works when the pointer moves beyond the
fixed offset (not while resting exactly on it).

### Handle + magnifier motion

Parity target: Telegram Android **composer** (AOSP Editor) — see
`.okf/telegram/composer-selection/`, not bubble `TextSelectionHelper` and not
stock Flutter / iOS system loupe.

**Handles**

- Appear: ~250ms fade + scale with Android `OvershootInterpolator` (tension
  2.0) around the handle center (`handleViewProgress`).
- Hide: **instant** (`_controller.value = 0` on clear — no reverse animation).
- Move: finger-tracked overlay on touch (fixed handle caret-anchored); ~250ms
  easeOut settle on release.
- Drag scale: **~1.2** on grabbed handle while drag in progress (Telegram
  composer); ~250ms easeOut; independent of finger-tracked delta.
- Geometry: Material circle+stem at 22dp. Editor (`MarkdownTextField`) forces
  `materialTextSelectionHandleControls` on all platforms so iOS does not use
  Cupertino bars.

**Magnifier**

- Shown while a handle is dragged. **Suppressed during one-touch long-press**
  (`_isOneTouchSelection`) until pointer up.
- Always tracks the **dragged** end (`selection.extent` under the invert model).
- Material `TextMagnifier` clamps loupe X to the current line.
- Focal X = finger X clamped to line bounds; focal Y =
  `lineTop + 0.5 * lineHeight`.
- During direction settling (selection frozen), magnifier still updates with the
  gesture so the loupe keeps following the finger.
- `MagnifierInfo` is time-smoothed toward the latest target (X settle ~100ms,
  Y ~200ms). Clock: `currentSystemFrameTimeStamp` (not `currentFrameTimeStamp`).

**Gestures**

- After long-press word select, **direction settling** ignores handle extents
  inside the initial word until the pointer exits
  (`beginDirectionSettling` / `_extentForHandleDrag`). Settling is cleared when
  the user explicitly grabs a start/end handle.
- Letter/digit/`_` **run snap is not applied during live handle drag** — it
  oscillates against character-precise finger tracking and `_avoidCollapseExtent`.
  Helpers remain in `selection_drag_snap.dart` for tests / future use.

See `selection_handle_motion.dart`, `selection_drag_snap.dart`, and
`.okf/telegram/composer-selection/`.
