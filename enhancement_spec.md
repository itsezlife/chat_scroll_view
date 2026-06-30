# ChatScrollView — Implementation Spec

> **Revision 3** — incorporates ID-contract analysis, Telegram API research, absent-slot gap fix (cursor API superseded by `fetchRange` + absent-slot marking given per-chat sequential ID guarantee), navigation stack, KeepAlive, and scrollbar-clamping from the June 2026 design sessions.

***

## Architecture Overview

The viewport is anchor-based: layout fans out from `(anchorMessageId, anchorPixelOffset)` in both directions. No global content height is ever computed. A chunk is a fixed 64-slot array indexed by `id >> 6`; each slot maps to one per-chat sequential ID. The render object owns composited `OffsetLayer → PictureLayer` per message; scroll-only frames update only `OffsetLayer.offset` without re-recording.

### Key invariants

- `message.id` is **per-chat sequential**, starting at 1, composite PK `(chat_id, id)`. It is never a global auto-increment. This matches the confirmed Telegram model and the project schema.
- A chunk slot has **three distinct states**: `pending` (fetch not yet done), `absent` (server confirmed gap), `present` (message data held). `null` alone is ambiguous and must not be used as the only sentinel.
- The fetch API is **`fetchRange`-based**, not cursor-based. Per-chat sequential ID allocation ensures gaps are bounded by deletion counts; `fetchRange` with absent-slot marking is the complete and durable solution. No `fetchBefore`/`fetchAfter`/`fetchByIds` API is required.
- `fetchRange(fromId, toId)` **MUST** cover the full chunk boundary (`firstIdOf(chunkIndex)` … `chunk.lastId`). Partial-range fetches corrupt absent-slot marking.

***

## Dependency Order

```
Phase 0 (ID + Fetch contract) 
    └─► Phase 1 (Monolith decomposition)
            ├─► Phase 2 (API corrections)     ← parallel after Phase 1
            ├─► Phase 4 (Correctness fixes)   ← parallel after Phase 1
            └─► Phase 3 (New capabilities)    ← after Phase 2
```

**The "touched files" rule**: maintain a living list of files modified per phase. Before editing any file, check it does not appear on a different phase's active list.

**The "no behaviour change" rule**: Phases 0, 1, 4 must produce zero observable difference for existing consumers. All commits are verifiable by running the existing test suite unchanged.

**The "one breaking change" rule**: Phase 2 contains exactly one breaking change (PR-C1, typedef rename). All other Phase 2 PRs are additive.

***

## Phase 0 — ID Contract & Absent-Slot Fix

*Entry: nothing. Exit: ADR committed, absent-slot state in place, gap test suite green.*

This phase is prerequisite to everything. The chunk bit-shift arithmetic `id >> 6` permeates `render_chat_scroll_view.dart`, `chat_data_source_ext.dart`, and `chat_scroll_element.dart`. Any extraction that moves this code without settling the ID contract embeds the same wrong assumption in the new location.

### PR-0A — ID Contract ADR + Chunk Math Centralization

**Why first**: Every downstream PR moves code containing chunk arithmetic. The decision must be written before any code moves.

**Decision (confirmed by Telegram API research and per-chat ID analysis)**:
- `message.id` is per-chat sequential integer, composite PK `(chat_id, id)`, starting at 1.
- IDs are **not** globally auto-incremented across chats. Each chat has its own independent sequence.
- IDs are **not** dense — deletions leave permanent gaps. A gap is indistinguishable from "unloaded" without an explicit absent marker.
- The `id >> 6` chunk key is **retained**. Per-chat sequential ID allocation makes this correct and sufficient: gaps are bounded by deletion counts, not arbitrary global-sequence skips.
- `fetchRange` is **retained**. No cursor-based fetch API is needed.

**Tasks**:

1. Write `docs/adr/001-message-id-contract.md`:
   - Per-chat sequential ID, composite PK, starts at 1
   - IDs are sparse; gaps are permanent after deletion
   - `id >> 6` chunk key is correct for per-chat sequential IDs; retained
   - Confirmed match with Telegram TDLib `message.id` per-chat scope

2. Ensure `kChunkSize`, `chunkOf(id)`, `firstIdOf(chunkIndex)`, `lastIdOf(chunkIndex)` are centralized in `chat_scroll_chunk.dart` with documented invariants. These are correct for the retained `id >> 6` model.

3. Write unit tests covering: single-message chat, 63-message chat (one partial chunk), a chat with a 900-ID gap between two messages, a chat where the oldest message has ID 1 and the newest has ID 10000 with many deletions in between.

**Exit condition**: ADR merged; chunk math centralized; unit tests green.

***

### PR-0B — Absent-Slot State + Fan-Out Skipping

**Why this exists**: `fetchRange(fromId, toId)` fetches the chunk correctly, but when the server returns fewer messages than IDs in the range (because some IDs were deleted), those slots stay `null`. Since `null` currently means both "not loaded yet" and "server confirmed nothing here", the viewport renders permanent skeletons for IDs that will never have data.

The fix is a client-side state change: distinguish `absent` (server confirmed gap) from `pending` (fetch not yet done) using a 64-bit bitmask in `ChatScrollChunk`. No new fetch methods, no backend changes, no breaking API change.

> **Why not cursor-based fetch?** Per-chat sequential ID allocation ensures gaps are bounded by deletion counts — not arbitrary global-sequence skips. `fetchRange` already covers the full chunk boundary. Absent-slot marking after `fetchRange` resolves is the complete and durable solution. `fetchBefore`/`fetchAfter`/`fetchByIds` would be architectural overhead without solving a real problem in this ID model.

**`ChatScrollChunk` addition**:

