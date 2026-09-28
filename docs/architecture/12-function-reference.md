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

| Member                                     | Purpose                                   | Mutates                                               | Must not                                                  |
| ------------------------------------------ | ----------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------- |
| `jumpTo`                                   | Teleport anchor to id; optional tail-or-target decision (`tailFitFraction`); optional additive `pixelOffset` after the alignment seat | id, offset=`0`, alignment; optional highlight request; optional pixel offset | Assume visible row if absent                              |
| `addTailOrTargetListener` / `removeTailOrTargetListener` | Outcome of a tail-or-target `jumpTo` | listener list (dedup)                          | `setState` / navigate from the callback (runs in layout)  |
| `notifyTailOrTarget` (`@internal`)         | Dispatch the decided outcome              | — (snapshot; silent after dispose)                    | Call from app code                                        |
| `markTailFitDecided` (`@internal`)         | Drop the fraction after a target outcome  | `navigationPlacement` fraction (target/phase kept)    | Call from app code                                        |
| `jumpToCenterBand`                         | Place center-band ray at msg top + offset | id, pending Center Band apply; clears highlight       | Compose via `jumpTo`+`scrollBy`; assume visible if absent |
| `highlight`                                | Request Message highlight                 | pending highlight id; absent/error drops the slot     | Treat as navigation / origin write                        |
| `scrollBy`                                 | Programmatic pixel shift                  | offset; fade armed highlight / hard-clear pending     | Call with non-finite; expect Tier-1                       |
| `animateTo`                                | Smooth nav                                | alignment; animator drives offset                     | Call after dispose                                        |
| `applyScrollDelta`                         | Silent tick/clamp delta                   | offset                                                | Call from app code                                        |
| `reassignAnchor`                           | Silent id+offset                          | both                                                  | Notify listeners (it does not)                            |
| `holdNavigationPlacement`                  | Pending → held after landing on loaded row | `navigationPlacement` phase (no-op when `null`)       | Call before the placement landed                          |
| `releaseNavigationPlacement`               | Drop the armed placement, any kind/phase  | `navigationPlacement` → `null`                        | —                                                         |
| `syncNavigationPlacementTarget`            | Keep placement on clamped id              | `navigationPlacement` target (phase kept)             | —                                                         |
| `visibleRange` / `centerBand` / `isAtTail` | Listenables                               | deferred notify                                       | setState without deferral (already deferred)              |
| `notifyScrollEvent`                        | Emit typed event                          | —                                                     | Call from physics                                         |
| `dispose`                                  | Drop listeners / animator                 | all                                                   | —                                                         |

---

## `ChatDataSource` / `ChatScrollChunk`

| Member                               | Purpose                                      | Must not                                                 |
| ------------------------------------ | -------------------------------------------- | -------------------------------------------------------- |
| `fetchRange`                         | Load full-chunk span                         | Partial ranges; null placeholders in list                |
| `getMessage`                         | Exact slot lookup by id                      | Treat null as “no previous message”; auto-walk neighbors |
| `getPreviousPresentMessage`          | Previous neighbor ↓, skip confirmed-absent   | Use when you mean `id - 1` in conversation order         |
| `getNextPresentMessage`              | Next neighbor ↑, skip confirmed-absent       | Use when you mean `id + 1` in conversation order         |
| `updateMessage` / `updateMessages`   | Integrator edit — always emits update intent | Use `upsert*` for fetch refresh only                     |
| `statusOf`                           | dirty/absent/chunk status                    | —                                                        |
| `seedBoundaries`                     | Atomic boundary update                       | Piecemeal field writes on delete                         |
| `upsertMessage(s)`                   | Write slot + notify                          | Double `notifyDataChanged` after super                   |
| `invalidate`                         | Mark stale + clear absent                    | —                                                        |
| `chunkOf` / `firstIdOf`              | Chunk math                                   | Open-coded `>> 6` outside chunk file                     |
| `markAbsentSlot` / `clearAbsentSlot` | Per-slot absent flags (`0`/`1`) + count      | Mark non-null slot absent                                |
| `isFullyAbsent`                      | O(1) all-absent via absent-slot count        | —                                                        |

---

## `ChatChildManager` / `ChatScrollElement`

