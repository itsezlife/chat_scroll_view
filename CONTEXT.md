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
_Avoid_: Scroll offset, pixels, content offset, ScrollPosition, Center Band, ChatCenterBand

**Center-band ray**:
Fixed infinitesimal horizontal ray at 50% of the paint band (top inset → bottom inset). Used to identify the Message under visual center.
_Avoid_: Gaze ray, id-midpoint heuristic, thick center slab, host-configurable fraction (v1)

**Center Band**:
Leave/reopen reading position: the Message whose rect intersects the center-band ray, plus pixels from that message’s top to the ray. Not the Anchor origin, and not a Message highlight.
_Avoid_: Open Anchor, layout anchor pair, gaze, ChatCenterBandRestore, Message highlight

**ChatCenterBand**:
Public snapshot of a Center Band: `messageId` + `offsetFromMessageTop`. Live via deferred listenable on the scroll controller. Apply with `jumpToCenterBand` (ADR 009).
_Avoid_: Anchor origin fields, visibleRange first/last midpoint

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
_Avoid_: Scroll path, pointer route (as the name for this path)

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

**Scroll physics**:
The host-chosen pairing of a **fling** and an **edge effect** that governs user-driven motion. Presets are named after their edge effect, and the platform default picks one per OS family; a custom pairing is just a different pair.
_Avoid_: ScrollBehavior, overscroll mode, parent physics chain

**Fling**:
Inertial travel after a release with velocity, following one deceleration curve. Stops at a boundary pin; leftover velocity goes to the edge effect.
_Avoid_: Ballistic, momentum scroll

**Edge effect**:
The paint-only response of the message layer when user motion presses past a reached conversation edge. Layout stays pinned; the origin never passes a boundary pin.
_Avoid_: Overscroll, bounceback, overscroll indicator, glow

**Stretch**:
An edge effect that scales the message layer from the pressed edge.
_Avoid_: Android overscroll (as the name)

**Rubber-band**:
An edge effect that translates the message layer past the pressed edge with growing resistance, then springs back.
_Avoid_: Bounce, iOS overscroll (as the name), layout rubber-banding

**Follow tail**:
Keeping the newest message pinned to the band bottom as new content arrives, only while the user is at the tail.
_Avoid_: Stick to bottom, jump to end, keyboard follow

**Short content**:
When the full known conversation fits in the scroll band, the viewport is not scrollable.
_Avoid_: Underscroll, empty list, disabled physics

**Tail-or-target open**:
A jump that decides once, in the first layout that lays out its target as a loaded row, between the target and the tail: when the newest message is known and loaded and the span from the target's body top (its **row chrome** excluded) to the newest message's bottom fits within a host-given fraction of the viewport height, the chat opens pinned at the tail; otherwise the target is placed as a plain jump. The host hears the outcome inside that layout.
_Avoid_: Smart jump, auto-scroll to bottom, half-screen check (as the engine name)

**Band-stable delete recovery**:
After the origin ID becomes absent, keep the visible band’s bottom (the reading position) still, not the raw origin Y.
_Avoid_: Compensate, keep anchor Y, correctBy

### Scrollbar

**Scrollbar**:
Viewport chrome on the trailing edge that shows where the visible band sits within the known conversation span. It paints outside the edge transform.
_Avoid_: Scroll indicator (as the umbrella term), fast scroller, overlay scrollbar widget

**Track**:
The scrollbar's full travel, standing for the span from the oldest to the newest known message.
_Avoid_: Rail, gutter, background bar

**Thumb**:
The part of the scrollbar standing for the visible band: its position is the band's place in the known span, its length the band's share of it. During a grab it follows the pointer, keeping the grab point, and the band follows the thumb; on release it eases back to the band's position.
_Avoid_: Handle, knob, bar (alone)

**Thumb squash**:
The thumb's response to a **rubber-band** edge effect: pinned to the pressed end of the track, it shortens 1:1 with the rubber-band overshoot, down to a round dot, and never leaves the track. **Stretch** and no edge effect leave the thumb untouched.
_Avoid_: Thumb bounce, scrollbar overscroll, scaled squash

**Scrollbar painter**:
The host-replaceable look of the scrollbar: it draws from track and thumb rects the viewport has already resolved, plus shown, hover, and drag factors. Where presses land never depends on what it draws.
_Avoid_: Scrollbar builder, scrollbar widget, custom scrollbar (as the extension point)