```dart
/// Three-way slot state. Using a parallel bitmask keeps the message list dense.
class ChatScrollChunk {
  // ... existing fields unchanged ...

  /// 64-bit bitmask: bit N set → slot N is permanently absent.
  /// Cleared on chunk invalidation. Set by absent-marking pass after fetchRange.
  int _absentMask = 0;

  bool isAbsentSlot(int slot) => (_absentMask >> slot) & 1 == 1;
  void markAbsentSlot(int slot) => _absentMask |= 1 << slot;
  void clearAbsentMask() => _absentMask = 0;

  /// True when all 64 slots are confirmed absent (_absentMask == -1).
  /// O(1) check; used by fan-out to skip entire all-absent chunks.
  bool get isFullyAbsent => _absentMask == -1;
}
```

**`ChatMessageStatus` addition**:

```dart
/// Permanently absent — server confirmed this message does not exist.
/// Callers MUST NOT render loading UI. Return SizedBox.shrink() or nothing.
static const ChatMessageStatus absent = ChatMessageStatus._(1 << 3);
bool get isAbsent => contains(ChatMessageStatus.absent);
```

**Absent-marking pass** (in `_executeFetch` success handler, after slots are filled):

```dart
for (final ci in _fetchingChunks) {
  final chunk = _chunks[ci]!;
  final firstId = ChatScrollChunk.firstIdOf(ci);
  for (var slot = 0; slot < ChatScrollChunk.kSize; slot++) {
    if (chunk.messages[slot] != null) continue;
    final id = firstId + slot;
    if (_withinConversationBounds(id)) chunk.markAbsentSlot(slot);
  }
}
```

**`fetchRange` full-chunk invariant** (documentation + debug assertion):

```
fetchRange(fromId, toId) MUST be called with:
  fromId == ChatScrollChunk.firstIdOf(chunkIndex)
  toId   == chunk.lastId
Partial-range fetches within a chunk are not supported — the absent-marking
pass would incorrectly mark valid-but-unfetched slots as absent.
```

**`RenderChatScrollView` fan-out change**: When `statusOf(id).isAbsent`, advance past the contiguous absent run (using the bitmask) and continue fan-out — do not break. All-absent chunks are detected via `isFullyAbsent` and skipped in O(1). Absent slots render at zero height, so scrollbar math derived from content height is automatically correct.

**`ChatMessageBuilder` typedef doc update**:

```
[message] is null in two situations:
  - status.isFetching || status.isDirty → return shimmer/placeholder
  - status.isAbsent → ID does not exist; return SizedBox.shrink() or nothing
```

**Exit condition**: Widget test with a gapped message sequence (IDs 1, 2, 500, 501, 999) shows no skeletons for absent IDs; scrollbar thumb position correct; zero regressions in dense-ID conversations.

***

### PR-0C: Chunk Math + Absent-Slot Verification Test Suite

**Entry condition:** PR-0A merged.
**Exit condition:** Parametric unit tests for chunk boundary arithmetic and absent-slot state pass in CI.

**Tasks:**

1. Add `test/chat_scroll_chunk_test.dart` with parametric cases:
   - `chunkOf(0) == 0`, `chunkOf(63) == 0`, `chunkOf(64) == 1`
   - `firstIdOf(0) == 0`, `firstIdOf(1) == 64`
   - `lastId` property: chunk index 0 `lastId == 63`
   - Large sparse gap: `chunkOf(1000) == 15`, `chunkOf(4000) == 62`
   - Absent mask: `markAbsentSlot` / `isAbsentSlot` round-trip; `isFullyAbsent` when all 64 bits set; `clearAbsentMask` resets to 0.
   - Boundary message after bulk delete: IDs 4000–4099 absent — slots marked absent, `isFullyAbsent` true for the affected chunk.

2. Add edge-case tests for `ChatDataSource.getMessage` with sparse IDs:
   - `getMessage(100)` returns correctly when IDs 101–198 are null in chunk 1.
   - Absent-marking pass: after `fetchRange` returns sparse results, null slots within conversation bounds are absent; null slots outside bounds remain pending.

**Acceptance criteria:** All new tests pass. Zero regressions in existing suite.

***

## Phase 1 — Monolith Decomposition

**Rule:** One extraction per PR. Each PR must leave `render_chat_scroll_view.dart`
passing the full existing test suite before the next PR opens.

### PR-1A: Extract `ChatScrollPhysics`

**Entry condition:** Phase-0 PRs merged.
**Files created:** `src/chat_scroll/chat_scroll_physics.dart`
**Files modified:** `render_chat_scroll_view.dart`

**What moves:**

| Field / Method | Current location | Destination |
|---|---|---|
| `simulation` | render object | `ChatScrollPhysics` |
| `flingStartTime`, `lastFlingValue` | render object | `ChatScrollPhysics` |
| `bouncebackActive`, `bouncebackStartTime` | render object | `ChatScrollPhysics` |
| `bouncebackInitialOverscroll`, `bouncebackSide` | render object | `ChatScrollPhysics` |
| `kOverscrollMax`, `kOverscrollBounceDuration` | render object (static) | `ChatScrollPhysics` constructor params |
| `tickFling()`, `startFling()`, `cancelFling()` | render object | `ChatScrollPhysics` |
| `tickBounceback()`, `maybeStartBounceback()` | render object | `ChatScrollPhysics` |
| `applyOverscrollResistance()` | render object | `ChatScrollPhysics` |

**Interface contract:**

```dart
/// Returns the scroll delta to apply this tick, or 0.0 when idle.
/// Owns fling simulation and bounceback spring.
class ChatScrollPhysics {
  ChatScrollPhysics({
    required this.onDelta,        // void Function(double delta)
    double overscrollMax = 200.0,
    Duration bounceDuration = const Duration(milliseconds: 200),
  });

  bool get isFlinging;
  bool get isBouncing;
  void startFling(double velocity);
  void cancelFling();
  void maybeStartBounceback(double overscroll, BouncebackSide side);
  void cancelBounceback();
  double tick(Duration elapsed);   // returns delta; 0.0 when nothing running
}
```