| Member                | Purpose                          | Must not                          |
| --------------------- | -------------------------------- | --------------------------------- |
| `buildChild`          | Inflate/update message           | Call outside layout callback      |
| `removeChildren`      | Deactivate messages              | —                                 |
| `buildFloatingHeader` | Inflate/remove sticky header     | Call from Tier-1                  |
| `buildChunkError`     | Inflate error tile               | —                                 |
| `removeChunkErrors`   | Deactivate error tiles           | —                                 |
| `buildOverlay`        | Loading/empty/none               | —                                 |
| `_buildWidget`        | Compose ChatRowChrome / selection | Put separator inside selection    |
| Skip-cache hit        | Reuse without `updateChild`      | Rely on deep equality of messages |

---

## `ChatFloatingHeaderController`

| Member                                                       | Purpose                        | Mutates                                     |
| ------------------------------------------------------------ | ------------------------------ | ------------------------------------------- |
| `scanTopDay`                                                 | Topmost visible bucket         | None (pure)                                 |
| `evaluateLayoutRebuild`                                      | Whether header widget rebuilds | `headerBucket`, `headerDate`, `headerDirty` |
| `tickForDayChange`                                           | Tier-1 day-change detect       | None                                        |
| `placeHeaderOffset`                                          | Header rest Y (`topPad`)       | None                                        |
| `invalidate` / `resetOnDataSourceChange` / `clearForOverlay` | Force/clear state              | header fields                               |

---

## `ChatScrollPhysics` (public value)

| Member                                         | Purpose                                                 | Must not                                   |
| ---------------------------------------------- | ------------------------------------------------------- | ------------------------------------------ |
| `ChatScrollPhysics(fling:, edgeEffect:)`       | Host choice of one fling + one edge effect              | Hold runtime state                         |
| `.stretch()`                                   | Spline fling + stretch                                  | Branch on platform                         |
| `.rubberBand()`                                | Decay fling + rubber-band                               | Branch on platform                         |
| `.clamped()`                                   | Spline fling + no edge effect                           | Branch on platform                         |
| `.forPlatform(platform:)`                      | The `null` default: OS-family table from `defaultTargetPlatform` | Read the theme or `ScrollConfiguration` |
| `ChatFling.spline(friction:)`                  | Android `OverScroller` spline; friction scales travel   | Grow variants outside the closed set       |
| `ChatFling.decay(decelerationRate:)`           | iOS decay via `FrictionSimulation(rate^1000)`           | Grow variants outside the closed set       |
| `ChatEdgeEffect.stretch(intensity:, …spring)`  | Android 12 stretch; pull response + return spring       | Grow variants outside the closed set       |
| `ChatEdgeEffect.rubberBand(resistance:, …spring)` | iOS translate; `d·c·x/(d+c·x)` pull + return spring  | Grow variants outside the closed set       |
| `ChatEdgeEffect.none()`                        | Hard clamp; fling ends at the pin                       | Paint anything                             |
| `==` / `hashCode`                              | Value equality; drives the equal-is-no-op swap          | Compare by identity                        |

## `ChatFlingMotion` (`@internal`)

| Member                        | Purpose                          | Must not               |
| ----------------------------- | -------------------------------- | ---------------------- |
| `startFling` / `cancelFling`  | Inertial scroll for its `fling`  | Emit controller events |
| `tickFling` / `flingVelocity` | Per-frame fling delta            | Touch layout           |

## `ChatScrollMotion` / `ChatEdgeEffectState` (`@internal`)

`ChatScrollMotion(physics)` builds one `fling` + one `edge` runtime; the
render object replaces it only on an unequal physics swap.

| `ChatEdgeEffectState` member | Purpose                                                              | Must not                                  |
| ---------------------------- | -------------------------------------------------------------------- | ----------------------------------------- |
| `claim(delta, viewportHeight, travel:)` | First claim on each drag or fling delta; may consume it or start a release | Run on wheel / animate deltas       |
| `pull`                       | Unconsumed drag dy past a reached pin                                | Feed mid-content travel                   |
| `onDragStart`                | Freeze (drag start or press catching a spring); idempotent           | Clear the painted effect                  |
| `onDragEnd(v)` → `bool`      | Release; answers whether a content fling may start                   | Start the fling itself                    |
| `absorbImpact`               | Fling hits a reached edge (incl. last travel frame)                  | Arm from rest on mid-content fling        |
| `tick` / `paintTransform`    | Advance spring; message-layer matrix or `null` at rest               | Mutate anchor                             |
| `isActive` / `isSpringing`   | Anything painted or animating / an autonomous spring runs            | —                                         |
| `reset`                      | Drop to rest (jump, animate, overlay, inset, swap)                   | Emit events                               |

