# Changelog

All notable changes to this project will be documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this project is pre-1.0 and not strictly SemVer yet.

## [Unreleased]

### Changed

- **Breaking — `AnimateToLoadPolicy` semantics (stitch load-gate).** `immediate`
  and `preferBuilt` keep their names but no longer timeout into shimmer-stitch.
  Both honor the navigation load-gate (wait until the destination is a real
  row). After readiness: **built → close-path**, **not built → stitch**.
  `preferBuilt` only adds a short close-path chance for a warming row
  (self-insert / follow-tail). Far path is Telegram-style stitch (continuity
  illusion), not a viewport opacity fade. See ADR 005 and
  `docs/architecture/11-animation-integration.md`.

### Added

- **`ChatMessageBody`** — slotted in-bubble layout (`content` + `meta`) with
  Telegram-style last-line packing and shrink-wrap. Meta sits on the last text
  line when it fits; otherwise it wraps to the next row. Body is a real child
  (no internal `TextPainter`, no type-marker discovery). Reply / media stay
  outside; compose them above in the host bubble. Demo bubbles dogfood it.

- **`ChatBubbleMetrics`** — pure resolvers from `ChatMessageThemeData` +
  `MessageRunLayout` to clustered `BorderRadius` and content insets. Hosts
  resolve chrome here instead of walking neighbors in `messageBuilder`.

- **Injectable sender-run policy** — `ChatSenderRunLayout` is an
  `abstract interface class` on `ChatScrollView.senderRunLayout`. Package
  default is `DefaultChatSenderRunLayout` (same sender + optional `groupBy`
  bucket + optional `|createdAt|` window, Telegram-aligned 5 minutes via
  `maxClusterGap`). Pass `null` gap to disable the time window, or replace
  the whole policy without forking the viewport.

- **Bubble radius theme tokens** — `ChatMessageThemeData.bubbleRadius`,
  `cornerNearCap`, and derived `nearRadius` / media radii for clustered
  outer corners on mid-run messages.

- **Message menu presenter** — `showChatMessageMenu` opens a package-owned
  session (dimmed scrim with an undimmed hole over a captured slot rect,
  optional reaction strip, host-defined action rows). Choosing an action
  or reaction completes once; scrim / Escape / overlay back / presence
  abort complete with `null`. IME visibility stays frozen via restored
  focus. Pre-IME back is a LIFO claim stack (`ChatPreImeBackBinding`) —
  native `acquire`/`release` only while the stack is non-empty.

- **Example message menu** — an idle message tap opens the package
  presenter with a Telegram-like action/reaction set. Presence follows
  the demo data source (loaded id). The example assigns
  `ChatPreImeBackBinding.native` at startup; `MainActivity` intercepts
  Back before the IME while a claim is active so the first back
  dismisses the menu and leaves the keyboard up. Dart overlay back
  still works when native is missing (desktop). No package `android/`.

- **Message menu back** — the session is a focus-preserving dialog route
  so system back dismisses the menu before a page `PopScope`. The
  example registers an overlay-priority `OnBackInvokedCallback` so
  gesture Back is claimed before the IME.

- **Message menu rows** — `ChatMessageMenuItem` is a sealed list entry:
  action, explicit `divider()`, or `custom()`. Destructive coloring no
  longer inserts a separator.

- **Message menu chrome** — restyle with `ChatMessageMenuThemeData` (or
  `ChatScrollThemeData.menu`). Swap rows or the floating column via
  `itemBuilder` / `reactionBuilder` / `menuBuilder` without forking
  session, scrim, placement, or back. Default chrome widgets are
  public for composition.

- **Message span selection** — long-press a present message and keep dragging
  past slop to grow or shrink a contiguous run of present neighbors
  (Telegram-style rubber-band). Select vs unselect polarity is locked at start
  from origin membership after that press’s own toggle. Moving back toward the
  origin drops or restores only this gesture’s changes; unrelated snapshot
  members stay put. The origin stays selected during a select span. Lift ends
  the span and leaves the set as it stands; a vertical drag that did not start
  from this long-press still scrolls. A press that never passes slop stays a
  single-message select. Span hit is the laid-out message row under the pointer
  (clamped into the scroll band). Date separators, gaps, shimmer, chunk errors,
  overlays, and selection-disallowed rows are not hits — the far end freezes.
  Absent ids occupy no height and never join the chain. Holding in the edge
  band auto-scrolls as the sole origin writer (follow-tail and close-path
  animate yield); delta is zero when content fits or a boundary pin is active.
  `ChatSelectionController.spanYield` can claim the long-press so a future
  in-bubble text selector can win (unused until then). The pinned floating
  date header is not a hit — tap and long-press go through to the message
  underneath.

