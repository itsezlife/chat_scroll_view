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

**Reserved inset**:
Space the scroll band yields so messages are not drawn under occluding host chrome. The viewport consumes it as `topPadding` / `bottomPadding`.
_Avoid_: SafeArea, MediaQuery padding (as the name for this reservation)

**Overlay chrome**:
Host widgets stacked over the viewport that position against the reserved edge and must not increase `topPadding` / `bottomPadding`.
_Avoid_: Bottom sheet, FAB inset (when they are not reserving the band), message menu

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

**Message body layout**:
Host helper that packs in-bubble content beside trailing meta (time / status) with last-line fit and shrink-wrap. Reply and media stay outside it.
_Avoid_: Stack+Positioned meta, type-marker child discovery, internal TextPainter for body text

**Bubble radius**:
Tunable large corner radius for message chrome (`ChatMessageThemeData.bubbleRadius`). Clustered outer corners use the near radius instead.
_Avoid_: Hardcoded BorderRadius in the message builder, neighbor walks for corners

**Near radius**:
`min(cornerNearCap, bubbleRadius)` applied to the outer corners when the message is pinned to a same-sender run neighbor (`!isFirstInSenderRun` / `!isLastInSenderRun`). Incoming: top-left / bottom-left; outgoing: top-right / bottom-right.
_Avoid_: Small radius, tail radius (when meaning clustered round corners)

**Bubble metrics**:
Pure resolvers (`ChatBubbleMetrics`) that map theme tokens + `MessageRunLayout` to Directionality-aware `BorderRadiusDirectional` / `EdgeInsetsDirectional` / media radii. Horizontal asymmetry is **outer (tail) vs inner (toward center)** — not raw left/right. Hosts read these; they do not re-derive pins from neighbors in `messageBuilder`.
_Avoid_: Inline corner switch in the list item, AttachmentsBordersType algebra, absolute EdgeInsets.left for bubble chrome

**Cluster gap**:
Max `|createdAt|` between present same-sender neighbors that may share a sender run under `DefaultChatSenderRunLayout` (`maxClusterGap`, default 5 minutes). Exceeding it ends the run — large corners and unclustered top inset — without a separate spacing enum. `null` disables the window. Hosts replace the whole policy via `ChatScrollView.senderRunLayout`.
_Avoid_: SpacingType.timeDiff, per-row time checks in messageBuilder, forking package statics

**Sender run layout**:
Host-injected policy (`ChatSenderRunLayout`) that resolves `MessageRunLayout` for each built id. Package default is `DefaultChatSenderRunLayout`.
_Avoid_: Static package-only clustering, neighbor walks inside messageBuilder

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

### Message menu

**Message menu**:
A modal overlay over one present message: dimmed scrim with that message left undimmed, optional reactions, and an action list. Mutually exclusive with message selection. Not overlay chrome.
_Avoid_: Context menu, overlay chrome, popup, action sheet

**Idle message tap**:
A tap on a present message slot while message selection is inactive. The hit is the full laid-out row, not bubble ink and not the list background. It identifies the message id, that slot’s rect, and the tap position. Independent of selection-allowed.
_Avoid_: Opaque tap, bubble tap, onTap, row click, menu-allowed

**Message menu session**:
The exclusive lifetime of a message menu for one id and one slot rect captured at idle message tap. IME visibility is frozen for that lifetime. Ends without an action on dismiss, or when a host-provided presence signal says that id is absent. Does not retarget.
_Avoid_: Overlay entry, popup lifetime, live tracking, context-menu route

**Message menu dismiss**:
Ending the session without an action: first system back, Escape, or scrim tap. IME and the route stay. Next back may hide the IME; only then may the route pop.
_Avoid_: Navigator.pop, hide keyboard, PopScope

**Pre-IME back claim**:
A stacked claim on Android back before the IME. The top claim is the live overlay’s dismiss (message menu session today). An empty stack leaves back to the IME.
_Avoid_: PopScope, BackButtonDispatcher, singleton back handler, WillPopScope

**Message menu action**:
A host-defined row in the message menu. The viewport has no catalog of actions.
_Avoid_: MessageAction enum, PopupMenuItem, context-menu item

**Message menu reaction**:
A host-defined emoji in the message menu reaction strip. Choosing one ends the session the same way an action does.
_Avoid_: Emoji picker, reaction sheet

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