## `ChatStretchOverscroll` (stretch strategy)

| Member                 | Purpose                                                              | Must not                                   |
| ---------------------- | -------------------------------------------------------------------- | ------------------------------------------ |
| `claim`                | Passes all through; >1 px reverse travel into content → release      | Release on sub-pixel travel or pin spill   |
| `onDragEnd`            | Reverse → release + fling allowed; same-dir → absorb; idle → soft spring | Slam back with inverted max fling velocity |
| `releaseIntoContent`   | Drop the pull; keep a short visual unwind                            | Move content                               |
| `paintTransform`       | Scale about the pressed edge (top for `s ≥ 0`, bottom otherwise)     | Paint under the precision tolerance        |

## `ChatRubberBandOverscroll` (rubber-band strategy)

| Member           | Purpose                                                                  | Must not                                   |
| ---------------- | ------------------------------------------------------------------------ | ------------------------------------------ |
| `pull` / `claim` | Map displacement → pull, add motion, map back; claim returns the rest past the pin | Depend on the path to a displacement |
| `onDragEnd`      | Flick toward content → keep displacement, fling allowed (unwound via `claim`); other displaced → spring at the layer's speed (velocity × band slope), fling blocked; at rest → allowed | Spring away a flick's momentum toward content |
| `absorbImpact`   | Spring from the pin with leftover velocity (≥ 50 px/s, uncapped)         | Arm on a fling that ran out at the pin     |
| `tick`           | Advance spring; stop at the pin                                          | Cross rest into the opposite edge          |
| `paintTransform` | Translate by `displacement`                                              | Scale                                      |

---

## `ChatAnimator`

| Member                                                                           | Purpose                                                          | Mutates                              |
| -------------------------------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------ |
| `animate`                                                                        | Start/replace animation                                          | Anchor (close start); flags          |
| `cancelAnimate`                                                                  | Abort without highlight                                          | Clears animate state                 |
| `tickAnimate`                                                                    | Close delta or stitch progress tick                              | offset (via return); stitch progress |
| `rebaseClosePathEnd`                                                             | Live retarget end offset                                         | start/end offsets                    |
| `takePendingSettleTargetId`                                                      | Consume settle hook                                              | pending id                           |
| `_completeAnimate`                                                               | Snap end, complete future                                        | anchor, highlight, completer         |
| `tryArmPendingHighlight` / `tickHighlight` / `clearHighlight` / `paintHighlight` | Wash arm/hold/fade; absent/error drops pending + controller slot | highlight fields                     |

---

## `RenderChatScrollView` — lifecycle / wiring

| Member                                  | Purpose                          |
| --------------------------------------- | -------------------------------- |
| `attach` / `detach`                     | Bind listeners, animator, ticker |
| `_seedTailNavigationOnAttach`           | Initial tail pin                 |
| `_invokeChildManagerLayout`             | Safe child inflate/remove        |
| `insertChild` / `removeChild`           | Message render map               |
| `insertChunkError` / `removeChunkError` | Error tile map                   |
| `invalidateFloatingHeader`              | Force header rebuild             |

## Layout