- **Selection-allowed and span abort** — optional
  `ChatSelectionController.selectionAllowed` (default `null` = every present
  message). A disallowed id is never a span hit, never joins the selected set,
  and is omitted from the present-neighbor span. If the gesture origin becomes
  absent during a live span, the span ends; the selected set is kept and the
  origin is not retargeted, so delete recovery can write the origin again.

- **Selection cap** — optional `ChatSelectionController.selectionCap` (default
  `null` = unlimited). A select span does not grow past the cap and auto-scroll
  in the grow direction stops; shrinking toward the origin and unselect spans
  still work. Hosts that want Telegram's 100 set the cap themselves.
  `capHits` increments on a refused add so chrome can shake and play an error
  haptic without the selected set changing.

- **Viewport-stable delete** — deleting a tall anchor message while scrolled into
  its interior no longer jumps the viewport; reading position near the composer
  is preserved within 8 logical pixels.

- **Short-content no-scroll mode** — when all loaded messages fit in the viewport,
  drag/fling/bounceback are suppressed, dual boundary pins no longer fight, and
  the scrollbar is hidden (same UX as a non-scrollable list).

- **`MessageRunLayout` and sender-run resolver** — first/last-in-run flags from
  live present neighbors, passed to `ChatMessageBuilder` as a 5th parameter so
  position-specific chrome participates in the skip-rebuild cache. Clustering
  policy is host-injectable (`ChatScrollView.senderRunLayout`; see Added /
  Changed above).

### Changed

- **`MessageRunLayout` resolution** — previously a static
  `ChatSenderRunLayout.resolve`; now instance policy via
  `ChatScrollView.senderRunLayout` (default
  `DefaultChatSenderRunLayout.instance`). Same-sender neighbors farther apart
  than `maxClusterGap` end a run (large corners / unclustered top inset).

- **Demo bubbles** — use `ChatMessageBody` for text + time/status packing and
  `ChatBubbleMetrics` for run-clustered radii; meta stays intrinsic-width
  (no `Align` that defeats shrink-wrap). Incoming avatar, sender name, and
  bubble tail remain on the **last** message in a same-sender run
  (Telegram-style).

- **Viewport-owned selection pointer** — long-press and tap are owned by the
  viewport, not per-row detectors. Rows keep tap / long-press chrome only
  while no span is live. Fling-cancel still suppresses the long-press that
  would start a span.

- **Breaking:** `ChatMessageBuilder` now takes `(context, id, message, status, runLayout)`.
  Update all call sites. Use `runLayout.isLastInSenderRun` / `isFirstInSenderRun`
  for avatar, sender label, tail, and tight padding — do not walk neighbors in
  the builder.

- **Architecture knowledge bundle** — scroll runtime constitution lives under
  `docs/architecture/` as an OKF concept set (coordinate model through known
  limitations). `docs/chat_viewport_architecture.md` now points there.

- **Scrollbar theme customization** — chat scrollbar thumb and uniform track
  colours are customizable via `ChatScrollbarThemeData` on
  `ThemeData.extensions` or a nested `Theme` widget. Thumb position and
  drag-to-jump behavior are unchanged.

### Fixed

- **Selection row-tint hairlines** — selected-row tint in
  `DefaultSelectionChrome` is painted outside the checkbox `ClipRect`. Hard
  clipping the tint was cutting anti-aliased edges and leaving a 1-device-pixel
  seam of the chat background between abutting selected rows.

- **Absent slots never reach `messageBuilder`** — confirmed-absent message ids
  are excluded before `buildChild` and selection chrome. Deleting the layout
  anchor reassigns to a present neighbor instead of leaving a shimmer or empty
  selectable row. Integrators must not rely on returning zero-size widgets for
  absent status.

- **Boundary retraction after last delete** — `seedBoundaries` accepts explicit
  `null` ids so removing the final message clears `oldestKnownId` /
  `newestKnownId` and the empty-chat overlay can appear.

- **Tail `animateTo` on tall newest** — close-path scroll to the known
  conversation end animates to tail-pin geometry (message bottom on the bottom
  inset) instead of band top followed by a layout snap.

