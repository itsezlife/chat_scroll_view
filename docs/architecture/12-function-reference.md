---
type: Function Catalog
title: Function Reference
description: Exhaustive catalog of scroll-critical APIs and their contracts, including delete-recovery and short-content no-scroll helpers.
tags: [reference, api]
timestamp: 2026-07-04T00:00:00Z
---

# Function Reference

Per-function contracts for scroll work. Columns:

- **Mutates** — what state changes
- **Order** — must run before/after
- **Must not** — common violations

Cross-links: [Layout Pipeline](./04-layout-pipeline.md),
[Tier-1 Scroll](./05-tier1-scroll.md),
[Animation Integration](./11-animation-integration.md).

---

## `ChatScrollController`

| Member | Purpose | Mutates | Must not |
|--------|---------|---------|----------|
| `jumpTo` | Teleport anchor to id | id, offset=`0`, alignment | Assume visible row if absent |
| `scrollBy` | Programmatic pixel shift | offset | Call with non-finite; expect Tier-1 |
| `animateTo` | Smooth nav | alignment; animator drives offset | Call after dispose |
| `applyScrollDelta` | Silent tick/clamp delta | offset | Call from app code |
| `reassignAnchor` | Silent id+offset | both | Notify listeners (it does not) |
| `clearNavigationAlignment` | Drop pending align | alignment fields | — |
| `syncNavigationAlignmentTarget` | Keep align on clamped id | alignment message id | — |
| `visibleRange` / `isAtTail` | Listenables | deferred notify | setState without deferral (already deferred) |
| `notifyScrollEvent` | Emit typed event | — | Call from physics |
| `dispose` | Drop listeners / animator | all | — |

---

## `ChatDataSource` / `ChatScrollChunk`

| Member | Purpose | Must not |
|--------|---------|----------|
| `fetchRange` | Load full-chunk span | Partial ranges; null placeholders in list |
| `getMessage` | Exact slot lookup by id | Treat null as “no previous message”; auto-walk neighbors |
| `getPreviousPresentMessage` | Previous neighbor ↓, skip confirmed-absent | Use when you mean `id - 1` in conversation order |
| `getNextPresentMessage` | Next neighbor ↑, skip confirmed-absent | Use when you mean `id + 1` in conversation order |
| `updateMessage` / `updateMessages` | Integrator edit — always emits update intent | Use `upsert*` for fetch refresh only |
| `statusOf` | dirty/absent/chunk status | — |
| `seedBoundaries` | Atomic boundary update | Piecemeal field writes on delete |
| `upsertMessage(s)` | Write slot + notify | Double `notifyDataChanged` after super |
| `invalidate` | Mark stale + clear absent | — |
| `chunkOf` / `firstIdOf` | Chunk math | Open-coded `>> 6` outside chunk file |
| `markAbsentSlot` / `clearAbsentSlot` | Per-slot absent flags (`0`/`1`) + count | Mark non-null slot absent |
| `isFullyAbsent` | O(1) all-absent via absent-slot count | — |

---

## `ChatChildManager` / `ChatScrollElement`

| Member | Purpose | Must not |
|--------|---------|----------|
| `buildChild` | Inflate/update message | Call outside layout callback |
| `removeChildren` | Deactivate messages | — |
| `buildFloatingHeader` | Inflate/remove sticky header | Call from Tier-1 |
| `buildChunkError` | Inflate error tile | — |
| `removeChunkErrors` | Deactivate error tiles | — |
| `buildOverlay` | Loading/empty/none | — |
| `_buildWidget` | Compose DatedMessage / selection | Put separator inside selection |
| Skip-cache hit | Reuse without `updateChild` | Rely on deep equality of messages |

---

## `ChatFloatingHeaderController`

| Member | Purpose | Mutates |
|--------|---------|---------|
| `scanTopDay` | Topmost visible bucket | None (pure) |
| `evaluateLayoutRebuild` | Whether header widget rebuilds | `headerBucket`, `headerDate`, `headerDirty` |
| `tickForDayChange` | Tier-1 day-change detect | None |
| `dividerOpacityFor` | Fade math | None |
| `placeHeaderOffset` | Header Y (`topPad`) | None |
| `invalidate` / `resetOnDataSourceChange` / `clearForOverlay` | Force/clear state | header fields |

---

## `ChatScrollPhysics`

| Member | Purpose | Must not |
|--------|---------|----------|
| `startFling` / `cancelFling` | Inertial scroll | Emit controller events |
| `applyOverscrollResistance` | Drag damping | Use on fling/animate |
| `maybeStartBounceback` / `cancelBounceback` | Spring-back | Read both sides mid-bounce |
| `tickFling` / `tickBounceback` / `tick` | Per-frame deltas | Touch layout |

---

## `ChatAnimator`

| Member | Purpose | Mutates |
|--------|---------|---------|
| `animate` | Start/replace animation | Anchor (close start); flags |
| `cancelAnimate` | Abort without highlight | Clears animate state |
| `tickAnimate` | Close delta or far fade | offset (via return); `fadeOpacity` |
| `rebaseClosePathEnd` | Live retarget end offset | start/end offsets |
| `takePendingSettleTargetId` | Consume settle hook | pending id |
| `_completeAnimate` | Snap end, complete future | anchor, highlight, completer |
| `tryArmPendingHighlight` / `tickHighlight` / `clearHighlight` / `paintHighlight` | Post-settle tint | highlight fields |

---

## `RenderChatScrollView` — lifecycle / wiring

