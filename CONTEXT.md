# Chat Scroll Viewport

Anchor-based bidirectional chat viewport. All geometry comes from a message-id
origin; there is no global content height and no absolute scroll offset.

Runtime rules live in [`docs/architecture/`](docs/architecture/index.md).
ID and position policy live in [`docs/adr/`](docs/adr/001-message-id-scheme.md).

## Language

### Identity

**Message ID**:
A signed integer that uniquely identifies one message in a conversation and never changes after assignment.
_Avoid_: Index, cursor, list key, document offset

**Chunk**:
A fixed 64-id page of the conversation used for fetch and storage.
_Avoid_: Page, window, range (when meaning this paging unit)

**Absent**:
A message ID confirmed missing in the sequential sequence. It occupies no height and must not be built.
_Avoid_: Deleted row, null message, tombstone widget, missing child

**Present neighbor**:
The next or previous message ID that is actually present, skipping absent IDs.
_Avoid_: id ± 1, previous slot, adjacent index

### Origin and geometry

**Anchor origin**:
The only scroll state: which message’s top edge is the layout origin, and that edge’s viewport Y.
_Avoid_: Scroll offset, pixels, content offset, ScrollPosition

**Fan-out**:
Placing rows by walking present IDs up and down from the anchor origin.
_Avoid_: List layout, layout from zero, sliver geometry

**Reposition**:
Moving already-built rows from the same origin without measuring or inflating.
_Avoid_: Relayout, rebuild, correctBy

**Scroll band**:
The usable vertical range between top and bottom padding, used for alignment and tail pinning.
_Avoid_: Viewport, SafeArea, full height

**Visible band**:
The on-screen slice of content used as the reading-position reference after a delete.
_Avoid_: Cache extent, build zone

### Layers of work

**Tier-1**:
The ticker path that mutates the origin offset and repositions built rows, painting unless coverage fails.
_Avoid_: Scroll activity, pointer route (as the name for this path)

**Tier-2**:
The layout path that inflates, measures, and fans out children from the origin.
_Avoid_: Build, performLayout (as the domain name)

**Writer**:
The single phase allowed to mutate the origin during a given stretch of frames.
_Avoid_: Compensate, extra offset, visual offset

**Renormalize**:
Silently picking a visible row as the new origin without moving pixels.
_Avoid_: Recenter, jump, re-anchor (when nothing should visually move)

### Data extent

**Reached oldest** / **Reached newest**:
Flags that the conversation edge is known, so a boundary pin may run.
_Avoid_: minScrollExtent, maxScrollExtent, end of list

**Oldest known ID** / **Newest known ID**:
The ends of the currently known ID span, not necessarily the conversation edge.

**Full-chunk fetch**:
A fetch that covers whole chunks only. Partial ranges corrupt absent marking.
_Avoid_: Cursor fetch, partial range, page query

### Edges and tail

**Boundary pin**:
A local geometric constraint on the oldest or newest built row when that conversation edge is known.
_Avoid_: Clamp to extents, correctBy, min/max pixels

**Follow tail**:
Keeping the newest message pinned to the band bottom as new content arrives, only while the user is at the tail.
_Avoid_: Stick to bottom, jump to end, keyboard follow

**Short content**:
When the full known conversation fits in the scroll band, the viewport is not scrollable.
_Avoid_: Underscroll, empty list, disabled physics

**Band-stable delete recovery**:
After the origin ID becomes absent, keep the visible band’s bottom (the reading position) still, not the raw origin Y.
_Avoid_: Compensate, keep anchor Y, correctBy

### Grouping and slots

**Day bucket**:
The grouping key (usually a calendar day) that owns a header.
_Avoid_: Date, section, sticky header (as the key)

**Starts day**:
A row that opens a new day bucket and may show an inline date separator.

**Slot**:
One of four disjoint identity spaces: messages, chunk errors, floating header, overlay.
_Avoid_: Child index, GlobalKey, element slot (Flutter’s)

### Selection

**Message selection**:
Membership of whole messages in the selected set. This viewport’s only selection model.
_Avoid_: Text selection, character range, highlight

**Span chain**:
The present-neighbor walk from the gesture origin to the current span hit. Absent, shimmer, and chunk-error slots are not on it.
_Avoid_: Id interval, reserved range, adapter slice

**Selection span**:
The span-eligible messages on the span chain. Membership is not reserved for ids that later become present.
_Avoid_: Paint-toggle, id range, adapter range

**Span polarity**:
Whether a selection span forces membership on or off. Locked at gesture start.
_Avoid_: Invert flag, drag mode

**Select span**:
A selection span whose membership is forced on.
_Avoid_: Additive drag, paint-select

**Unselect span**:
A selection span whose membership is forced off.
_Avoid_: Subtractive drag, paint-deselect

**Span gesture**:
A viewport-owned pointer sequence that holds a selection span: long-press on a present message, travel past slop, then move. Lift ends it. Message rows do not own this pointer. Does not start if the long-press was claimed (span yield).
_Avoid_: Selection drag, paint gesture, range drag, per-row detector

**Span yield**:
A host claim on the long-press that prevents a span gesture from starting. The seam for a future in-bubble text selector; unused until that selector exists.
_Avoid_: Arena win, text selection (as the name of this seam)

**Span abort**:
Forced end of a span gesture that leaves the selected set as-is. Happens when the gesture origin becomes absent.
_Avoid_: Cancel selection, clear, retarget origin

**Gesture origin**:
The present message that received the long-press that started the span gesture.
_Avoid_: Anchor, start id, first selected

**Span hit**:
The laid-out message row whose rectangle contains the pointer after clamping into the scroll band. Non-message slots are not hits; over a gap or non-message slot the span stays put.
_Avoid_: Nearest neighbor, id under Y, adapter child

**Span auto-scroll**:
Viewport motion toward the pointer’s edge band during a span gesture. It is the sole origin writer while that band is occupied. Delta may be zero: short content and boundary pins still win.
_Avoid_: Fling, follow tail, user drag (as the name for this motion)

**Selection snapshot**:
The set of selected message IDs at span-gesture start, after the origin’s own toggle.
_Avoid_: Live selection, current set

**Span-eligible**:
A present message the current span polarity may change, judged only against the selection snapshot.
_Avoid_: canSelect, selectable

**Selection-allowed**:
A present message the host permits in the selected set at all. Independent of span polarity.
_Avoid_: canSelect, selectable, span-eligible

**Selection cap**:
An optional host-set maximum size of the selected set. Null means no maximum.
_Avoid_: Hardcoded 100, forward limit

**Cap hit**:
A refused add because the selected set is already at the selection cap.
Membership does not change; a dedicated listenable still fires so chrome
can shake or play an error haptic.
_Avoid_: overflow, limit error

### Navigation

**Navigation alignment**:
Where a jump or animate should land the target inside the scroll band (band top … band bottom).
_Avoid_: Scroll offset, alignment in pixels

**Close-path animation**:
Continuous origin-offset interpolation when the target is already built and nearby.
_Avoid_: Animate pixels, lerp ScrollPosition

**Far-path animation**:
A crossfade plus jump when the target is not built or is far away.
_Avoid_: Teleport, correctBy through intermediate offsets