- **Stale sender-run chrome after delete** — deleting the first of two
  same-sender messages no longer leaves the survivor without avatar/author when
  the message instance is unchanged.

- **Absent-slot tracking on web** — each chunk stores confirmed-absent slots as
  per-slot flags (`0`/`1`) plus an absent-slot count, not a packed 64-bit
  integer mask. Slot 63, fully-absent O(1) fan-out skip, and invalidate/upsert
  clear paths stay correct on every platform, including dart2js/web.

- **Scrollbar thumb progress** — thumb position is height-weighted: pixel offset
  at the top scroll-band edge over `(estimatedExtent − viewportBandHeight)`,
  using average built row height to extrapolate unloaded ids. Thumb size scales
  with `viewportBandHeight / estimatedExtent` (native scrollbar proportion).
  Hard clamps at tail (`1.0`) and oldest head (`0.0`). Replaces
  id-linear band-edge mapping that treated each message id equally regardless of
  row height (stuck thumb, tail jumps with variable message sizes). Legacy
  anchor and id-linear values remain in `ChatScrollScrollbar` logs for comparison.

- **Scrollbar inset alignment** — track, thumb travel, hit strip, and drag
  progress mapping now respect `ChatScrollView` `topPadding` and
  `bottomPadding` (the same scroll band as message alignment). Thumb id
  mapping (Variant A) is unchanged.

- **Programmatic scroll with non-default alignment** — `animateTo` with
  `alignment` other than `0` (e.g. centering a search result) no longer
  micro-jumps mid-animation. Close-path animation now owns offset interpolation
  for the full duration; layout-time alignment snap is deferred until settle
  and, when the target row is still loading, until the real message is built.
  The animator rebases its aligned end offset when layout geometry changes
  mid-flight (bottom inset, message height, date-header relayout) so the
  viewport no longer jumps after the scroll animation finishes; settle runs
  after the final tick reposition instead of fighting a stale end offset.

- **Close-path `animateTo` at the cache margin** — while a close-path animation
  is in flight, layout no longer renormalizes the anchor away from the target
  or GCs the animate / navigation-alignment rows. Fixes drift, wrong landing
  position, and the target row vanishing when skeleton placeholders are visible
  at the fetch boundary.

- **`jumpTo` / `animateTo` alignment respects top inset** — the alignment band
  now runs from `topPadding` through the bottom inset (`0` = band top below
  chrome, `1` = band bottom above the composer). `alignment: 0` no longer parks
  the message under the app bar / selection bar.

- **Bottom inset changes while scrolled in history** — keyboard or composer
  inset growth/shrink shifts visible content by the inset delta (anchor
  compensation), not only by repinning the tail. Opening the keyboard mid-history
  no longer yanks the viewport as if the user were still at the newest message.

### Changed

- **Demo `ChatComposer`** — `bottomInset` and `onSizeChanged` are optional;
  keyboard height is applied outside the composer measure tree so layout
  reports content height only.

- **`ChatKeyboardShortcuts` drops `dataSource` parameter** _(breaking)_ —
  Home / End now read `oldestKnownId` / `newestKnownId` from the shared
  [ChatScrollController], which mirrors the viewport's wired data source via
  `RenderChatScrollView`. Pass only `controller` + `child`; boundary ids stay
  in sync after data-source swaps.

- **`ChatScrollController.oldestKnownId` / `newestKnownId`** — read-only
  passthrough of the wired source's boundary ids, updated on attach, boundary
  listener callbacks, and each layout publish.

- **`ChatGroupSeparatorBuilder` replaces `ChatDateSeparatorBuilder`** _(breaking)_ —
  the `dateSeparatorBuilder` callback now receives `(context, bucket,
firstMessageDate)` where `bucket` is the raw `groupBy` key and
  `firstMessageDate` is the first message's `createdAt` in that section. When
  `groupBy` uses the default local-day bucket, behaviour is unchanged — format
  from `firstMessageDate` as before. Custom non-`DateTime` buckets (week labels,
  records) now reach the builder instead of being silently ignored.

- **`ChatFloatingHeaderController` internal extraction** — floating day-header
  state, top-day scan, inline divider fade math, and layout rebuild decisions
  now live in `lib/src/chat_scroll/chat_floating_header_controller.dart`.
  `RenderChatScrollView` delegates while keeping `RenderBox` ownership and
  `buildFloatingHeader` inflation in the render layer. No public API change.