`BouncebackSide` enum moves into this file. The render object holds a `ChatScrollPhysics`
instance and calls `physics.tick(elapsed)` from `onTick`, receiving the delta back.
`kOverscrollBounceSide` constant stays with `BouncebackSide`.

**Key constraint:** `LayerHandle` and `TickerProvider` stay on the render object.
`ChatScrollPhysics` is a pure Dart class with no Flutter framework dependency.

**Acceptance criteria:**
- Existing fling + bounceback behaviour is pixel-identical (verified by golden tests if
  available, or by manual QA checklist).
- `ChatScrollPhysics` has its own unit test: fling settles, bounceback snaps, resistance
  scales correctly.

***

### PR-1B: Extract `ChatChunkFetchScheduler`

**Entry condition:** PR-1A merged.
**Files created:** `src/chat_scroll/chat_chunk_fetch_scheduler.dart`
**Files modified:** `render_chat_scroll_view.dart`, `chat_data_source.dart`

**What moves:**

| Field / Method | Destination |
|---|---|
| `pollTimer`, `lastScrollTs` | `ChatChunkFetchScheduler` |
| `jumpFetchPending`, `jumpFetchDispatchDetached` | `ChatChunkFetchScheduler` |
| `layoutMinChunk`, `layoutMaxChunk` | `ChatChunkFetchScheduler` |
| `scheduleFetchPoll()`, `onPollTick()` | `ChatChunkFetchScheduler` |
| `maybeDispatchJumpFetch()` | `ChatChunkFetchScheduler` |
| `rangeHasPendingChunks` | `ChatChunkFetchScheduler` |
| `evictChunks()` | `ChatChunkFetchScheduler` |

**Dual-dispatch fix (previously Phase 4 E1) — done here:**
`maybeDispatchJumpFetch` currently dispatches via both `scheduleMicrotask` and
`addPostFrameCallback`. The root cause is documented in the render object source.
During extraction, replace both paths with a single `addPostFrameCallback`.
If the original race recurs in testing, document the specific reproduction steps
before reinstating the microtask path. The scheduler's callback contract:
`void Function(int minChunk, int maxChunk) requestRange` — the scheduler calls
back into the data source through this interface only, never directly.

**Interface contract:**

```dart
class ChatChunkFetchScheduler {
  ChatChunkFetchScheduler({
    required ChatDataSource dataSource,
    required void Function(int min, int max) requestRange,
    Duration pollInterval = const Duration(milliseconds: 150),
  });

  int get layoutMinChunk;
  int get layoutMaxChunk;
  void onLayoutComplete(int minChunk, int maxChunk);
  void onJump();           // resets debounce, sets jumpFetchPending
  void markScrollActive();
  void dispose();
}
```

**Acceptance criteria:** Poll timing, jump-fetch dispatch, and LRU eviction behaviour
are unchanged. New unit test: scheduler calls `requestRange` with correct chunk bounds
after jump; does not call it when all chunks are valid.

***

### PR-1C: Extract `ChatFloatingHeaderController`

**Entry condition:** PR-1B merged.
**Files created:** `src/chat_scroll/chat_floating_header_controller.dart`
**Files modified:** `render_chat_scroll_view.dart`

**What moves:**

| Field / Method | Destination |
|---|---|
| `headerBucket`, `headerDate`, `headerDirty` | `ChatFloatingHeaderController` |
| `scanTopDay()` | `ChatFloatingHeaderController` |
| `updateFloatingHeader()` | `ChatFloatingHeaderController` |
| `tickFloatingHeader()` | `ChatFloatingHeaderController` |
| `placeFloatingHeader()` | `ChatFloatingHeaderController` |
| `dividerOpacityFor()` | `ChatFloatingHeaderController` |
| `kHeaderFallbackHeight`, `kDividerFadeBand` | constants on controller |

The controller does **not** own `floatingHeader` (the `RenderBox`). It takes
`children` and `topPad` as parameters to its methods — it reads, never owns.

**Acceptance criteria:** Floating header rebuild, day-change detection, and divider
fade behaviour are unchanged.

***

### PR-1D: Extract `ChatAnimator`

**Entry condition:** PR-1C merged.
**Files created:** `src/chat_scroll/chat_animator.dart`
**Files modified:** `render_chat_scroll_view.dart`

**What moves:**

| Field / Method | Destination |
|---|---|
| `animateCompleter`, `animateTargetId` | `ChatAnimator` |
| `animateAlignment`, `animateStartOffset`, `animateEndOffset` | `ChatAnimator` |
| `animateStartTime`, `animateDuration`, `animateCurve` | `ChatAnimator` |
| `farAnimateActive`, `farAnimateJumped` | `ChatAnimator` |
| `highlightTargetId`, `highlightStartTime` | `ChatAnimator` |
| `highlightFactor`, `highlightColor`, `highlightDuration` | `ChatAnimator` |
| `tickAnimate()`, `tickHighlight()` | `ChatAnimator` |
| `clearHighlight()`, `paintHighlight()` | `ChatAnimator` |
| `cancelAnimate()` | `ChatAnimator` |

**`fadeOpacity` and `fadeLayer` stay on the render object.** The animator returns
an opacity value from `tickAnimate(elapsed)` and the render object applies it to
`fadeLayer`. This keeps `LayerHandle` out of the pure animator class.

`ChatAnimator` implements `ChatScrollAnimator` (currently implemented by
`RenderChatScrollView`). The render object delegates `animate()` to its
`ChatAnimator` instance.

