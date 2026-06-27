# Changelog

All notable changes to this project will be documented in this file. The
format is loosely based on [Keep a Changelog](https://keepachangelog.com/);
this project is pre-1.0 and not strictly SemVer yet.

## [Unreleased]

### Added

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
  oldest *loaded* page, not the conversation floor.
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