| Member                                                                          | Purpose                           | Order notes                                                            |
| ------------------------------------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------------- |
| `performLayout`                                                                 | Full Tier-2 pipeline              | See [Layout Pipeline](./04-layout-pipeline.md)                         |
| `_layoutOverlayMode`                                                            | Empty/loading                     | Clears scroll state                                                    |
| `_layoutFromAnchor`                                                             | Fan-out wrapper                   | Inside layout callback                                                 |
| `_fanOutFromAnchor`                                                             | Build/place children              | Before renorm/clamp                                                    |
| `_buildMessage` / `_buildChunkError`                                            | One child                         | Writes parent data; hands a `RenderChatRowChrome` its transition frame before layout |
| `_bucketOf` / `_startsDay`                                                      | Day grouping                      | Predecessor = `id-1` only today                                        |
| `_nextNonAbsentIdDown` / `Up`                                                   | Absent skip                       | Return `bound±1`                                                       |
| `_renormalizeAnchor`                                                            | Visible-origin rebase             | Skip on close path; skip on delete recovery                            |
| `_resolveTailOrTarget`                                                          | Decide an armed tail-or-target jump | Before `_applyNavigationPlacement`; first pass with the target loaded and built; re-fans when the listener moved the unread boundary |
| `_layOutNewestBelow`                                                            | Newest id + row for the fit span  | `null` when newest not reached / not loaded / too far; re-fans from the target body when newest is unbuilt |
| `_dispatchTailOrTarget`                                                         | Notify outcome in layout callback | Re-fans, consumes `_rowChromeChanged`, and cancels both rows' separator transitions when a listener moved the unread boundary |
| `_applyNavigationPlacement`                                                     | Seat target by kind; pending → held | Skip on close path; release alignment on newest; held snaps only on `reapplyHold` |
| `_isNavigationTargetChromeChange`                                               | Row chrome change on placement target | Before 6d; target among the changed rows (boundary move or moved transition frame); skips the row chrome hold when true |
| `_isNavigationTargetAnchored`                                                   | Placement target is the anchor    | Before 6d; with a held placement + moved top pad, skips the row chrome hold |
| `_startUnreadSeparatorTransitions`                                              | Boundary move → exit / enter legs | Before 6d, on the pass that sees the move; rows not laid out last frame change without a transition |
| `_recordRowChromeReference` / `_holdRowChromeReference`                         | Row chrome hold (6d)              | Record before fan-out; hold after pass-1 fan-out, exact comparison, then re-fan |
| `isUnreadSeparatorExiting`                                                      | Element query                     | Keeps the old boundary row's separator built until its exit ends       |
| `_closePathEndOffsetFor`                                                        | Close-path animate end            | Tail newest → pin top; else band align                                 |
| `_alignedTopForMessage`                                                         | Band alignment math               | Not true tail pin                                                      |
| `_clampBoundaries`                                                              | pinNewest/pinOldest               | Skip drag/bounce; single pin when content fits; delete-recovery guards |
| `_contentFitsInViewport`                                                        | Span ≤ scroll band                | Gates no-scroll mode — drag travel, fling, scrollbar                   |
| `_compensateBottomPaddingChange`                                                | Keyboard follow                   | Before fan-out                                                         |
| `_normalizeAnchorToKnownTail`                                                   | Pre-mount clamp                   | Before fan-out                                                         |
| `_recordLayoutBeforeDelete`                                                     | Capture band + deleted extent     | Before reassignment when anchor absent                                 |
| `_preserveViewportAfterDelete`                                                  | Band-stable scroll delta          | After pass-1 fan-out; sets recovery flags                              |
| `_scrollDeltaForDelete`                                                         | Delta decision tree               | Pure; see render doc comment                                           |
| `_shiftLayoutByScrollDelta`                                                     | applyScrollDelta + reposition     | Optional band-bottom follow-up ≤200px                                  |
| `_matchExpectedBandGap`                                                         | Gap correction before/after clamp | Skips off-screen push                                                  |
| `_skipRenormalizeDuringDeleteRecovery`                                          | One-pass renormalize block        | —                                                                      |
| `_bottomBandMessage`                                                            | Visible band probe                | Closest bottom to bottomEdge                                           |
| `_applyPendingTailPin` / `_markPinTailOnJumpIfNeeded` / `_cancelPendingTailPin` | Tail settle FSM                   | Before clamp                                                           |
| `_updateFloatingHeader`                                                         | Header rebuild/layout             | End of layout                                                          |
| `_gcPinnedDuringClosePath` / `_skipRenormalizeDuringClosePath`                  | Animate guards                    | —                                                                      |

## Tier-1 / gestures