**`@internal` contract documentation (previously Phase 4 E3) — added here:**
Each `ChatChildManager` method gets the doc comment:
```dart
/// Must only be called from within [invokeLayoutCallback]. Calling
/// from any other context will assert in debug mode.
```
Add `bool _insideLayoutCallback` debug flag to `ChatScrollElement` asserting
true when any `ChatChildManager` method is entered.

**Acceptance criteria:** `animateTo` close-path, far-path crossfade, and highlight
fade are pixel-identical. Unit test: highlight opacity progresses from 1.0 → 0.0
over `highlightDuration`.

***

### PR-1E: Extract `ChatRangeFetch` from `ChatDataSource`

**Entry condition:** PR-1D merged. Lower priority — may be deferred after Phase 2.
**Files created:** `src/chat_scroll/chat_range_fetch.dart`
**Files modified:** `chat_data_source.dart`

The fetch state machine (`_fetchToken`, `_retryTimer`, `_fetchRetryStep`,
`_fetchingMinChunk`, `_fetchingMaxChunk`, `_fetchingChunks`, `_executeFetch`,
`_cancelFetch`, `requestChunks`) moves into a `ChatRangeFetch` that
`ChatDataSource` owns as a private field. `ChatDataSource` exposes only the
public-facing entry points (`requestChunks`, `cancelFetch`, `retryChunk`,
`invalidate`), delegating to `ChatRangeFetch` internally.

**Why:** `ChatRangeFetch` is the only part of `ChatDataSource` that cannot be
unit-tested without subclassing. Extracting it enables isolated tests for backoff,
token invalidation, and retry logic with a fake `fetchRange`.

**Acceptance criteria:** All `ChatDataSource` tests pass unchanged. New unit tests
for `ChatRangeFetch`: exponential backoff delays, token cancellation on range change,
`fetchingChunks` tracking.

***

## Phase 2 — Public API Corrections

**Entry condition:** All Phase-1 PRs (1A–1D minimum) merged.
**These PRs are independent of each other and may be opened in parallel.**

***

### PR-C1: Decouple `groupBy` from `dateSeparatorBuilder` *(breaking)*

**Files modified:** `chat_scroll_view.dart`, `chat_scroll_element.dart`

**Change:** Rename separator builder typedef:
```dart
// Before
typedef ChatDateSeparatorBuilder = Widget Function(BuildContext, DateTime);

// After
typedef ChatGroupSeparatorBuilder =
    Widget Function(BuildContext context, Object bucket, DateTime firstMessageDate);
```

The new signature receives `bucket` (the raw `groupBy` key) and
`firstMessageDate` (the `createdAt` of the first message in that group).
`_defaultGroupBy` stays as a sensible default (bucket by calendar day).

`dateSeparatorBuilder` was silently ignored when `groupBy` returned a non-DateTime
bucket. This is fixed: the builder always receives the actual bucket key.

**Migration note in CHANGELOG:** Callers that used the old typedef must update
their callback signature. The `date` parameter was previously `message.createdAt`;
it is now `firstMessageDate` with the same value when `groupBy` returns `DateTime`.

**Acceptance criteria:** Existing date-separator behaviour is identical when using
`DateTime` buckets. Custom bucket keys now correctly reach the builder.

***

### PR-C2: `ChatKeyboardShortcuts` controller consolidation

**Files modified:** `chat_keyboard_shortcuts.dart`, `chat_scroll_controller.dart`

Remove the standalone `dataSource` parameter from `ChatKeyboardShortcuts`.
Add to `ChatScrollController`:

```dart
/// Oldest message ID currently known to the wired data source.
/// Null before first fetch. Read-only passthrough — updates whenever
/// the data source calls [seedBoundaries].
int? get oldestKnownId;

/// Newest message ID currently known to the wired data source.
int? get newestKnownId;
```

These are populated by `RenderChatScrollView` which already listens to
`dataSource.addBoundaryListener`. The keyboard widget reads boundary IDs
from the same controller instance that owns the viewport's scroll state,
eliminating the sync hazard where `dataSource` and the wired data source
diverge after a data-source swap.

**`lineExtent` derivation:** Publish `averageMessageHeight` as a
`ValueListenable<double?>` on the controller. The render object computes
`totalBuiltHeight / builtCount` during `performLayout` and pushes it through
a `_DeferredValueNotifier`. `ChatKeyboardShortcuts` uses it as the default
`lineExtent` fallback, replacing the hardcoded 60px. The 60px stays as a
pre-first-layout sentinel only.

**Acceptance criteria:** `ChatKeyboardShortcuts` compiles without a `dataSource`
parameter. Boundary-boundary ID reads are always consistent with the viewport's
wired source. `lineExtent` dynamically tracks average message height after first
layout.

***

### PR-C3: Scrollbar visual redesign — loaded-region map

**Files modified:** `chat_scrollbar.dart`, `render_chat_scroll_view.dart`

**Motivation (from design session):** The current scrollbar maps linearly between
`oldestKnownId` and `newestKnownId`. After a reply-jump, a second loaded island
exists. A simple clamp-to-contiguous-range breaks when multiple islands exist.
The correct model is **visual honesty**: the scrollbar track shows loaded regions
as bright segments and unloaded regions as dim segments. The thumb can still be
dragged anywhere (ephemeral jump + fetch), but the user can see at a glance what
is loaded.

**New type:**

```dart
/// An inclusive ID range that is currently loaded (chunk status = valid).
typedef ChatLoadedRange = ({int firstId, int lastId});
```

**Changes to `ChatScrollbar`:**