- **`ChatAnimator` internal extraction** — `animateTo` close-path scroll,
  far-path crossfade, and post-settle highlight tint now live in
  `lib/src/chat_scroll/chat_animator.dart`. `ChatAnimator` implements
  `ChatScrollAnimator`; `fadeLayer` stays on the render object. Debug asserts
  and doc comments document the `ChatChildManager` / `invokeLayoutCallback`
  contract on `ChatScrollElement`. No public API change.

- **`ChatRangeFetch` internal extraction** — the range-fetch state machine
  (token cancellation, exponential-backoff retry, `fetchingChunks` tracking)
  now lives in `lib/src/chat_scroll/chat_range_fetch.dart`. `ChatDataSource`
  delegates `requestChunks`, `cancelFetch`, `retryChunk`, and the fetch half of
  `invalidate` unchanged. No public API change; behaviour-neutral refactor for
  unit-testability.

- **`ChatVisibleRange` nested row API** — boundary and anchor metrics are grouped
  into `ChatVisibleRow` records (`firstRow`, `lastRow`, optional
  `anchorNextRow`) instead of flat `*Fraction` / `*Height` / `*Id` fields.
  `anyVisibleFillsBand` is renamed to `anyRowFillsBand`. `anchorId` was
  removed earlier (use `ChatScrollController.anchorMessageId`). Per-row
  `*FillsBand` flags remain removed (derive via `visibleRowFillsBand`).

  | Before (flat)                     | After (nested)                         |
  | --------------------------------- | -------------------------------------- |
  | `range.firstVisibleFraction`      | `range.firstRow.visibleFraction`       |
  | `range.firstRowHeight`            | `range.firstRow.height`                |
  | `range.lastVisibleFraction`       | `range.lastRow.visibleFraction`        |
  | `range.lastFractionId`            | `range.lastRow.id`                     |
  | `range.lastFractionHeight`        | `range.lastRow.height`                 |
  | `range.anchorNextId`              | `range.anchorNextRow?.id`              |
  | `range.anchorNextVisibleFraction` | `range.anchorNextRow?.visibleFraction` |
  | `range.anchorNextHeight`          | `range.anchorNextRow?.height`          |
  | `range.anyVisibleFillsBand`       | `range.anyRowFillsBand`                |

  `firstId`, `lastId`, and `paintBandHeight` are unchanged. `lastId` may still
  exceed `lastRow.id` when the chunk boundary expands beyond the last measured
  child.

### Fixed

- **`animateTo` highlight waits for the target message to load.** Jumping to an
  unloaded chunk no longer flashes the highlight tint on a skeleton row — the
  tint arms only after the message is in the data source and its row is built.

- **Demo selection mode: floating day header tracks the selection bar.** Entering
  selection drives `ChatScrollView.topPadding` from the `SelectionAppBar` slide
  animation so the floating header moves with the overlay instead of sitting
  behind it.

- **Deleted messages no longer produce permanent loading skeletons.** When a
  batch of messages is deleted from a conversation, IDs in the deleted range are
  now confirmed as permanently absent after the first successful fetch. The
  viewport skips absent IDs entirely during layout so no shimmer or placeholder
  row is ever shown for them. Absent slots contribute zero height, keeping
  scrollbar position proportional to real content even across large deletion
  gaps.

- **Smooth scroll and correct scrollbar across large ID gaps.** Fan-out now
  skips runs of absent IDs in O(chunk) time rather than iterating every ID.
  Fully-absent 64-slot chunks are skipped in O(1). A conversation with one real
  message at ID 1 and one at ID 10,001 renders exactly two rows with no stall.

- **`invalidate()` resets absent state.** Calling `invalidate()` — e.g. after
  a WebSocket reconnect or pull-to-refresh — clears the absent bitmask on every
  chunk so the subsequent re-fetch can re-confirm or restore each slot without
  being blocked by a stale absent flag.

- **No more message "shifting" when scrolling through an absent gap.** The
  per-frame scroll repositioning (`_repositionMessagesOnly`) previously stopped
  at the first absent ID — because absent IDs are never inserted into the render
  children map, the `null` check terminated the walk and left real messages on
  the far side of the gap with stale y-offsets. Messages now correctly snap back
  into place each frame across any absent zone.