| Member                                                                                                              | Purpose                                                             |
| ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_onTick`                                                                                                           | Full scroll composition                                             |
| `_repositionFromAnchor` / `_repositionMessagesOnly`                                                                 | Offset-only place                                                   |
| `_setOffset`                                                                                                        | Offset + divider opacity                                            |
| `_rangeNoLongerCovers`                                                                                              | Need layout?                                                        |
| `_onDragStart` / `Update` / `End`                                                                                   | Gesture → pending delta; edge freeze / release (fling gated by `onDragEnd`) | Edge effect only from unconsumed edge remainder                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_startFling` / `_cancelFling`                                                                                      | Fling lifecycle                                                     | Start no-op when content fits                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `_unconsumedOverscrollDelta` / `_cancelOverscroll`                                                                  | Overflow past pin travel → edge effect; missing box is not that edge |
| `physics` setter / `_edgeTransform` / `applyPaintTransform`                                                        | Unequal swap cancels fling + resets edge; one edge matrix for paint, hit, reported transform, `paintTop` |
| `_boundaryBox` / `_resolveAnchorBox`                                                                                | Boundary/anchor render boxes                                        |
| `handleEvent` / `hitTestChildren`                                                                                   | Pointer / scrollbar grab (strip hit-test on the last painted frame) / header / selection; press catches fling or edge spring; messages hit through `_edgeTransform` |
| `ChatSelectionPointer` / `_selectionMessageIdAt` / `_spanHitAt` / `_selectSpanChain`                                | Viewport-owned long-press, tap, select/unselect span                | Yield + fling-cancel suppress; span polarity vs selection snapshot; empty set ends the span; the pinned floating date header is not a hit (tap/long-press/span go through to the message); other non-message slots and non-selectable rows freeze the far end; non-selectable ids are omitted from the chain; chrome wrap follows `showsChrome` (`gutterOnly` without check); select-span growth and grow-direction auto-scroll stop at `selectionCap` (unselect ignores the cap); a refused grow bumps `capHits` once per wall; origin-absent aborts the span (set kept); `selectionAllowed` assign / `reapplySelectionAllowed` refilters the set and invalidates chrome wrap via `addSelectionAllowedListener` |
| `_onJump` / `_onScrollBy` / `_onDataChanged` / `_onBoundaryChanged`                                                 | Controller/DS reactions                                             |
| `_onAnimateSettled` / `_cancelAnimate` / `_clearHighlight`                                                          | Animate settle/cancel                                               |
| `_publishControllerState` / `_publishVisibleRange` / `_publishCenterBand` / `_publishIsAtTail` / `_computeIsAtTail` | Listenables                                                         |
| `_updateScrollSemantics` / `_computeCanRevealOlder` / `Newer`                                                       | A11y scroll actions                                                 |
| `_computeScrollbarProgress` / band helpers                                                                          | Thumb progress + length share from band-edge fractional ids |
| `_dragScrollbarTo`                                                                                                  | Grab position → band-top fractional id (`oldest + progress × (idCount − visible ids)`, frozen span share) → `jumpToFraction(id, fraction)` | Inverse of the band-metrics progress, so drag and paint share one mapping; skips an identical armed placement |
| `scrollbar` setter / `_endScrollbarGrab`                                                                            | Equal preset no-op; unequal ends the grab. Ending releases the navigation placement, starts the thumb settle, ensures the ticker, repaints (setter: per `shouldRepaint`) |
| `_paintScrollbar` / `ChatScrollbarRuntime.resolve`                                                                  | One frame per paint: rects from preset painter geometry and thumb motion (rest / grab / settle); cleared for `none` and fits here, for overlay mode in `_paintContents` |
| `ChatScrollbarRuntime.tryStartGrab` / `moveGrab` / `endGrab` / `tickSettle`                                         | Press on thumb keeps the grab offset; press on track centres the thumb; moves repaint the thumb under the pointer at the frozen length; release eases the rect back over `settleDuration` on the viewport ticker | `_stopTickerIfIdle` keeps the ticker while `isSettling`; `detach` resets all motion |

## Paint / debug

Paint walks children at `Offset(0, parentData.offset)` inside the edge
transform layer when the edge effect is active, header and scrollbar
on top outside it; far-path stitch applies per-child translation (not a viewport fade);
highlight paints over target row.
`_paintScrollbar` clears the scrollbar frame and paints nothing when the preset
is `none`, content fits, or the thumb would leave no travel; the painter draws
in viewport-local coordinates.

Debug getters (`debugChildCount`, `debugDividerOpacity`, etc.) and
`_fetchAnchorEvent` / `_scrollbarEvent` are diagnostics only.

---

## Ordering cheat sheet

**Layout:** compensate pad → record/reassign/purge → fan-out → preserve viewport →
renorm → align → tail flags → match band gap → clamp → re-fan → match gap → GC →
fetch → publish → header → highlight arm → rebase close path.

**Tick:** pending → fling → animate → span auto-scroll → edge claim (drag or
fling) → split unconsumed → apply consumed → reposition → renorm → clamp →
edge pull / absorb → stranded-edge release → edge tick → publish → header
tick → highlight/settle → paint or layout.