```dart
// New theme object (replaces hardcoded colors)
class ChatScrollbarTheme {
  const ChatScrollbarTheme({
    this.thumbColor = const Color(0x66000000),
    this.thumbDraggingColor = const Color(0x99000000),
    this.trackLoadedColor = const Color(0x1A000000),
    this.trackUnloadedColor = const Color(0x0D000000),
  });
  final Color thumbColor;
  final Color thumbDraggingColor;
  final Color trackLoadedColor;
  final Color trackUnloadedColor;
}
```

`ChatScrollbar.paint` gains a `List<ChatLoadedRange> loadedRanges` parameter
and `int totalSpan` (= `newestKnownId - oldestKnownId`). It paints:
1. Dim full track (unloaded colour).
2. For each loaded range, a bright segment at the proportional track position.
3. Thumb overlaid at `progress`.

**Changes to `RenderChatScrollView`:**

- `scrollbarProgress` remains the same linear interpolation between oldest and
  newest — it represents the thumb's absolute position in conversation space.
- New method `_computeLoadedRanges()` walks `dataSource.chunks`, groups
  contiguous valid chunks into `ChatLoadedRange` records, and returns the list.
  Called once per paint tick (not per layout — chunks change only on fetch events).
- The loaded-range list is passed to `ChatScrollbar.paint`.

**`ChatScrollbarTheme`** is an optional parameter on `ChatScrollView` with a
system-appropriate default that derives from `Theme.of(context).brightness`.

**Scrollbar progress accuracy (previously Phase 4 E2):**
The `scrollbarProgress` formula gains a sub-chunk fractional component:
```dart
final slotHeight = anchor?.size.height ?? 60.0;
final fractionalId = anchorId - (anchorPixelOffset / slotHeight);
return (fractionalId - oldest) / range;
```
This is identical to the existing formula and is already implemented. No change
needed — confirmed by reading the source. Accuracy note added to doc comment:
progress is an approximation for the unbuilt extent.

**Acceptance criteria:**
- Scrollbar thumb position is unchanged from consumer perspective.
- Loaded regions paint visually distinct from unloaded regions.
- `ChatScrollbarTheme` applies correctly in both light and dark mode.
- Unit test: `_computeLoadedRanges` correctly collapses adjacent valid chunks into
  single ranges and separates non-adjacent islands.

***

### PR-C4: `ChatSelectionController` data-source swap guard

**Files modified:** `chat_scroll_view.dart` (`updateRenderObject`)

In `ChatScrollView.updateRenderObject`, when `dataSource` changes and a
`selectionController` is wired with active selection:

```dart
if (renderObject.dataSource != dataSource) {
  if (widget.selectionController?.isSelectionMode == true) {
    widget.selectionController!.clear();
    assert(() {
      debugPrint(
        'ChatScrollView: dataSource swapped while selection was active. '
        'Selection cleared automatically.',
      );
      return true;
    }());
  }
  renderObject.dataSource = dataSource;
}
```

The existing documentation footgun note in `ChatSelectionController` is retained
but updated to reference this automatic behaviour.

**Acceptance criteria:** No silent selection-state mismatch after data-source swap.
Debug warning appears in debug mode. No change in release mode.

***

### PR-C5: `ChatScrollController` binding interface split

**Files created:** `src/chat_scroll/chat_scroll_controller_binding.dart`
**Files modified:** `chat_scroll_controller.dart`, `render_chat_scroll_view.dart`

**Problem:** `@internal` setters (`animator`, `visibleRange` setter, `isAtTail` setter,
`flingCancelSuppressesLongPress` setter, `reassignAnchor`, `applyScrollDelta`,
`syncNavigationAlignmentTarget`, `clearNavigationAlignment`) sit on the public
class. `@internal` from `package:meta` is analyzer-only — external packages can
still call them.

**Solution:** Extract a `ChatScrollControllerBinding` interface:

```dart
/// Viewport-only binding interface. Not part of the public API.
/// [RenderChatScrollView] accesses the controller through this interface.
/// External consumers should never cast to this type.
@internal
abstract interface class ChatScrollControllerBinding {
  set animator(ChatScrollAnimator? value);
  set visibleRange(ChatVisibleRange? value);
  set isAtTail(bool value);
  set flingCancelSuppressesLongPress(bool value);
  void reassignAnchor(int messageId, double pixelOffset);
  void applyScrollDelta(double delta);
  void syncNavigationAlignmentTarget(int resolvedId);
  void clearNavigationAlignment();
  double get navigationAlignment;
  int? get navigationAlignmentMessageId;
}
```

`ChatScrollController` implements both its existing public interface and
`ChatScrollControllerBinding`. `RenderChatScrollView` casts to
`ChatScrollControllerBinding` internally. The public `ChatScrollController` type
exposed to consumers has no `@internal` members visible.

**Acceptance criteria:** `dart analyze` produces no new public-API warnings.
External consumers cannot accidentally call internal setters without an explicit
cast (which is clearly their own fault).

***

### PR-C6: `notifyDataChanged` double-notify guard

**Files modified:** `chat_data_source.dart`

Mark `notifyDataChanged` `@nonVirtual`:

```dart
@protected
@nonVirtual
void notifyDataChanged() { ... }
```

Add to class doc:
> Subclasses must not call `notifyDataChanged()` after delegating to
> `super.upsertMessage()` or `super.upsertMessages()` — the base class
> already calls it. Calling it again fires listeners twice for a single
> logical state change.

**Acceptance criteria:** `@nonVirtual` annotation present. `dart analyze` warns
if any subclass attempts to override `notifyDataChanged`.

***

## Phase 3 — New Capabilities

**Entry condition:** All Phase-2 PRs merged.

***

### PR-D1: Navigation history stack ("Jump back to origin")

**Files modified:** `chat_scroll_controller.dart`

