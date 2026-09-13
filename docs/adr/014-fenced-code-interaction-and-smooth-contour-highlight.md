# ADR 014: Fenced code interaction, cursor resolution, and smooth tap highlight

**Status**: Accepted (amended 2026-09-13 — §4 press-lifecycle)  
**Date**: 2026-09-13  
**Deciders**: Maintainer, Agent  
**Consulted**: Telegram Android (`TMessagesProj/ChatMessageCell.java`, `LinkSpanDrawable.java`), Telegram Desktop (`tdesktop/iv_markdown_article_paint.cpp`)  
**Related ADRs**: [ADR 012](012-cross-platform-selection-policies.md), [ADR 013](013-viewport-owns-markdown-text-selection.md), [ADR 015](015-per-body-scope-owns-continuous-text-gestures.md)

## Context

Chat messages frequently contain code blocks, inline monospace snippets,
hyperlinks, and user mentions. In Telegram Android and Telegram Desktop, these
elements exhibit distinct interaction zones, platform-specific chrome, hover
feedback, and tactile press animations that diverge from simple rectangular
widgets or uniform click-to-copy handlers:

1. **Fenced Code Blocks**:
   - On **desktop**, a fenced code block has a top header bar with the language
     name and a copy button. Hovering anywhere over the header presents the
     `SystemMouseCursors.click` hand cursor; clicking it copies the code to the
     clipboard. The code body beneath it is ordinary selectable text with the
     `SystemMouseCursors.text` I-beam cursor, supporting standard character and
     word selection.
   - On **mobile**, the top language banner is informative text (non-tappable).
     Snippets with $\ge 75$ characters display a bottom `"COPY CODE"` bar.
2. **Inline Code Spans**:
   - Inline monospace spans are click-to-copy on all platforms and show the
     `SystemMouseCursors.click` cursor on hover.
3. **Press / Tap Highlight Effect**:
   - Pressing an inline link, inline code snippet, or mention does not wait for
     release to show feedback. Ink arms on pointer **down**, holds while
     pressed, and fades on **up** / cancel (`LinkSpanDrawable` press tracking).
     Short tap and long-press share that lifecycle; host long-press actions are
     separate from paint.
   - Telegram uses smooth contour rounding for multiline text highlights
     (`LinkPath.java` / `LinkSpanDrawable.java`), avoiding jagged, stepped
     rectangles.

## Decision

We adopt a four-part architecture separating markdown rendering, chat chrome,
and gesture feedback:

### 1. Fenced Code Block Separation (`ChatCodeBlockPainter`)
Fenced code blocks are rendered in `chat_scroll_view` via
`MarkdownThemeData.builder` using a custom `ChatCodeBlockPainter` implementing
`SelectableTextBlock`:
- Measures and paints the top header bar (and optional mobile bottom bar).
- Offsets the code body's text selection coordinates by setting:
  `selectionOrigin = Offset(padding, headerHeight + padding)`.
- Carets, bounding boxes, and drag selection inside the code body remain
  100% pixel-accurate with zero offset drift.
- Hovering over the header reports `isLinkAtLocal == true` $\rightarrow$
  `SystemMouseCursors.click`. Hovering over the body reports `false` $\rightarrow$
  `SystemMouseCursors.text`.
- In `ChatTextSelection.inlineHitAt`, taps inside the header resolve to
  `ChatInlineHit.code` (click-to-copy); taps inside the code body resolve to
  `null` (delegating to text selection and handle interaction).

### 2. Desktop vs Mobile Platform Policy
Platform differences are governed by `ChatSelectionPolicy` (ADR 012):
- **Desktop Strategy (`$Desktop`)**: Header bar contains the language label and
  trailing copy icon; clicking the header triggers copy.
- **Mobile Strategy (`$Mobile`)**: Top language label is non-tappable. Code
  blocks with $\ge 75$ characters display a bottom copy strip.