- **Absent-marking now covers all fetched chunks, including older-page loads.**
  The post-fetch absent-marking pass previously skipped null slots outside the
  initial `[oldestKnownId, newestKnownId]` range. Fetches triggered by paging
  older messages now correctly mark absent any slot the server did not return,
  regardless of where the slot falls relative to the initial boundaries.

- **Realtime inserts at previously absent slots are visible immediately.** A new
  `clearAbsentSlot` method on `ChatScrollChunk` is called by `upsertMessage` and
  `upsertMessages` so a server-pushed message at a previously deleted slot clears
  the absent flag and surfaces in the viewport on the next frame without requiring
  a chunk invalidation.

- **Fan-out termination guaranteed even when the entire scanned range is absent.**
  The absent-skip helpers (`_nextNonAbsentIdDown` / `_nextNonAbsentIdUp`) now
  return one past the boundary when all IDs in the range are absent, ensuring the
  outer loop guard always terminates.

- **Blank viewport after a large absent collapse no longer persists after the
  scroll settles.** The viewport snap that brings the anchor back into view now
  fires only after the scroll velocity has dropped to zero, preventing it from
  fighting fling physics during an active gesture.

### Added

- **`ChatMessageStatus.absent`** — new status flag returned by `statusOf(id)`
  when a message ID is confirmed permanently absent within the conversation's
  known bounds. Integrators should return `SizedBox.shrink()` (zero height) for
  absent slots in `ChatMessageBuilder`.

- **Architecture decision record for the position model** — documents the
  per-chat sequential ID guarantee, the full-chunk `fetchRange` invariant, and
  the explicit rationale for not adopting a cursor-based fetch API.

### Added

- **Optional `highlight` on `animateTo`** — pass `highlight: false` to scroll
  to a message with animation but without the post-settle tint (e.g. returning
  to the newest message). Default remains `true`. `highlightDuration:
Duration.zero` on `ChatScrollView` still disables highlights globally.
- **Silent tail navigation (demo pill)** — new-messages affordance uses
  `animateTo(..., highlight: false)` so the tail bubble is not highlighted
  after tap.