```dart
final _navigationStack = <({int id, double offset})>[];

/// Push the current anchor position onto the navigation stack.
/// Called automatically by the viewport before a reply-jump or search-jump.
/// Consumer UI (a FAB) observes [canPopPosition] and calls [popPosition].
@internal
void pushPosition() {
  _navigationStack.add((id: _anchorMessageId, offset: _anchorPixelOffset));
}

/// Whether a previously pushed position exists to return to.
bool get canPopPosition => _navigationStack.isNotEmpty;

/// Jump back to the last pushed position and remove it from the stack.
void popPosition() {
  if (_navigationStack.isEmpty) return;
  final prev = _navigationStack.removeLast();
  jumpTo(prev.id);
  // Offset is restored silently on the next layout via reassignAnchor
  // once the target chunk is loaded; store it as pending navigation offset.
}
```

`pushPosition` is called by `RenderChatScrollView.onJump` when the jump distance
exceeds `jumpGapThreshold` (introduced in PR-D3). `canPopPosition` drives a
`ValueListenable<bool>` so the consumer FAB can listen reactively.

**Acceptance criteria:** Jumping far and calling `popPosition` returns to the
captured position. Stack is cleared on `dispose`. Unit test covers push/pop/empty
behaviour.

***

### PR-D2: Per-message semantics builder

**Files modified:** `chat_scroll_view.dart`, `chat_scroll_element.dart`,
`render_chat_scroll_view.dart`

Add to `ChatScrollView`:

```dart
typedef ChatMessageSemanticsBuilder =
    SemanticsConfiguration Function(BuildContext, int id, IChatMessage?);

/// Optional. When set, each message is wrapped in a [Semantics] widget
/// configured by this builder. Provides per-message accessibility labels,
/// hints, and custom actions.
final ChatMessageSemanticsBuilder? semanticsBuilder;
```

In `ChatScrollElement.buildWidget`, when `semanticsBuilder` is non-null, wrap
content in `Semantics(container: true, ...)` with caller-configured properties.

In `RenderChatScrollView.describeSemanticsConfiguration`, supplement existing
`onScrollUp`/`onScrollDown` with:
- `onScrollToStart` → `jumpTo(oldestKnownId ?? anchorMessageId)`
- `onScrollToEnd` → `jumpTo(newestKnownId ?? anchorMessageId)`

**Acceptance criteria:** Screen reader announces per-message labels. Scroll
semantic actions reach oldest/newest correctly.

***

### PR-D3: Contextual eviction on far jump (Telegram-style window)

**Files modified:** `chat_data_source.dart`, `render_chat_scroll_view.dart`,
`chat_chunk_fetch_scheduler.dart`

**Motivation (from design session):** Telegram's scrollbar works because a
loaded window is always a single contiguous range. Disjoint islands are prevented
by evicting the old window on every far jump. The scrollbar then honestly maps
the loaded window.

**New method on `ChatDataSource`:**

```dart
/// Evict all chunks outside [centerChunk ± keepRadius].
/// Never evicts the anchor chunk or any currently-fetching chunk.
/// Calls [notifyDataChanged] once after the pass if anything changed.
@internal
void evictToWindow(int centerChunk, int keepRadius) {
  if (_disposed) return;
  bool changed = false;
  for (final key in _chunks.keys.toList()) {
    if ((key - centerChunk).abs() > keepRadius) {
      _chunks.remove(key);
      changed = true;
    }
  }
  if (changed) notifyDataChanged();
}
```

**Eviction decision function in `RenderChatScrollView.onJump`:**

```dart
void _maybeEvictOnJump(int targetId) {
  final targetChunk = ChatScrollChunk.chunkOf(targetId);
  final anchorChunk = ChatScrollChunk.chunkOf(controller.anchorMessageId);

  // Already loaded — no eviction needed.
  if (dataSource.chunks[targetChunk]?.status.isValid == true) return;

  // Target is within the near-fetch radius — let poll handle it.
  final nearRadius = (cacheExtent / ChatScrollChunk.kSize).ceil();
  final distance = (targetChunk - anchorChunk).abs();
  if (distance <= nearRadius) return;

  // Below threshold — bridging is cheap, no context switch.
  const jumpGapThreshold = 8; // 512 messages
  if (distance < jumpGapThreshold) return;

  // Far jump — evict old window, establish new one.
  final keepRadius = (dataSource.maxChunks / 2).floor();
  dataSource.evictToWindow(targetChunk, keepRadius);
}
```

**Order of operations in `onJump`:**
1. `cancelFling()`
2. `cancelAnimate()`
3. `_maybeEvictOnJump(targetId)` ← new
4. `clearHighlight()`
5. `cancelBounceback()`
6. `jumpFetchPending = true`
7. `markNeedsLayout()`

**`pushPosition` integration:** Call `controller.pushPosition()` inside `onJump`
before step 3, when eviction is triggered — i.e., only on true far jumps.

**Scrollbar behaviour after eviction:** With a single contiguous window, the
`_computeLoadedRanges()` method (PR-C3) naturally returns a single range. The
track shows one bright segment. The thumb sits within it. Dragging past the
bright segment triggers a fetch and the window expands — Telegram-style.

**Invariant maintained:** `nearRadius ≤ jumpGapThreshold ≤ keepRadius`.
Assert this in debug mode when the three values are configured.

**Acceptance criteria:**
- Far jump to an unloaded chunk evicts old window; new fetch covers target.
- Near jump (within threshold) does not evict anything.
- Jump to an already-loaded chunk does not evict anything.
- Jump arriving while a fling is in progress: fling cancelled before eviction.
- Anchor pointing at an evicted/null chunk after eviction: `renormalizeAnchor`
  correctly walks to the nearest non-null neighbour.