### 3. Smooth Text Contour (`ChatSmoothContour`)
We implement the vector-arc rounding algorithm in pure Dart inside
`chat_scroll_view`:
- Takes a list of line bounding boxes (`List<Rect>`).
- Traverses the perimeter clockwise using a 2D vertex coordinate table,
  eliminating collinear points and aligning step transitions.
- Computes tangent unit vectors at each vertex and evaluates the 2D cross-product
  to determine the arc turn direction (`arcToPoint`) with a clamped radius
  $r = 4\text{–}6\text{ dp}$.
- Outputs a single, closed, smooth `Path`.
- **Load-bearing reuse:** The exact same contour engine serves both inline
  **tap highlights** and Ticket 10 **custom text selection highlights**.

### 4. Press Feedback Lifecycle (`ChatSpanFeedbackPainter`)
Actionable inline hits (links, inline code, fenced copy chrome) drive a
**press-lifecycle** canvas feedback painter — Telegram Android
`LinkSpanDrawable` / `ChatMessageCell` press tracking, not a one-shot flash
fired only after the action:

| Phase | When | Visual |
| ----- | ---- | ------ |
| **Expand** | Pointer **down** on a pressable inline hit | `pressT` $0 \rightarrow 1$; contour plate + ripple from $(touchX, touchY)$ clipped to the smooth path |
| **Hold** | Pointer still down | Stay at full press (`releaseT = 1`) |
| **Release** | Pointer **up**, cancel, or abort | `releaseT` $1 \rightarrow 0$ over $100\text{–}150\text{ ms}$; then clear |

Quick taps still enforce a **minimum hold** ($\sim 60\text{ ms}$) before fade so
the flash remains visible. Long-press uses the **same** ink; the host long-press
action (`handleInlineHitLongPress`) is a side channel, not a second painter.

**Pressable on down:** hyperlink spans; inline monospace click-to-copy; fenced
header / bottom copy chrome. **Not** the fenced code **body** (text / selection).

**Abort** when the same pointer is claimed by a **span gesture** or
**text-selection** yield ([ADR 003](003-viewport-owned-span-gesture.md),
[ADR 015](015-per-body-scope-owns-continuous-text-gestures.md)) — do not hold
ink into message-then-text or span membership.

Facade symmetry: `beginSpanFeedback` / `releaseSpanFeedback` /
`abortSpanFeedback`. Animation ownership stays on `ChatMarkdownBody`; the
selection facade does not own `AnimationController`s.

*(Supersedes the earlier “tap-up → one-shot 180 ms” wiring shipped with ticket
04; paint math (`pressT` / `releaseT` / contour) is unchanged.)*

### 5. Minimal Package Contract in `flutter_md`
`flutter_md` remains an unopinionated general-purpose markdown library. It
exposes only two minimal, non-breaking primitives:
- `cursorResolver`: Optional callback on `MarkdownThemeData` / `MarkdownWidget`
  allowing parent widgets to dynamically resolve hover cursors from local offsets.
- `localBoxesForRange`: Fast query on `MarkdownSelectionSurface` returning
  `List<Rect>` for a specific block and span character range from cached painters
  without re-layout.

## Consequences

### Positive
- 1:1 interaction parity with Telegram Android and Desktop.
- Code blocks support both click-to-copy (header) and character-range text
  selection (body) without gesture conflicts.
- Polished, tactile **press-lifecycle** feedback (expand / hold / release) with
  expanding ripple and vector-smoothed contours; long-press reuses the same ink.
- Single geometry engine (`ChatSmoothContour`) solves both tap feedback and
  Ticket 10 custom selection paint.
- `flutter_md` stays clean and lightweight without chat-specific UI bloat.

### Negative
- Requires a two-point update across `flutter_md` fork and `chat_scroll_view`.
- Rendering multi-line contour paths is slightly more complex than a single
  rectangular ink well, but the path is computed only on press/selection change
  and cached.
- Press-lifecycle arming must abort cleanly when span / text selection claims
  the pointer, or ink fights message-then-text (ADR 015).