- **Visible-range boundary fractions** — `ChatVisibleRange` now includes
  `firstVisibleFraction` and `lastVisibleFraction` (share of each boundary
  message's exposable height inside the scrollable paint band). Denominator is
  `min(messageHeight, bandHeight)` so tall messages report `1.0` when the band
  is filled. Published on every layout / scroll update, including when ids are
  unchanged.
- **Threshold-gated progressive read (demo pill)** — `NewMessagesPill` advances
  the read baseline during scroll only when `lastVisibleFraction` crosses
  `visibilityThreshold` (default `0.5`) on a rising edge, so a one-pixel sliver
  no longer marks a message as read.

- **Production-ready Supabase demo backend** — replaces the Dart Shelf
  `backend/` with a copy-pasteable `supabase/` stack: Postgres schema aligned to
  `chat_protocol`, Edge Functions (`load_chats`, `load_chat`, `load_messages`,
  `send_message`, `get_read_state`, `update_read_state`), Realtime on `messages`
  (≥10k messages, id remap +1), and server-backed last-read via `chat_read_state`
  (seeded at message id **9951**). `BackendChatDataSource` calls Edge Functions with lazy boundary discovery
  (no `GET /api/conversation` / `totalMessages`). Run `./scripts/dev.sh` then
  `flutter run --dart-define-from-file=config/development.supabase.json`.
  - **Send messages demo** — wire `ChatComposer` to `BackendChatDataSource.sendMessage`;
    tail follow on send via existing `notifyDataChanged`; SnackBar on failure with
    composer text retained; connect seeds `newestKnownId` from `load_chat` →
    `ChatEntry.last_message.id` — not `load_messages` or total count.
  - **Composer keyboard persistence** — `ChatKeyboardShortcuts.preserveExternalFocus`
    keeps the soft keyboard open during viewport scroll/tap while composing; demo
    screen enables it on `WidgetChatScreen`.
  - **`chat_last_message` denormalization** — Postgres table + `AFTER INSERT`
    trigger on `messages` maintains `LastMessagePreview`; post-seed backfill after
    bulk demo load; `load_chat` / `load_chats` read denormalized row (no tail scan).
  - **Protocol inline documentation** — self-contained three-layer SQL docs
    (`--` above tables/columns + `COMMENT ON`) in migrations; JSDoc with inline enum
    and error slug tables in `supabase/functions/_shared/` and handler modules.
  - **`protocol_enums.ts`** — canonical ChatKind, MessageKind, MessageFlags,
    UserFlags, Permission, and RichStyle tables with hex values, reserved bit
    ranges, parse helpers, and documented side effects (e.g. DELETED tombstone).

### Removed

- **`health` Edge Function** — replaced by protocol-shaped `load_chats` / `load_chat`.
- **Dart `backend/` package** — superseded by the Supabase stack above.

### Fixed

- **New-messages pill near tail** — opening with only a few unread messages and
  large bubbles no longer flashes the pill away or zeroes the unread count when
  `isAtTail` flickers for a frame during layout settling. The pill uses stable
  at-tail hysteresis before dismissing or advancing the read baseline; demo
  last-read persistence follows baseline changes instead of raw tail edges.

- **Post-mount scroll magnet** — scrolling up through history immediately after
  the chat viewport mounts no longer snaps back to the newest message. User drag
  cancels deferred tail-settle from open-at-newest; boundary pin is suppressed
  while off-tail until an explicit jump to the newest message.

- **Jump to newest / open at tail** — opening the demo chat or jumping to the
  newest message no longer lands one message short of the tail. Tail-targeted
  `jumpTo` / `animateTo` now force a one-shot bottom repin on the first layout
  (even when the viewport was not previously at the tail), and keep repinning
  until the newest message is loaded and settled — including after lazy backend
  fetch and composer inset changes.
- **Phantom skeleton below newest** — jump targets past `newestKnownId` (e.g.
  passing message count instead of last id) are clamped to the known tail so no
  shimmer placeholder row appears below the real newest message. Pre-mount
  `jumpTo(newest)` is seeded on viewport attach so the first layout matches a
  mounted tail jump.
- **Demo initial scroll** — `WidgetChatScreen` jumps to `newestKnownId` on
  connect instead of deriving the anchor from `totalMessages`.
- **Fling stop on touch** — tapping or pressing the chat viewport during an
  active fling now stops inertial scroll immediately. Tap and long-press
  during a fling cancel scroll without toggling or entering selection;
  selection gestures on a stationary list are unchanged.
- **Tail snap-back after scroll-away** — scrolling off the newest message no
  longer yanks the viewport back when a pending tail pin is active; repinning
  continues only for tall/lazy tail settle, not when the user has genuinely
  left the tail.
- **Last-read open before history loads** — `resolveOpenAnchor` trusts a stored
  id within known bounds when the message is not cached yet (metadata-only
  connect); backward walk applies only for confirmed deletions. Backend
  `connect()` now seeds `oldestKnownId` so off-tail open does not fall back to
  id `0`.
- **New-messages pill dismiss label** — tapping jump-to-newest no longer
  flashes a “0 new messages” label during the fade-out; the last non-zero count
  is frozen until opacity finishes.

### Added

- **Open at last-read message (demo)** — the demo chat resumes at the stored
  last-read position when reopening, instead of always jumping to the newest
  message. First visit still opens at the tail. Read position is persisted in
  memory when the user reaches the conversation tail (including via the
  new-messages pill).
- **`DemoLastReadStore`** and **`resolveOpenAnchor`** — demo-only helpers for
  per-conversation last-read persistence and open-anchor resolution (stale id
  → previous surviving message; out-of-range → clamp to oldest/newest).
- **`NewMessagesPill.lastSeenNewestId`** — `ValueNotifier` baseline for the
  unread counter; advances progressively while scrolling toward newer messages
  and at tail; replaces `initialLastSeenNewestId`.
- **`jumpTo` / `animateTo` `alignment` parameter** — optional vertical
  alignment in `0..1` (`0` = top, default; `0.5` = center in the scroll band
  above the bottom inset). Boundary pins clamp when content is insufficient;
  tail navigation stays bottom-pinned. Demo off-tail last-read open uses
  `kDemoLastReadOpenAlignment` (`0.5`).
- **`test/widgets/chat_navigation_alignment_test.dart`** — alignment centering,
  bottom inset, oldest clamp, tail override, and `animateTo` settle.
- **`test/widgets/chat_open_at_last_read_test.dart`** — regression coverage for
  off-tail open, unread count, pill jump-to-newest (no zero flash), tail
  persistence, live arrivals, and stale last-read recovery.
- **`test/widgets/chat_new_messages_pill_test.dart`** — progressive unread
  count on scroll, empty-source arrival, and at-tail baseline updates.
- **`test/widgets/chat_jump_to_tail_test.dart`** — regression coverage for
  tail pin on open, jump/animate to newest, clamp past tail, overscroll at
  tail, lazy-fetch repin, scroll-away without snap-back, and tall newest
  message with `bottomPadding`.
- **Demo chat back handling** — system back / pop while in message selection
  mode clears the selection instead of leaving the screen.

- **Local demo backend** (`backend/`) — Dart HTTP server with SQLite storage,
  paginated `GET /api/messages`, conversation metadata, seed script, and
  tests. Start everything with `./scripts/dev.sh`.
- **`BackendChatDataSource`** — HTTP-backed `ChatDataSource` for the demo
  backend; loads conversation metadata on `connect()`, applies `rangeMeta`
  boundary updates from each fetch, and surfaces `BackendConnectionException`
  with actionable hints when the server is unreachable.
- **`UserChatMessage.fromJson`** for decoding backend message payloads.
- **`DemoConfig.backendUrl`** — resolved from `--dart-define-from-file`
  (`config/development.json`, `config/development.android.json`, or
  auto-generated `config/development.android.device.json`).
- **VS Code launch configs** for desktop, Android emulator (`10.0.2.2`), and
  USB Android device (Mac LAN IP).
- **`scripts/dev.sh`** — seeds the database, starts the backend, and writes
  `config/development.android.device.json` with the host machine's LAN IP for
  physical-device debugging.
- **`test/backend_chat_data_source_test.dart`** and
  **`test/widgets/chat_lazy_pagination_test.dart`** regression coverage for
  backend parsing and partial-oldest-boundary pagination.
- **Demo app backend integration** — `WidgetChatScreen` loads via
  `BackendChatDataSource.connect()`; `DemoBackendError` surfaces connection
  failures with a retry affordance.
- **Follow-tail auto-scroll** + `ChatScrollController.isAtTail` listenable.
  When the viewport is pinned to the newest message and a new one arrives,
  the viewport auto-scrolls so the new message stays at the bottom edge.
  When the user has scrolled away, the anchor is left alone — they are
  reading history.
- **Post-`animateTo` highlight fade.** After a successful `animateTo`
  lands, a translucent tint paints over the target message and fades to
  zero over the configured duration. Configurable via
  `ChatScrollView.highlightColor` and `ChatScrollView.highlightDuration`;
  pass `highlightDuration: Duration.zero` to opt out.
- **`ChatKeyboardShortcuts`** wrapper widget for desktop keyboard
  navigation (PageUp/Down, Home/End, ArrowUp/Down). Defaults to
  `autofocus: false` so a sibling composer `TextField` retains focus.
- **`ChatScrollController.scrollBy(double pixels)`** — programmatic
  scroll API with `addScrollByListener` callbacks and a new
  `ChatProgrammaticScroll` typed event.
- **`ChatDataSource.invalidate()`** — marks all loaded chunks stale so
  the viewport refetches on the next pass. Lazy: in-range chunks get a
  fresh fetch from the existing poll; off-range chunks stay dirty until
  visited. Use after SSE / WebSocket reconnect, `AppLifecycleState.resumed`,
  or pull-to-refresh.
- **Rubber-band overscroll** on conversation boundaries. Pulling past
  the oldest or newest applies damping; on release a short spring-back
  animation pulls the anchor back to the boundary. Mouse-wheel, keyboard,
  fling, and `animateTo` keep the hard clamp.
- **RTL support.** `ChatScrollView` honours ambient `Directionality` and
  accepts an explicit `textDirection` override; the scrollbar mirrors to
  the leading edge. When an override is set, a `Directionality` widget is
  installed around the message subtree so `messageBuilder` reads the same
  direction the chrome uses.
- **Golden-test baselines** for the demo widgets (bubbles, shimmer,
  chunk-error tile, empty state, initial skeleton, date separator).
  Linux-only — see `test/golden/demo_widgets_golden_test.dart`.

### Behavior changes (silent on upgrade)

- **Chunk LRU eviction** now has two passes: when at the `maxChunks` budget,
  off-layout chunks are dropped first (so a `jumpTo` can admit the
  destination range); while under budget, off-screen chunks are retained so
  `jumpTo` / scroll-back can reuse cached data without a refetch.
- **Lazy-pagination fan-out** no longer clamps upward layout to
  `oldestKnownId` while `reachedOldest` is false — `oldestKnownId` is the
  oldest _loaded_ page, not the conversation floor.
- **Fetch poll** no longer treats errored chunks as pending layout work;
  retries are owned by `ChatDataSource` backoff / `retryChunk` instead.
- **Drag past a known boundary now bounces** with a damped overshoot and
  a spring-back animation on release. Existing apps that asserted a hard
  clamp on direct user drag will see a different physics curve. Other
  paths (wheel, keyboard, fling, `animateTo`) keep the hard clamp.
- **Ambient `Directionality.rtl` flips the scrollbar to the left edge.**
  RTL hosts that were running before this PR rendered the scrollbar on
  the right; this is now correctly mirrored. Force LTR via
  `ChatScrollView.textDirection: TextDirection.ltr` if needed.

### Fixed

- **`UserChatMessage.fromJson`** no longer calls `DateTime.parse('')` when
  `updatedAt` is missing — a `FormatException` there previously marked every
  fetched chunk as errored and surfaced `DemoChunkErrorTile` for all
  messages.
- **Lazy pagination blank space** when scrolling up before the oldest page
  has loaded — layout fan-out and range-coverage checks now use a floor of
  `0` until `reachedOldest` is true.
- **`jumpTo` chunk eviction** — when already at `maxChunks`, stale chunks
  outside the new layout range are evicted before the destination chunk is
  fetched; stale render children are dropped at the start of the jump layout
  so renormalize / clamp do not fan across the old id span.
- **`bottomPadding` listenable swap** — repins the newest message at the new
  inset even when a concurrent `dataSource` update cleared
  `_wasAtTailLastLayout` in the same `updateRenderObject` cascade.
- **`chunkErrorBuilder` swap** always schedules a relayout (not only when
  chunk-error tiles are already mounted), so turning the builder on mid-flight
  replaces per-id shimmers with chunk tiles.
- **Android USB device networking** — debug/profile manifests allow cleartext
  HTTP; `dev.sh` auto-writes the Mac LAN IP config (gitignored).
- `_layoutOverlayMode` now resets `_dragInProgress` and clears any
  bounceback state, preventing `_clampBoundaries` from being silently
  suspended after an overlay transition.
- `_onJump` clears any active post-`animateTo` highlight so a programmatic
  `jumpTo` does not leave a ticker tinting a now-invisible target.
- `_onScrollBy` cancels any in-flight bounceback so a programmatic
  scroll wins over the passive spring-back.
- Controller swap with an in-flight drag re-creates the gesture
  recognizer and clears `_dragInProgress` instead of leaking the drag
  state into the new controller.
- `invalidate()` no longer fires two `notifyDataChanged` events on a
  source with running fetches — the cancel-fetch and dirty-marking
  passes are coalesced.
- `_signedOverscroll` returns the larger-magnitude violation when both
  boundaries are violated simultaneously (short conversation pulled past
  both edges) so the bounceback pulls toward the dominant side.
- `_publishIsAtTail` skips snapshot writes while the viewport is in
  overlay mode so follow-tail is not lost across an overlay → normal
  transition.

### Tests

- `chat_widgets_test`: **a failed fetch flips chunks to error and retries**
  temporarily skipped (`skip: true`) — poll/backoff interaction still hangs
  under test; other widget tests pass.

### Performance

- `_applyOverscrollResistance` short-circuits when neither boundary is
  reached, eliding the per-drag-tick `_signedOverscroll` walk on the
  dominant case of mid-conversation drags.
- `ChatKeyboardShortcuts` hoists its `Shortcuts` / `Actions` maps out of
  the per-rebuild `LayoutBuilder`, so a keyboard show/hide no longer
  reallocates the six action callbacks.

### Migration notes

- If your tests assert on the hard-clamp behavior at a boundary, expect
  to see the new bounceback instead. The bounceback completes in
  ~200 ms; wait via `pumpAndSettle()` to land at the boundary again.
- `animateTo` now paints a highlight tint by default — pass
  `highlightDuration: Duration.zero` on `ChatScrollView` to opt out
  without any other change.
- `ChatKeyboardShortcuts.autofocus` defaults to `false`. Existing code
  that relied on the wrapper claiming focus on mount should pass
  `autofocus: true` explicitly.