- Scrollbar shows single bright region after eviction + load.
- Unit tests for all five cases above.

***

### PR-D4: `KeepAlive` integration

**Entry condition:** PR-D3 merged (eviction semantics must be stable first).
**Files created:** `src/chat_scroll/chat_keep_alive_controller.dart`
**Files modified:** `render_chat_scroll_view.dart`, `chat_scroll_element.dart`,
`chat_scroll_view.dart`

```dart
/// Prevents specific message IDs from being evicted from the widget tree,
/// even when they scroll outside the build extent.
/// Note: if the underlying chunk is evicted from [ChatDataSource] (e.g. by
/// [evictToWindow]), the widget will be rebuilt as a skeleton on next layout
/// regardless of keep-alive status. KeepAlive is a widget-tree concern only.
class ChatKeepAliveController extends ChangeNotifier {
  final Set<int> _pinnedIds = {};

  void pin(int messageId) { _pinnedIds.add(messageId); notifyListeners(); }
  void unpin(int messageId) { _pinnedIds.remove(messageId); notifyListeners(); }
  bool isPinned(int messageId) => _pinnedIds.contains(messageId);
  void clear() { _pinnedIds.clear(); notifyListeners(); }
}
```

In `ChatScrollElement.removeChildren`, skip any ID that
`widget.keepAliveController?.isPinned(id) == true`.

**Important limitation documented explicitly:**
KeepAlive prevents widget deactivation. It does **not** prevent data eviction.
If `evictToWindow` removes the chunk for a kept-alive message, the widget will
show a skeleton until the chunk is refetched. For Telegram-smooth return navigation
to recently visited messages, the correct lever is `dataSource.maxChunks`, not
KeepAlive. KeepAlive's benefit is reducing widget re-inflation cost, not preventing
skeleton flash.

**Acceptance criteria:** Pinned IDs survive GC passes. Unpinned IDs are collected
normally. Pinned IDs whose chunk is evicted rebuild as skeletons correctly.

***

## Phase 4 — Correctness & Race Fixes

**Entry condition:** Phase-1 PRs merged. May open in parallel with Phase-2.**

***

### PR-E1: Anchor-at-deleted-message guard

**Files modified:** `render_chat_scroll_view.dart`

In `renormalizeAnchor`, after resolving the anchor box, add a null-message guard:

```dart
// If the anchor slot is null (message was hard-deleted), walk forward
// (or backward in reverse mode) to find the nearest non-null neighbour.
if (dataSource.getMessage(controller.anchorMessageId) == null) {
  // Walk children (already built) for the nearest valid message.
  int? bestId;
  for (final id in children.keys) {
    if (dataSource.getMessage(id) != null) {
      bestId = id;
      break; // SplayTreeMap is sorted ascending; first valid is closest top
    }
  }
  if (bestId != null) {
    controller.reassignAnchor(bestId, children[bestId]!... /* offset */);
  }
}
```

In `ChatAnimator.tickAnimate` (after PR-1D), when target slot becomes null
mid-animation: settle at nearest non-null neighbour and complete the future.

**Delete event handling contract (documented, not code):**
When the backend fires a delete event:
1. Null the slot(s) in the chunk.
2. If deleted ID was `oldestKnownId` or `newestKnownId`, call
   `seedBoundaries(oldestKnownId: newOldest, ...)` atomically.
3. Call `notifyDataChanged()` once.
The scroll view handles the rest automatically via `renormalizeAnchor`.

**Acceptance criteria:** Deleting the anchor message does not produce a blank
viewport. Animation toward a deleted target completes gracefully.

***

### PR-E2: `ChatDataSource.deleteMessages` helper

**Files modified:** `chat_data_source.dart`

```dart
/// Hard-delete [messageIds] from the chunk cache. Nulls each slot in place.
/// Sparse IDs (gaps from prior deletes) are silently ignored.
/// Calls [notifyDataChanged] once after all slots are nulled.
///
/// **Boundary update:** If any deleted ID equals [oldestKnownId] or
/// [newestKnownId], the caller must pass updated boundary values via
/// [newOldestKnownId] / [newNewestKnownId]. Failing to do so leaves
/// boundary state pointing at a non-existent message.
void deleteMessages(
  List<int> messageIds, {
  int? newOldestKnownId,
  int? newNewestKnownId,
}) {
  if (_disposed) return;
  bool changed = false;
  for (final id in messageIds) {
    final chunk = _chunks[ChatScrollChunk.chunkOf(id)];
    if (chunk == null) continue;
    final slot = id - chunk.firstId;
    if (chunk.messages[slot] != null) {
      chunk.messages[slot] = null;
      changed = true;
    }
  }
  if (newOldestKnownId != null || newNewestKnownId != null) {
    seedBoundaries(
      oldestKnownId: newOldestKnownId,
      newestKnownId: newNewestKnownId,
    );
    // seedBoundaries calls notifyDataChanged if boundaries changed.
    // Only call notifyDataChanged separately if boundaries were unchanged
    // but data was.
    return;
  }
  if (changed) notifyDataChanged();
}
```

**Acceptance criteria:**
- Deleting a full chunk's worth of messages leaves 64 null slots; chunk `status`
  remains `valid` (the chunk exists, it is just empty).
- Deleting boundary messages with `newOldestKnownId` updates `oldestKnownId`
  atomically with the data change — listeners see one notification.
- Unit test: delete 100 messages across two chunks, verify null slots, verify
  boundary update, verify single `notifyDataChanged` call.

***

### PR-E3: `ChatChildManager` call-site contract enforcement

**Files modified:** `chat_scroll_element.dart`, `chat_child_manager.dart`
(or inline in the abstract interface in `render_chat_scroll_view.dart`)