**Scrollbar grab**:
How the scrollbar takes pointers away from message scrolling: which presses and hovers it claims, and what a drag or track press does. A grab starts only on a fresh press nothing else in the viewport owns, then owns that pointer until release. Touch grabs only an enlarged target around a visible thumb; a hovering pointer may claim the whole strip even while it is hidden, since hover reveals it first. Chosen from a closed set; hosts tune it, never replace it.
_Avoid_: Scrollbar interaction (collides with **selection interaction**), scrollbar gesture, fast scroll

**Scrollbar preset**:
A host-chosen combination of scrollbar visibility, **scrollbar grab**, and **scrollbar painter**. The platform default picks the mobile or desktop preset per OS family; a preset with no scrollbar turns it off. The input device in use adjusts behavior inside a preset, never switches presets.
_Avoid_: Scrollbar mode, adaptive scrollbar (as a live switch), ScrollBehavior

**Scrollbar visibility**:
The scrollbar's own shown factor in `[0, 1]`, separate from **scroll activity**. List motion feeds it the same way it feeds scroll activity; a grab, hovering the scrollbar, a moving edge effect, and the pointer entering or leaving the viewport also move it. It rises when the reader's position in the conversation changes, never when only the thumb's geometry changes (history loads, follow tail on arrival, pixel-preserving writers). Either always shown or auto-hiding after an idle delay (longer after navigation).
_Avoid_: Scroll activity (as the scrollbar's driver), scrollbar opacity, fade mode

**Scrollbar hold** / **Scrollbar suppression**:
Host-owned handles on scrollbar visibility for conditions the viewport cannot see. While any hold is alive the scrollbar stays shown; while any suppression is alive it hides, ignores show triggers, and claims no presses. Suppression beats hold; handles release independently. A **scrollbar flash** is the handle-less one-shot: show, then hide after the idle delay.
_Avoid_: Scrollbar enabled flag, force-show bool, disableScroll

### Grouping and slots

**Day bucket**:
The grouping key (usually a calendar day) that owns a header.
_Avoid_: Date, section, sticky header (as the key)

**Starts day**:
A row that opens a new day bucket and may show an inline date separator.

**Row chrome**:
Viewport-owned decoration stacked above the message body inside one message slot, such as the inline date separator of a row that starts a day. Each item has a **row chrome delegate** that resolves its opacity and input every frame from its paint position, the floating header zone, and **scroll activity**; the summed chrome height is the line above which presses are chrome, not message. Outside selection chrome; never message surface.
_Avoid_: Header row, fake message, list item, part of the message builder, chrome role enum

**Unread boundary**:
The host-chosen message id where unread content begins — typically the first unread message from someone else, fixed when the chat opens and kept while the reader catches up. The host decides what counts as unread and when the boundary appears, moves, or goes away; the viewport only compares ids. Distinct from a read baseline that advances as the reader scrolls, and from **Starts day**.
_Avoid_: Read baseline, last-read, unread row, first-unread index

**Unread separator**:
Host-built **row chrome** stacked inside the **unread boundary** row: below the inline date separator when that row **starts a day**, above the message body. Painted only on a loaded message row, always opaque (the day header policy never fades it), outside selection chrome, never message surface.
_Avoid_: Unread row, fake message, divider item, part of the message builder

**Day header policy**:
The delegate that decides how the floating header and the inline date separators share the top of the viewport: the header's push offset and opacity, and the row chrome delegate every inline separator uses. Built-ins fade separators under a resting header, or push the header up with the next day's separator. The header is *held* while it stands in for a separator hidden or faded under it: it stays shown and pins scroll activity at `1`, so leaving that position never finds it hidden.
_Avoid_: Sticky header mode, header style enum

**Scroll activity**:
A viewport-owned factor in `[0, 1]`: rises when the list moves, holds while it moves, falls after an idle delay (longer after navigation). Delegates read it to hide chrome while the list rests; without a clock it stays `1`.
_Avoid_: AFK timer per widget, scroll idle flag, is-scrolling bool

**Slot**:
One of four disjoint identity spaces: messages, chunk errors, floating header, overlay.
_Avoid_: Child index, GlobalKey, element slot (Flutter’s)

**Message body layout**:
Host helper that packs an optional in-bubble header band, content, and trailing meta (time / status) with last-line fit and shrink-wrap. Header width can trail meta when it exceeds the text cluster; reply and media stay outside it.
_Avoid_: Stack+Positioned meta, type-marker child discovery, internal TextPainter for body text, Column sender above a separate body that ignores name width

**Message change transition**:
Edit morph: layout size is already final; painted bubble bounds move via edge deltas; old/new text crossfade inside a clip of that painted background; “edited” meta enters on the same progress factor (`ChatMessageChangeTransition`).
_Avoid_: OverflowBox/ClipRect host-size lerp, SubstringLayoutAnimator, per-glyph morph

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
Host-injected policy (`ChatSenderRunLayout`) that resolves `MessageRunLayout` for each built id. Package default is `DefaultChatSenderRunLayout`. Optional `MessageRunLayout.extras` is host chrome in the skip-rebuild cache (value equality), not clustering. Cast it in `messageBuilder`. Hosts wrap the default or a custom policy, close over host state, and return a snapshot with `extras` set. Invalidate extras via a new unequal policy instance, or keep one `Listenable` / `ChangeNotifier` policy and notify — never via `ChatDataSource.notifyDataChanged` (that channel is message inventory, not chrome).
_Avoid_: Static package-only clustering, neighbor walks inside messageBuilder, domain receipts / typed chrome bags in the package, mutable or identity-only `extras`, chrome ticks on the data source
### Selection

**Message selection**:
Membership of whole messages in the selected set (multiselect chrome). Independent of character ranges; relationship to text selection is governed by **selection policy**.
_Avoid_: Text selection (when meaning membership), character range, highlight

**Text selection**:
A character-range selection inside the body text of one message. Owned by the chat viewport as a peer to **message selection**. Not membership in the selected set, and not a Message highlight. How it is entered and whether it nests with message selection is **selection policy**.
_Avoid_: Message selection, SelectableRegion, cross-message character range (chat list), already-selected-only (as a universal rule), bridge package (as the owner)

**Text selection subject**:
The single message that owns the active character-range text selection. Under mobile policy it is one of the message-selected members (message selection is preserved intact); under desktop/web policy it owns the range while the selected set is empty.
_Avoid_: Gesture origin, document id, anchor, “the selected message” (as the only meaning)

**Text selection chrome**:
The mobile handles and adaptive toolbar that present and act on the live **text selection** for the **text selection subject**. Owned with that selection (per-body scope + facade sync); not **message selection** chrome, not the **message menu**, and not overlay chrome. On desktop/web, Flutter’s built-in text context menu remains the default when the host does not handle **secondary message tap**; when the host does under `$Desktop`, text-range actions belong in the **message menu** instead of a second popup. Under `$Mobile`, the adaptive toolbar stays even when secondary is also wired (message menu entry is idle primary).
_Avoid_: Context menu (alone), selection overlay (Flutter), floating toolbar (host), magnifier

**Selection policy**:
The product rules for how message selection and text selection enter, nest or exclude each other, dismiss, behave on Copy, and how **inline hits** relate to idle dismiss (mobile vs desktop/web strategies). Not a pointer kind and not a platform import fork by itself.
_Avoid_: TargetPlatform (as the domain name), theme, “Telegram order” (when meaning only Android)

**Selection interaction**:
A host-observable outcome from the selection facade — successful clipboard **Copy**, hyperlink activation (tap or long-press), or code activation when auto-copy is off — delivered as one sealed `ChatSelectionInteraction` channel (`onInteraction` / `addInteractionListener`). Feedback UI stays app-side; handle `ChatCopied` for “Copied” chrome. Distinct from a **message menu request** (viewport slot geometry / menu entry).
_Avoid_: onCopySuccess (as the public surface), parallel link/code callbacks, toast inside the package, message-menu request

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
A viewport-owned pointer sequence that holds a selection span: long-press on a present message, travel past slop, then move. Lift ends it. Message rows do not own this pointer. Does not start when engine-owned long-press routing claims the press for **text selection**.
_Avoid_: Selection drag, paint gesture, range drag, per-row detector

**Span yield**:
Former transitional host claim on a long-press at a global point that prevented a span gesture from starting. Superseded and removed: routing between span and text is fully engine-internal from live membership, **text selection subject**, range, and **selection policy** ([ADR 003](docs/adr/003-viewport-owned-span-gesture.md), [ADR 013](docs/adr/013-viewport-owns-markdown-text-selection.md)).
_Avoid_: Arena win, text selection (as the name of this seam), current host API

**Inline hit**:
A pointer on a markdown body that is not idle selection-dismiss: link activation or code/pre click-to-copy (or a host callback for those). Mentions and other host-typed tokens that arrive as markdown links are still link activations — not a separate hit kind. First-class against idle-tap dismiss. Under mobile **selection policy**, **message selection** or a live **character-range text selection** suppresses *all* inline activations (links, inline code, fenced COPY chrome). Under desktop/web, message membership alone does not suppress; a live character-range still does. Mere arm-for-entry does not suppress.
_Avoid_: Idle message tap (as the name of this path), toolbar dismiss, text selection (as the name of this path), mention hit (as a peer of link)

**Body linkify**:
A host-invoked rewrite of bare URLs and mention tokens in message text into markdown links before the body is shown. Runs at send and at receive/materialize, never as a viewport paint or rebuild step. The viewport only paints and activates already-marked links.
_Avoid_: Autolink on paint, URL detection in layout, entity overlay (when meaning this rewrite), package-owned “what is a URL”

**Linkify policy**:
Caller-owned allowlist bitmask for **body linkify**: which token families count (`webUrls`, `mentions`, …) and how they combine. Shipped bits also skip fenced code, inline code, and existing markdown links (fixed exclusion zones, not a separate host knob). A package may ship convenience combinations (e.g. `webAndMentions`); the policy is still a host choice, not viewport behavior.
_Avoid_: Hardcoded universal URL definition, product-branded rule names, linkify inside the scroll viewport, sealed one-of presets when flags must combine

**Link preview**:
Host- or backend-owned rich card for a URL (title, image, favicon, and so on). Outside this context: not an **inline hit**, not **body linkify**, and not viewport chrome.
_Avoid_: OG fetch in the viewport, preview slot as markdown, conflating styled links with webpage cards

**Tap highlight** (press highlight):
A transient visual plate under a pressable surface — markdown inline hits (links including mention-scheme URLs, inline code, fenced copy chrome) or host chrome such as a sender name via `ChatTapHighlight`. **Press-lifecycle:** expand on pointer down, hold while pressed, fade on up; abort / cancel clears immediately. Body ink aborts if the pointer is claimed by a **span gesture** or **text selection**, and under mobile **selection policy** does not arm while **message selection** or **text selection** is already active (desktop keeps press ink). `ChatTapHighlight` is selection-facade-free: under `ChatSelectionStateScope` it follows `canPerformActions`; padding expands paint/hit only (no layout shift). Null `onLongPress` on touch lets viewport **message selection** claim the press (Telegram name chrome); mouse presses exclude viewport message pan. Same paint for short tap and long-press (host action is separate). Composed of a vector-smoothed contour path with an expanding touch-origin ripple. Not persistent **text selection**, and not a whole-row **Message highlight**.
_Avoid_: RippleDrawable, InkWell, selection highlight, active selection, one-shot long-press flash

**Smooth text contour**:
A continuous rounded polygon path generated from a list of text bounding boxes (single or multi-line) with vector-arc rounded corners, collinear vertex elimination, and cross-product turn direction. Used for **tap highlights** and custom **text selection** plates.
_Avoid_: Rounded rect union, stair-stepped selection, CornerPathEffect (as the Dart concept)

**Fenced code block header**:
The top banner of a fenced markdown code block displaying language information and desktop click-to-copy action with hover cursor feedback, visually and hit-test distinct from the selectable code body text beneath it.
_Avoid_: Code fence title, code card button, toolbar

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
A host-presented exclusive surface of actions (and optional reactions) for one present message, opened from a press or tap on that message. One concept across platforms; how it looks (scrim with the message left undimmed vs a light popup at the pointer) is presentation, not a second term. Cannot run concurrently with an active **span gesture** or other selection-entry gesture; may open while the selected set is already non-empty (**over-selection**). Not overlay chrome and not **text selection chrome**.
_Avoid_: Context menu, overlay chrome, popup, action sheet, **text selection chrome**

**Message menu request**:
The structured packet the viewport emits when a message-menu entry gesture wins on a present message **slot** (full row — not bubble-only, not list background or day headers): message id, slot rect, tap position, the reported **message surface** rect and outline when the host registered one, the **scroll band** rect, and viewport-known **hit context** the host needs to choose rows — **message menu point state** (message-surface Inside vs slot Outside), **message menu membership** (idle / upon-selected / elsewhere), whether this message is the live **text selection** subject (`hasTextSelection`), whether the tap is upon that highlight (`overlapsTextSelection`, with a snapshot for Copy-selected), optional **select-up-to** chain ids when membership is elsewhere and the span fits under the selection cap, and an optional **inline hit** (link / code) when the tap is Inside. Not a catalog of actions — that stays host data. Opening the menu does not by itself clear text selection. Not a **selection interaction** (Copy / link / code on the selection facade).
_Avoid_: ContextMenuRequest (as our type name), MenuEvent, TapDetails alone, host-rebuilt hit guess, nearest-neighbor gap hit, ChatSelectionInteraction

**Message menu point state**:
Whether the menu gesture landed on the painted **message surface** / bubble (Inside — including sender header and meta) or only on surrounding **slot** padding / row chrome (Outside). The menu may still open for Outside on a present slot; hosts typically reduce rows (desktop Select-only). Empty list / day headers never emit a request — that is not Outside. Hosts report the surface via `ChatMessageSurfaceBounds` (or equivalent); hit-testing resolves the mounted box’s live global geometry so scroll without rebuild does not leave a stale Outside.
_Avoid_: Text-body-only as Inside, Bubble ink only, slot-as-Inside, nearest-neighbor Outside, cached global Rect across scroll

**Message menu membership**:
How the gesture relates to **message selection**: idle (selection inactive), upon-selected (tap id is in the set — **over-selection**), or elsewhere (selection active but tap id is not in the set). Bulk actions belong on upon-selected only. Elsewhere may offer **Select up to this message** when the request carries a non-empty `selectUpToIds` chain that fits under the selection cap.
_Avoid_: Selection mode flag alone, overSelection as the only axis

**Over-selection**:
A **message menu request** whose **membership** is upon-selected — the tap lands on a message already in the selected set while message selection is active. The host typically offers bulk actions (copy/forward/delete/clear) instead of single-message rows. Opening the menu does not clear membership by itself.
_Avoid_: Selection mode menu, multi-select sheet, bulk-only menu product

**Idle message tap**:
A primary tap on a present message slot while message selection is inactive. The hit is the full laid-out row, not bubble ink and not the list background. Under mobile **selection policy** it produces a **message menu request**; under desktop/web it does not open the message menu (primary stays text, links, and dismiss). Independent of selection-allowed.
_Avoid_: Opaque tap, bubble tap, onTap, row click, menu-allowed

**Secondary message tap**:
A secondary (right-click) tap on a present message slot. Under desktop/web **selection policy** it is the message-menu entry gesture and produces a **message menu request** (including while message selection is active, so the host can offer over-selection actions). When the host wires the secondary callback, the viewport owns secondary on the **full slot** (including text glyphs) and per-body Flutter text context menus yield; when the callback is null, Flutter’s text menu stays available on selectable text. Not the mobile idle-tap path.
_Avoid_: Context menu event (as our term), right-click handler, onSecondaryTap alone

**Message menu session**:
The exclusive lifetime of a **message menu** for one **message menu request** (id and slot rect captured at entry). IME visibility is frozen for that lifetime when an IME is in play. Ends without an action on dismiss, or when a host-provided presence signal says that id is absent. Does not retarget.
_Avoid_: Overlay entry, popup lifetime, live tracking, context-menu route

**Message menu presentation**:
How a **message menu session** is drawn: mobile uses a dimmed scrim that leaves only the target's **message surface** undimmed, in the outline the host reported and clipped to the **scroll band** (the whole slot when no surface is reported), with the action column anchored to that slot; desktop/web uses a light popup at the pointer with no viewport dim and no message outline lift. Defaults from **selection policy** (`$Mobile` → scrim sheet, `$Desktop` → pointer popup); the host may override for a given present. Same session contract; not a second product concept.
_Avoid_: Two menu products, ContextMenu vs ActionSheet split, host-only desktop shell

**Message menu dismiss**:
Ending the session without an action: system back, Escape, scrim tap (mobile presentation), or outside/dismiss on the desktop popup. IME and the route stay when an IME was frozen. Next back may hide the IME; only then may the route pop.
_Avoid_: Navigator.pop, hide keyboard, PopScope

**Pre-IME back claim**:
A stacked claim on Android back before the IME. The top claim is the live overlay’s dismiss (message menu session today). An empty stack leaves back to the IME.
_Avoid_: PopScope, BackButtonDispatcher, singleton back handler, WillPopScope

**Message menu action**:
A host-defined row in the message menu. The viewport has no catalog of actions.
_Avoid_: MessageAction enum, PopupMenuItem, context-menu item

**Message menu reaction**:
A host-defined emoji in the message menu reaction strip (optional on any **message menu presentation**). Choosing one ends the session the same way an action does. Host may omit the strip on a given presentation without making reactions a separate product.
_Avoid_: Emoji picker, reaction sheet, desktop-only reaction product

**Global catalog asset cache**:
Process-wide thumbs/media cache for document-backed emoji, stickers, and GIFs, shared with the Panel Catalog Viewport so chat leaves and panel leaves bind the same assets.
_Avoid_: Per-message private decode stores, panel-only drawable maps as the long-term source of truth

### Navigation

**Navigation alignment**:
Where a jump or animate should land the target inside the scroll band (band top … band bottom).
_Avoid_: Scroll offset, alignment in pixels

**Alignment hold**:
After a navigation's **navigation alignment** (or Center Band placement) lands on a loaded target row, the viewport keeps it on that row until the first user scroll, a programmatic scroll-by, or the next navigation. While held, a change of the top **reserved inset** or of the target row's **row chrome** re-applies it. Other geometry keeps its usual owner: bottom-inset compensation, the boundary clamp, the **row chrome** hold on other rows, and the tail pin. The hold ends without moving anything when the target stops being the **anchor origin**. The engine calls the armed alignment or Center Band placement the *navigation placement*; an **alignment hold** is that placement in its *held* phase (after *pending*, before *released*).
_Avoid_: Sticky jump, re-jump on inset change, pinning the target

**Close-path animation**:
Continuous origin-offset interpolation when the target is already built (Telegram `found` → `smoothScrollBy`).
_Avoid_: Animate pixels, lerp ScrollPosition

**Far-path animation**:
Navigation when the target is not among current built children. Implemented as a stitch, not as scrolling through the gap and not as a viewport crossfade.
_Avoid_: Continuous scroll through unloaded ids, far fade, inventing pixel distance across gaps, distance gate forcing stitch for a built row

**Stitch**:
A continuity illusion for far-path navigation: capture visible outgoing rows, teleport the origin to the target, then dual-translate outgoing and incoming paint so the jump reads as one scroll. Intermediate history need not exist as real rows during the flight.
_Avoid_: Crossfade, opacity fade of the whole viewport, walking every id between endpoints

**Outgoing strip**:
The message rows visible at stitch capture, pinned and painted sliding out for the duration of the stitch.
_Avoid_: Old viewport snapshot bitmap, ghost list

**Incoming band**:
The destination rows built after the stitch teleport, painted sliding in under the same animation factor as the outgoing strip.
_Avoid_: New list, post-jump content (when meaning the paint set during flight)

**Full-strip travel**:
Stitch scroll length derived from the full outgoing strip and incoming extents, including off-screen parts of tall rows — not clamped to the scroll band for product reasons.
_Avoid_: Viewport-capped stitch, cropped tall-message scroll

**Navigation load-gate**:
Far-path stitch runs only after the target is loaded enough to be a real destination row (not an unresolved shimmer stand-in). Until then the host may show loading; the viewport must not dual-translate a placeholder band across an unloaded gap.
_Avoid_: preferBuilt timeout → force stitch on shimmers, inventing travel across unloaded chunks

**Destination window fetch**:
Loading for navigation readiness is an around-target window owned by the host/data-source. The engine must not expand readiness into a contiguous fill of every chunk between the current origin and the target.
_Avoid_: Gap fill for stitch, minChunk…maxChunk storm as a load-gate requirement

**Stitch presence pin**:
For the load-gate wait and the stitch flight, the animate target and the outgoing strip stay protected from GC and from being treated as Absent. Explicit host deletion of those ids cancels the animation; silent retarget or delete-collapse of the target is forbidden.
_Avoid_: Soft retarget mid-stitch, LRU eviction of outgoing/target during flight

**Immediate navigation**:
Start path selection as soon as possible: if the target is not ready, enter the navigation load-gate (destination window fetch), then close-path or stitch. Never stitch over unresolved shimmers.
_Avoid_: Force stitch after timeout, shimmer dual-translate

**Prefer-built navigation**:
Same readiness rule as immediate navigation, plus a short chance for a row that is already entering the build range (self-insert / follow-tail) so close-path can win when near. Still never falls back to shimmer-stitch.
_Avoid_: preferBuilt timeout → force stitch

**Message highlight**:
A transient attention wash on one present message row. Not membership in the selected set, and not a leave/reopen reading position.
_Avoid_: Message selection, selected-fill, Center Band

**Deferred highlight**:
A Message highlight whose target row is not yet a loaded Message with a built child. Held until that row exists, or dropped when superseded, the id is absent/error, a host jump does not request highlight, or the user drags. No wall-clock TTL; arm is from layout/data, not a pending ticker.
_Avoid_: Navigation load-gate, pending jump, pending Center Band, timeout TTL