| Member | Purpose |
|--------|---------|
| `attach` / `detach` | Bind listeners, animator, ticker |
| `_seedTailNavigationOnAttach` | Initial tail pin |
| `_invokeChildManagerLayout` | Safe child inflate/remove |
| `insertChild` / `removeChild` | Message render map |
| `insertChunkError` / `removeChunkError` | Error tile map |
| `invalidateFloatingHeader` | Force header rebuild |

## Layout

| Member | Purpose | Order notes |
|--------|---------|-------------|
| `performLayout` | Full Tier-2 pipeline | See [Layout Pipeline](./04-layout-pipeline.md) |
| `_layoutOverlayMode` | Empty/loading | Clears scroll state |
| `_layoutFromAnchor` | Fan-out wrapper | Inside layout callback |
| `_fanOutFromAnchor` | Build/place children | Before renorm/clamp |
| `_buildMessage` / `_buildChunkError` | One child | Writes parent data |
| `_bucketOf` / `_startsDay` | Day grouping | Predecessor = `id-1` only today |
| `_nextNonAbsentIdDown` / `Up` | Absent skip | Return `bound±1` |
| `_renormalizeAnchor` | Visible-origin rebase | Skip on close path; skip on delete recovery |
| `_applyNavigationAlignment` | Snap to alignment | Skip on close path; skip newest |
| `_closePathEndOffsetFor` | Close-path animate end | Tail newest → pin top; else band align |
| `_alignedTopForMessage` | Band alignment math | Not true tail pin |
| `_clampBoundaries` | pinNewest/pinOldest | Skip drag/bounce; single pin when content fits; delete-recovery guards |
| `_contentFitsInViewport` | Span ≤ scroll band | Gates no-scroll mode — overscroll, drag, fling, scrollbar |
| `_compensateBottomPaddingChange` | Keyboard follow | Before fan-out |
| `_normalizeAnchorToKnownTail` | Pre-mount clamp | Before fan-out |
| `_recordLayoutBeforeDelete` | Capture band + deleted extent | Before reassignment when anchor absent |
| `_preserveViewportAfterDelete` | Band-stable scroll delta | After pass-1 fan-out; sets recovery flags |
| `_scrollDeltaForDelete` | Delta decision tree | Pure; see render doc comment |
| `_shiftLayoutByScrollDelta` | applyScrollDelta + reposition | Optional band-bottom follow-up ≤200px |
| `_matchExpectedBandGap` | Gap correction before/after clamp | Skips off-screen push |
| `_skipRenormalizeDuringDeleteRecovery` | One-pass renormalize block | — |
| `_bottomBandMessage` | Visible band probe | Closest bottom to bottomEdge |
| `_applyPendingTailPin` / `_markPinTailOnJumpIfNeeded` / `_cancelPendingTailPin` | Tail settle FSM | Before clamp |
| `_updateFloatingHeader` | Header rebuild/layout | End of layout |
| `_gcPinnedDuringClosePath` / `_skipRenormalizeDuringClosePath` | Animate guards | — |

## Tier-1 / gestures

| Member | Purpose |
|--------|---------|
| `_onTick` | Full scroll composition |
| `_repositionFromAnchor` / `_repositionMessagesOnly` | Offset-only place |
| `_setOffset` | Offset + divider opacity |
| `_rangeNoLongerCovers` | Need layout? |
| `_onDragStart` / `Update` / `End` | Gesture → pending delta | Update/end no-op when content fits |
| `_startFling` / `_cancelFling` | Fling lifecycle | Start no-op when content fits |
| `_maybeStartBounceback` / `_cancelBounceback` | Spring lifecycle | Start no-op when content fits |
| `_signedOverscroll` / `_overscrollOnSide` / `_applyOverscrollResistance` | Boundary physics inputs | Zero when content fits |
| `_boundaryBox` / `_resolveAnchorBox` | Boundary/anchor render boxes |
| `handleEvent` / `hitTestChildren` | Pointer / scrollbar / header / selection |
| `ChatSelectionPointer` / `_selectionMessageIdAt` / `_spanHitAt` / `_selectSpanChain` | Viewport-owned long-press, tap, select span | Yield + fling-cancel suppress; non-message slots freeze the far end |
| `_onJump` / `_onScrollBy` / `_onDataChanged` / `_onBoundaryChanged` | Controller/DS reactions |
| `_onAnimateSettled` / `_cancelAnimate` / `_clearHighlight` | Animate settle/cancel |
| `_publishControllerState` / `_publishVisibleRange` / `_publishIsAtTail` / `_computeIsAtTail` | Listenables |
| `_updateScrollSemantics` / `_computeCanRevealOlder` / `Newer` | A11y scroll actions |
| `_jumpToScrollbar` / `_computeScrollbarProgress` / band helpers | Scrollbar geometry |

## Paint / debug

Paint walks children at `Offset(0, parentData.offset)`, header and scrollbar
on top; far-path uses fade layer; highlight paints over target row.
`_paintScrollbar` returns immediately when content fits (no thumb travel).

Debug getters (`debugChildCount`, `debugDividerOpacity`, etc.) and
`_fetchAnchorEvent` / `_scrollbarEvent` are diagnostics only.

---

## Ordering cheat sheet

**Layout:** compensate pad → record/reassign/purge → fan-out → preserve viewport →
renorm → align → tail flags → match band gap → clamp → re-fan → match gap → GC →
fetch → publish → header → highlight arm → rebase close path.

**Tick:** pending → resistance → fling → animate → bounceback → apply delta →
reposition → renorm → clamp → publish → header tick → highlight/settle →
paint or layout.