Add to each `ChatChildManager` method:
```dart
/// Must only be called from within [invokeLayoutCallback].
/// Calling from any other context will assert in debug mode.
```

Add debug flag to `ChatScrollElement`:
```dart
bool _insideLayoutCallback = false;

// Wrap every invokeLayoutCallback call:
invokeLayoutCallback<BoxConstraints>((_) {
  assert(() { _insideLayoutCallback = true; return true; }());
  try {
    // ... existing body ...
  } finally {
    assert(() { _insideLayoutCallback = false; return true; }());
  }
});

// Each ChatChildManager method starts with:
assert(_insideLayoutCallback, 'ChatChildManager methods must only be called from within invokeLayoutCallback');
```

**Acceptance criteria:** In debug mode, calling any `ChatChildManager` method
outside `invokeLayoutCallback` throws an assertion. Zero cost in release mode.

***

## Summary Table

| PR | Phase | Files Touched | Breaking | Depends On | Parallel With |
|---|---|---|---|---|---|
| PR-0A | 0 | `IChatMessage`, `ChatDataSource` docs | No | — | — |
| PR-0B | 0 | new test file | No | 0A | — |
| PR-1A | 1 | `render_chat_scroll_view`, new physics | No | 0A, 0B | — |
| PR-1B | 1 | render object, new scheduler | No | 1A | — |
| PR-1C | 1 | render object, new header controller | No | 1B | — |
| PR-1D | 1 | render object, new animator | No | 1C | — |
| PR-1E | 1 | `ChatDataSource`, new `ChatRangeFetch` | No | 1D | Phase 2/4 |
| PR-C1 | 2 | scroll view, element | **Yes** | 1D | C2–C6 |
| PR-C2 | 2 | controller, keyboard shortcuts | No | 1D | C1, C3–C6 |
| PR-C3 | 2 | scrollbar, render object | No | 1D | C1, C2, C4–C6 |
| PR-C4 | 2 | scroll view | No | 1D | C1–C3, C5–C6 |
| PR-C5 | 2 | controller, render object | No | 1D | C1–C4, C6 |
| PR-C6 | 2 | `ChatDataSource` | No | 0A | C1–C5 |
| PR-D1 | 3 | controller | No | all C | D2–D4 |
| PR-D2 | 3 | scroll view, element, render object | No | all C | D1, D3, D4 |
| PR-D3 | 3 | data source, render object, scheduler | No | all C | D1, D2 |
| PR-D4 | 3 | new controller, render object, element | No | D3 | D1, D2 |
| PR-E1 | 4 | render object | No | 1D | Phase 2 |
| PR-E2 | 4 | `ChatDataSource` | No | 1D | Phase 2 |
| PR-E3 | 4 | element, interface | No | 1D | Phase 2 |

***

## Appendix A — Parameters and Their Invariants

| Parameter | Owner | Default | Invariant |
|---|---|---|---|
| `kBits` | `ChatScrollChunk` | `6` | Never changes. All chunk math derives from this. |
| `kSize` | `ChatScrollChunk` | `64` | `1 << kBits`. |
| `maxChunks` | `ChatDataSource` | `16` | LRU eviction budget. Set to `64` for large conversations to minimise skeleton flash. |
| `nearRadius` | `RenderChatScrollView` | `ceil(cacheExtent / kSize)` | Must be ≤ `jumpGapThreshold`. |
| `jumpGapThreshold` | `RenderChatScrollView` | `8` (512 messages) | Must be ≥ `nearRadius`, ≤ `keepRadius`. |
| `keepRadius` | `evictToWindow` call site | `floor(maxChunks / 2)` | Must be ≥ `jumpGapThreshold`. |
| `pollInterval` | `ChatChunkFetchScheduler` | `150ms` | Debounce window for scroll-active fetch suppression. |

Debug assertion: `nearRadius ≤ jumpGapThreshold ≤ keepRadius` fires on first layout
in debug mode if the invariant is violated by configuration.

***

## Appendix B — Deletion Edge Cases Reference

| Scenario | Behaviour | Code owner |
|---|---|---|
| Anchor points at deleted ID | `renormalizeAnchor` walks to nearest non-null neighbour | PR-E1 |
| `oldestKnownId` deleted | `deleteMessages` caller passes `newOldestKnownId`; `seedBoundaries` updates atomically | PR-E2 |
| `newestKnownId` deleted | Same as above with `newNewestKnownId` | PR-E2 |
| `animateTo` target deleted mid-animation | Animator settles at nearest non-null; future completes | PR-E1 |
| Bulk delete spanning chunk boundary | Null slots in each chunk; chunk remains `valid`; single `notifyDataChanged` | PR-E2 |
| IDs renumbered after delete | **Forbidden by PR-0A contract. System behaviour is undefined.** | PR-0A |

***

## Appendix C — Telegram Behaviour Reference

Included as the reference model that informs PR-C3 and PR-D3.

- **Delete model:** Hard delete. No tombstone. ID slot is permanently null.
  ID space is sparse by design — the scroll system treats gaps as normal.
- **Scrollbar model:** Reflects the single contiguous loaded window only.
  Achieved by evicting the old window on every far jump (PR-D3 replicates this).
- **Reply-jump:** Ephemeral jump + loading indicator. "Return to origin" FAB
  captures origin before jump (PR-D1 replicates this).
- **Warm cache:** Per-session in-memory cache, LRU by conversation. Cold start
  uses local SQLite. This is a consumer-side concern — `ChatDataSource` subclass
  owns persistence. The scroll library's cache is `maxChunks` chunks in `_chunks`.
- **Search jump:** Jumps to matched message ID; defers until chunk loads if not
  already in cache. Handled correctly by the existing anchor system with no changes.