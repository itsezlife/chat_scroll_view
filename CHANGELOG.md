## Unreleased

### Diagnostics
- **CHANGED**: The per-concern `ChatScrollDevLog` instances are replaced by
  one internal logger (`fine` / `config` / `info` / `warning` / `severe`)
  that takes a category: `animate`, `anchor`, `fetch`, `overscroll` or
  `scrollbar`. Enable one with
  `--dart-define=chat_scroll_view.debug.<category>=true` or a
  `#chat_scroll_view.debug.<category>: true` zone value, or all of them with
  `chat_scroll_view.debug`. Console name is `chat_scroll_view.<category>`.

### Row chrome and day header policy
- **ADDED**: `ChatRowChrome` stacks viewport-owned chrome items above a
  message body in one slot. `messageBodyTop` holds the summed chrome height,
  and a press above it counts as chrome, not message. Each
  `ChatRowChromeItem` resolves its opacity and input every frame through a
  `ChatRowChromeDelegate`, an open protocol that receives
  `ChatRowChromeMetrics` (paint top, extent, floating header zone, scroll
  activity). The built-ins are `.opaque()` (the default),
  `.fadeUnderHeader(band:)` and `.hideUnderHeader()`. Chrome keeps its
  laid-out height whatever it resolves to.
- **ADDED**: `ChatScrollView.dayHeaderDelegate` (`ChatDayHeaderDelegate`)
  sets the floating header's push offset, opacity and input, and picks the row
  chrome delegate for every inline day separator. `ChatFadingDayHeader`, the
  default, keeps the header still and fades separators under it.
  `ChatPushingDayHeader` lets the next day's separator push the header up, and
  hides the inline separator once the header stands in for it.
- **ADDED**: Opt-in `ChatScrollView.scrollActivityTiming` runs a viewport
  clock and passes its activity, a value in `[0, 1]`, to every delegate.
  `ChatScrollActivityTiming` defaults to a 500 ms idle delay, 1000 ms after
  navigation, and 150 ms sine fades. The built-in day header policies hide the
  floating header once scrolling is idle (`hidesWhenIdle`), except while it
  stands in for an inline separator. The clock starts idle, so the list opens
  with the floating header hidden unless it stands in. The default `null` runs
  no clock, and activity stays at `1`.
- **CHANGED**: Flings follow Android's `OverScroller` spline instead of
  `ClampingScrollSimulation`. Distance and initial velocity are unchanged,
  but a fling now lasts the full native duration (about 20% longer) with a
  slow tail, so the idle delay starts as late as on a native Android list.
- **DEPRECATED**: `DatedMessage` forwards to `ChatRowChrome` with one
  `fadeUnderHeader` item, and `RenderDatedMessage` is a typedef of
  `RenderChatRowChrome`. The inline separator fade now lives in
  `ChatRowChromeDelegate.fadeUnderHeader` instead of internal header-controller
  math.

### Message menu scrim
- **CHANGED**: The sheet scrim leaves only the message surface undimmed,
  instead of the whole row. `ChatMessageSurfaceBounds.shape` (a
  `ShapeBorder`) reports the bubble outline. The hole takes that outline,
  including per-corner radii, and is clipped to the scroll band, so a
  bubble partly under host chrome does not uncover the chrome. Without a
  reported surface, the hole is still the slot, rounded by
  `ChatMessageMenuThemeData.holeRadius`. Placement is unchanged.
- **ADDED**: `ChatMessageMenuRequest.surfaceGlobal`, `.surfaceShape` and
  `.bandGlobal`. `showChatMessageMenu` takes them as `surfaceRect`,
  `surfaceShape` and `visibleRect`. `ChatMessageMenuScrim` gains `holeShape`
  and `holeClip`. `ChatSelectionController.reportMessageSurfaceBounds`
  takes an optional `shape`, and `messageSurfaceGlobal` reads the live
  surface rect and outline.
- **EXAMPLE**: The demo bubble reports its run-aware rounded outline, and
  `MessageMenu` forwards the request geometry.

### Unread separator
- **ADDED**: `ChatScrollView.unreadBoundary` (a `ValueListenable<int?>`) and
  `ChatScrollView.unreadSeparatorBuilder` (a `WidgetBuilder`). The viewport
  stacks the built separator as row chrome in the boundary row, below the
  inline date separator when that row starts a day and above the body, with or
  without day grouping. It paints only on a loaded message row, always opaque
  while the date above it fades, outside selection chrome and the
  secondary-tap scope. A tap, secondary tap, or long press on it produces no
  message menu request and no selection. The viewport listens to the
  boundary: setting, moving, or clearing it rebuilds only the old and the new
  boundary row, and swapping the listenable counts as a value change. The
  row at the bottom of the scroll band keeps its screen position across the
  change: a boundary row on screen grows or shrinks upward, and at the tail
  the newest row stays pinned above the bottom inset. A boundary row that
  loads later gets the separator when it is built. Swapping the builder
  rebuilds every built row. A `null` boundary paints nothing.
- **CHANGED**: The separator animates in and out instead of appearing and
  disappearing in one frame, with the timings of Telegram Android's chat
  item animator. Leaving, it fades out over 120 ms while its slot collapses
  over 250 ms, so the neighbouring rows slide closed. Arriving, its slot
  grows over 250 ms while it fades in and scales up from 0.9. A moved
  boundary runs both at once. A change mid-transition reverses from the
  current frame without a jump. The reading-position rule now holds on every
  frame, not only on the frame of the change: the row at the bottom of the
  scroll band keeps its screen Y, and at the tail the newest row stays
  pinned. A held `jumpTo` target that gains or loses the separator is
  re-placed on every frame. Only the old and the new boundary row rebuild:
  the new row at once, the old row when its exit ends. A separator
  mid-transition takes no input. Rows that were not laid out on the previous
  frame, a change made by a tail-or-target listener, and any change while
  `TickerMode` is off still land in one frame.
- **CHANGED**: A held `jumpTo` target no longer keeps its screen Y when a
  top inset change and a separator on another row arrive in the same frame.
  The placement owns that first frame only. The later transition frames
  hold the rows below the separator, as for any separator change on
  another row.
- **EXAMPLE**: The demo reads the stored last-read id on open again, for the
  server-backed source. When a message from someone else follows it, that
  message becomes the unread boundary: the chat opens with
  `jumpTo(boundary, alignment: 0)` and shows a placeholder bar above it,
  labelled in Russian like the demo's day pill. Without one, the open path is
  unchanged, and so is the scroll-to-bottom pill count.
  `ChatDataSourceX.resolveOpenPosition` / `resolveUnreadBoundary` pick the
  boundary from cached messages; at the first uncached id they fetch that
  whole chunk once, so an open makes at most one fetch. A failed fetch is
  logged and the chat opens at last-read without the bar.
- **EXAMPLE**: `UnreadBoundaryController` holds the boundary for one open,
  following Telegram Android's lifecycle. The bar stays put while the reader
  scrolls through unread messages; only the scroll-to-bottom pill's read
  baseline advances. Incoming messages never remove it: at the tail the list
  follows them and the bar scrolls away with the rows above. A send from
  this device removes it, and so does an own message from another device
  that arrives loaded. The host can `setBoundary`, `setPendingBoundary` and
  `clear` any number of times per open; each change notifies once and
  same-value writes are silent. A pending boundary becomes the first loaded
  message from someone else at or after its id, checked on every data
  change. It lapses if there is no such message up to the newest one, and
  later arrivals never resolve it. `separatorSeen` turns `true` on the first
  visible range push that shows the loaded boundary row, and resets when the
  boundary changes.
- **EXAMPLE**: Any deletion removes the bar, as in Telegram Android: every
  remove batch from the data source clears the boundary, pending or not,
  including ids that were never loaded. Edits keep it. A read on another
  client removes it too: `UnreadBoundaryController` takes an optional
  `readElsewhere` listenable and clears on each notification, whatever read
  id the other client stored. This device's own read-progress writes never
  clear it.
- **EXAMPLE**: A page-down that stitches to the tail removes the bar, as a
  reloading page-down does in Telegram Android. When an `animateTo` whose
  target was the newest known message when it started ends with
  `ChatAnimateEnd.path == AnimateToPath.stitch`, `UnreadBoundaryController`
  clears the boundary. A page-down near the tail that scrolls through built
  rows keeps it, and navigations to any other target never clear it.
- **EXAMPLE**: The demo backend syncs read state. `chat_read_state` joins
  the Realtime publication and gains a `write_tag` column, which
  `update_read_state` fills from an optional `write_tag` field and the
  delete trigger clears when it moves the cursor. `BackendChatDataSource`
  tags every read write with its per-instance `writeTag`, follows
  `chat_read_state` changes for its chat and `userId`, and notifies
  `readElsewhere` for each change it did not write. It unsubscribes and
  goes silent on `dispose`.
- **EXAMPLE**: A chat reopens where the reader left off, as in Telegram
  Android. Leaving the demo chat (the screen is disposed or the app hides)
  saves its Center Band per chat in `ChatCenterBandStore`
  (`shared_preferences`). Leaving at the tail drops it, and so does leaving
  with an unread message from someone else as the newest visible row and
  another one among the next four loaded messages. With a saved Center
  Band, `resolveOpenPosition` returns `ChatOpenPosition.centerBand`; the
  screen restores it with `jumpToCenterBand` and makes the boundary pending
  right after last-read, with no boundary fetch. The bar appears when the
  reader reaches that row. `resolveOpenPosition` now returns the sealed
  `ChatOpenPosition`; the open at a message (`MessageOpenPosition`) is
  unchanged. Page-down goes to the unread boundary until its bar has been
  seen (`UnreadBoundaryController.unseenFromId`), landing the bar at the
  band top, and to the newest message afterwards.
  `ChatScrollToBottomButton.interceptTap` lets the host take over a tap.
- **EXAMPLE**: Messages that arrive while the app is in the background
  move the bar, as in Telegram Android. `UnreadBoundaryController` treats
  hide to show (`AppLifecycleListener.onHide` / `onShow`) as one pause. The
  first incoming message that lands at a loaded tail during the pause
  becomes the boundary, replacing a placed or pending one, and later
  arrivals in the same pause leave it. An arrival while the tail row below
  it is not loaded (the reader far up) moves nothing. On show, a reader who
  was at the tail when the app hid jumps to the moved boundary at
  `ChatDataSourceX.unreadBoundaryAlignment`; a reader scrolled up keeps the
  position. The controller now needs an initialized `WidgetsBinding`.
- **EXAMPLE**: A realtime reconnect that missed messages marks the gap.
  `BackendChatDataSource` notices a resubscribe after a channel error,
  close, or timeout, re-reads the newest message id and the stored read
  mark, seeds the new newest id, and reports a `RealtimeReconnectGap` to
  `addReconnectGapListener` listeners when the newest id moved. The screen
  passes it to `UnreadBoundaryController.markReconnectGap`, which makes the
  boundary pending at the later of the first id after the newest one
  before the drop and the read mark, so the bar lands on the first missed
  message from someone else once it loads. A chat that was empty at the
  drop is reseeded like a fresh connect, and its bar lands on the chat's
  first message from someone else. A reconnect with nothing new changes
  nothing. A pending boundary now also skips ids below the oldest message
  once the chat's start is reached.
- **EXAMPLE**: `UnreadBoundarySenderRunLayout` breaks the sender run at the
  bar. The message below it starts a new bubble cluster (full top corners,
  unclustered top inset) and the message above it ends one; every other row
  keeps the wrapped policy's layout. The policy is a `Listenable` over the
  same boundary listenable as the bar, so clearing or moving the bar rebuilds
  only the rows whose run flags flip. The package default policy is
  unchanged.
- **EXAMPLE**: The placeholder bar becomes a fixed-height strip with a
  centered label and a trailing down arrow. The label ignores the text scale
  and the ambient text style, so the row never grows. `UnreadSeparatorColors`
  (a `ThemeExtension` with `light` and `dark` palettes) carries the strip,
  label and arrow colors; without a registered extension the palette follows
  the theme brightness.
- **EXAMPLE**: Short unread content opens at the bottom, as with Telegram
  Android's half-screen rule. An open at the unread boundary passes
  `tailFitFraction: ChatDataSourceX.unreadBoundaryTailFitFraction` (`0.5`,
  carried on `MessageOpenPosition.tailFitFraction`). When the unread
  messages fit in half the viewport, the chat opens at the tail and
  `UnreadBoundaryController` clears the boundary on the `tail` outcome, so
  the bar never shows. Longer unread content opens at the bar as before.

### Navigation
- **CHANGED**: Alignment hold. A `jumpTo` / `animateTo` alignment or a
  `jumpToCenterBand` placement stays held on its target once it lands on a
  loaded row. It lasts until the first user scroll (drag, fling, wheel,
  scrollbar drag), `scrollBy`, or the next navigation. While held, a
  `topPadding` change or a row chrome change on the target row (such as the
  unread separator appearing on it) re-applies the placement. After
  `jumpTo(boundary, alignment: 0)`, top chrome that grows before the reader
  scrolls no longer covers the boundary row, and a separator added to that
  row lands at the band top with the body below it. Before, the alignment
  was dropped as soon as it was reached: a top inset change left the row
  under the new chrome, and the separator grew upward past the band top.
  Everything else behaves as before. Bottom inset changes are still
  compensated, row chrome changes on other rows still keep the band bottom
  row in place, and a jump to the known newest is still owned by the tail
  pin. The hold ends without moving anything when the target becomes absent
  or the list follows the tail. `scrollBy` now also cancels a placement
  that has not landed yet, so a `scrollBy` right after `jumpTo` sticks
  instead of being snapped back.
- **ADDED**: `ChatAnimateEnd.path` (`AnimateToPath`) reports how an
  `animateTo` flight reached its target: `close` when the target was a built
  row and the list scrolled through the rows in between (a target already
  in place included), `stitch` when it was not built and the viewport
  teleported and slid the destination band in (a load-gate wait that ends
  in a stitch included), `instant` for `duration <= 0`, and `none` when the
  flight was cancelled on the load-gate before choosing. A flight
  cancelled after it began reports the path it began. Path selection, load
  policies and the load-gate are unchanged, and so are the events: a
  coalesced or ignored call, or an `animateTo` with no viewport bound (a
  plain `jumpTo`), still emits no `ChatAnimateEnd`. The return value of
  `animateTo` is still `AnimateToDisposition`.
- **ADDED**: Tail-or-target jump. `jumpTo` takes an optional
  `tailFitFraction` (`0..1`). The jump decides once, in the first layout
  that lays out the target as a loaded row, so a jump issued before the view
  mounts or onto a loading row works too. When the newest message is known
  (`reachedNewest`) and loaded, and the span from the target's body top
  (its row chrome, such as the unread separator, excluded) to the newest message's
  bottom is at most that fraction of the viewport height, the chat opens
  pinned at the tail. Otherwise the target is placed at `alignment` as a
  plain `jumpTo` would place it. The span counts only rows laid out in that
  layout, so rows still sized as skeletons from before their chunk loaded
  never shrink it. Skeleton layouts before the decision never pre-empt it:
  a jump onto the newest message still decides once that row loads, and a
  target outcome stays seated even when short skeletons had pinned the list
  to the tail. `addTailOrTargetListener` /
  `removeTailOrTargetListener` report the `TailOrTargetOutcome` (`tail` or
  `target`) synchronously inside that layout, with the usual listener
  contract (dedup, snapshot dispatch, silent after `dispose`); a callback
  that navigates fails an assert in debug builds. An unread boundary change
  made in the callback is laid out in the same pass, so clearing it on
  `tail` paints no separator in any frame. A jump released
  before it decides (user scroll, `scrollBy`, next navigation) reports
  nothing. Calls without the fraction are unchanged.

### Breaking changes

Source-breaking for hosts that built against earlier revisions of this
repository. Each entry says what to change.

- **CHANGED**: `ChatScrollAnimator.animate` returns `Future<AnimateToPath>`
  instead of `Future<void>`. The viewport binds its own animator; only a
  custom implementation needs to complete with the path it took.

- **REMOVED**: `onCopySuccess`, `onLinkTap`, `onLinkLongPress`, `onCodeTap` and
  the matching typed `add*Listener` APIs on `ChatSelectionController`. Use
  `ChatSelectionController(onInteraction: …)` or `addInteractionListener` (see
  Text selection).
- **CHANGED**: `ChatSelectionController.spanYield` is now
  `(int messageId, Offset globalOffset) → bool`. When it returns `true`, the
  viewport doesn't start a span or change membership from that press, and
  `addSpanYieldedListener` / `removeSpanYieldedListener` fire once with the
  same payload (`claimSpanYield`). The predicate MUST stay side-effect free;
  start text selection from the typed notification. See ADR 003 and CONTEXT
  (_Span yield_).
- **CHANGED**: `ChatMessageBuilder` now takes
  `(context, id, message, status, runLayout)`. Update all call sites. Use
  `runLayout.isLastInSenderRun` / `isFirstInSenderRun` for avatar, sender
  label, tail and tight padding; don't walk neighbors in the builder.
- **CHANGED**: `ChatGroupSeparatorBuilder` replaces
  `ChatDateSeparatorBuilder`. The `dateSeparatorBuilder` callback now receives
  `(context, bucket, firstMessageDate)`. `bucket` is the raw `groupBy` key,
  and `firstMessageDate` is the `createdAt` of the section's first message.
  With the default local-day bucket nothing changes; format from
  `firstMessageDate` as before. Custom non-`DateTime` buckets, such as week
  labels or records, now reach the builder instead of being dropped.
- **CHANGED**: `ChatVisibleRange` groups boundary and anchor metrics into
  `ChatVisibleRow` records (`firstRow`, `lastRow`, optional `anchorNextRow`)
  instead of flat `*Fraction` / `*Height` / `*Id` fields.
  `anyVisibleFillsBand` is renamed `anyRowFillsBand`. `anchorId` was removed
  earlier; use `ChatScrollController.anchorMessageId`. Per-row `*FillsBand`
  flags stay removed; derive them with `visibleRowFillsBand`.

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

  `firstId`, `lastId` and `paintBandHeight` are unchanged. `lastId` can still
  exceed `lastRow.id` when the chunk boundary extends past the last measured
  child.
- **REMOVED**: `ChatKeyboardShortcuts.dataSource`. Home and End read
  `oldestKnownId` / `newestKnownId` from the shared [ChatScrollController],
  which mirrors the viewport's data source through `RenderChatScrollView`. Pass
  only `controller` and `child`. Boundary ids stay in sync after data-source
  swaps.
- **CHANGED**: `AnimateToLoadPolicy` keeps its enum names, but the behavior
  changed. Neither `immediate` nor `preferBuilt` falls back to animating over
  unresolved placeholders anymore. An unready destination waits in the
  load-gate until the target is a real row. A built target then gets a
  close-path scroll, and an unbuilt one gets a stitch (outgoing capture,
  teleport, dual-translate). `preferBuilt` only adds a short window in which a
  row already entering the build range (self-insert, follow-tail) can take
  close-path. Read `docs/architecture/11-animation-integration.md` and ADR 005
  before wiring search, deep links or send-follow.
- **REMOVED**: Bounceback and overscroll resistance in `ChatScrollPhysics`
  (`BouncebackSide`, `kOverscrollBounceDuration`, `applyOverscrollResistance`,
  `maybeStartBounceback`, `tickBounceback`). Fling-only clamping remains.
  `ChatAnimator` takes `cancelOverscroll` instead of `cancelBounceback`. Hosts
  that relied on the layout rubber band MUST migrate to paint stretch (see
  Overscroll and boundaries).
- **CHANGED**: The chat_chrome public panel, allow, tab, labels, callbacks,
  bottom bar and actions, and type-tabs pill are renamed from `EmojiPanel*` to
  `KeyboardPanel*`. Unicode page, glyph and `emoji_data` names stay `Emoji*`.
  The prefs store [KeyboardHeightStore] is renamed [KeyboardPanelStore] and
  uses only `keyboard_panel_*` keys (selected page and heights, no legacy
  dual-read). Hosts start from the controller; see the package README and
  public dartdoc.

### Markdown bodies and links
- **ADDED**: `ChatMarkdownBody` selects `BlockPainter$ScrollableTable`, so
  wide tables pan horizontally inside the bubble. This is a catalog painter
  opt-in, not a theme flag. `MarkdownSelectionController` keeps the pan
  position across theme rebuilds and engine row recycling.
- **CHANGED**: Selected bodies refuse nested table pan. `ChatMarkdownBody`
  builds `BlockPainter$ScrollableTable(enabled: !isSelected(messageId))`. An
  overflowing table keeps its clipped layout but ignores horizontal drag and
  wheel pan while its message is in **message selection**. The theme cache
  keys on membership, so `enabled` rebuilds when membership flips. Selected
  rows stay hittable for text entry (ADR 015).
- **ADDED**: Opt-in, host-invoked body linkify. `ChatBodyLinkify.apply` takes a
  combinable `ChatLinkifyPolicy` bitmask: `webUrls`, `mentions`, and the
  default `webAndMentions`, combined with `|`, `add` and `remove`. It rewrites
  bare `http`, `https` and `www` URLs and `@username` into markdown links.
  Mentions become `[@username](mention:<username>)` and use the existing link
  **inline hit** channel. It skips fenced code, inline code and existing
  `[…](…)` links. The viewport's paint and build path never calls it
  ([ADR 017](docs/adr/017-body-linkify-host-invoked.md)). Link previews remain
  out of scope. The example host calls the helper at send and materialize
  time, and branches activation on `http`/`https` vs `mention:`.

### Tap highlight
- **ADDED**: `ChatTapHighlight` wraps any child with contour ink that follows
  the press. The ink expands, holds and releases, and a cancel aborts it.
  Travel past touch slop also aborts it, because scrollables rarely deliver
  `PointerCancel` to a `Listener` during a mobile list pan. Desktop and mouse
  presses keep the pointer out of viewport message pan. On touch with a null
  `onLongPress`, mobile **message selection** can claim the press. Pointer
  handlers tolerate an unmount mid-gesture. The widget doesn't need the
  selection facade, but under `ChatSelectionStateScope` it respects
  `canPerformActions`. The label [color] uses diluted ink alpha
  (`labelInkAlpha`), and [padding] grows the paint and hit area without
  changing layout size. The example's sender name uses it.
- **FIXED**: Inline press ink in `ChatMarkdownBody` aborts past touch slop,
  like `ChatTapHighlight`. When the pointer moves past slop it calls
  `abortSpanFeedback`, so a list pan or a horizontal table pan clears the
  highlight at once. Waiting for a `PointerCancel` left the ink on.

### Text selection
- **CHANGED**: The viewport owns markdown **text selection** (ADR 013). ADR 013
  supersedes ADR 011's optional bridge and markdown-agnostic core. ADR 012
  records these policy amendments:
  - the engine routes mobile long-presses, and the public **span yield** is
    not the long-term entry point;
  - collapse-to-subject is this viewport's mobile rule;
  - mobile retarget is policy;
  - **inline hit** is its own path, separate from idle dismiss;
  - desktop drag-out promotion to **message selection** is accepted and
    deferred until after the foundation work.
- **CHANGED**: `ChatSelectionController` is the selection facade. Membership,
  the **text selection** subject and range, the **selection policy**, and Copy
  observation all live on one controller. New call sites don't add a second
  host text controller.
- **ADDED**: `chat_scroll_view` depends on `flutter_md` and owns an internal
  text-selection module that reuses that library's selection model
  (documents, positions, copy formatting). The facade takes a
  `ChatSelectionPolicy` (`$Mobile` / `$Desktop`, `forPlatform` by default).
  The public text API is `enterTextSelection` / `clearTextSelection` /
  `copyTextSelection`, `putBody` / `removeBody`, and Copy-success listeners
  plus an optional `onCopySuccess`.
- **ADDED**: Sealed `ChatSelectionInteraction` (`ChatCopied`,
  `ChatLinkActivated`, `ChatCodeActivated`) arrives through
  `ChatSelectionController.onInteraction` / `addInteractionListener`. It
  replaces the separate `onCopySuccess`, `onLinkTap`, `onLinkLongPress` and
  `onCodeTap` callbacks and their typed listeners. Code click-to-copy
  (`copyCodeOnClick: true`) emits a single `ChatCopied(origin: codeTap)` and no
  second code event, so "Copied" chrome can key on `ChatCopied` alone. With
  auto-copy off, only `ChatCodeActivated` fires. Message-menu requests stay on
  `ChatScrollView`, because they carry slot geometry.
- **ADDED**: `ChatSelectableMessage` sets `canPerformActions` to false while
  mobile **message selection** or **text selection** is active, which turns
  off host chrome such as `ChatTapHighlight`. `IgnorePointer` still covers only
  **unselected** bodies that aren't the subject. Selected rows stay hittable,
  so a yielded long-press can enter **text selection** (ADR 015). Desktop keeps
  host chrome hittable.
- **ADDED**: Edge autoscroll for markdown text selection. `ChatMarkdownBody`
  drives the anchor viewport through `ChatMarkdownAutoscroll`. Hosts pass
  `ChatMarkdownAutoscrollOptions` (enabled, maxVelocity, edgeZone) instead of
  the raw markdown autoscroll config. The default speed on mobile is about
  half a line (~9 px) per frame at the display refresh rate; desktop derives it
  from a fixed ~15 ms step near the edge. Scrolling stops when the text subject
  is flush with the pad. Desktop promotion from text to message selection at
  that edge is not implemented yet.
- **ADDED**: `chat_md_selection` package: message-then-text markdown selection
  on top of `ChatSelectionController`. It registers bodies by Message ID and
  keeps markdown selection inert until `enterTextSelection`. Entering
  collapses membership to the text-selection subject, arms only that document,
  and starts either a word range at a global point or select-all, with default
  Copy and Select all chrome. It owns `spanYield`, which claims a press only
  when the id is already selected and the global point hits that body's
  selectable text; the yield notification enters text selection. Selected
  bodies mount hit-test surfaces while inactive. While text is active, only
  the subject mounts a surface and is armed. Exit rules under the mobile
  policy:
  - dismissing text keeps the subject selected;
  - `copyTextSelection` or the default toolbar Copy clears text and message
    selection;
  - clearing message selection clears text;
  - entering on a new subject moves the range and collapses membership.
- **ADDED**: Sealed `ChatMdSelectionPolicy` (`mobile` / `desktop`) in
  `chat_md_selection` (ADR 012), with a host override and a `forPlatform`
  default: iOS and Android get mobile, desktop OSes and web get desktop.
  `ChatMdSelectionController` delegates entry, nesting, the span-yield claim
  and Copy-success effects to the policy. Mobile keeps message-then-text and
  clears the mode on Copy. Desktop clears membership on enter and keeps the
  range on Copy. Copy success notifies typed listeners and the optional
  `onCopySuccess`; the feedback UI stays in the app.
- **FIXED**: The adaptive toolbar no longer appears mid-drag during
  autoscroll. With message multi-select and a live text expand drag,
  hit-targeting a nearby selected body briefly committed a cross-document
  range. The facade then restored the last on-subject range through the public
  markdown `selection` setter, which set `toolbarWanted`, and edge autoscroll
  notifications showed the toolbar before the drag ended. The restore now
  clears `toolbarWanted` after the clamp, and drag end sets it again through
  `showToolbar`. This pairs with the markdown scope's mid-drag scroll guard.
- **FIXED**: Mobile retarget of a continuous text gesture. With message
  multi-select and text active on subject A, a long-press on another selected
  body's text now yields to that body's markdown scope, the same path as first
  entry, so drag-extend and scope haptics work. Before, the viewport kept the
  press and called `enterTextSelection` once, which settled immediately.
  Selected siblings mount surfaces while text is live; adopt and Select All
  still prune the registry to the subject (ADR 015). A handle drag that walks
  onto a sibling mount restores the last on-subject range. It used to clear
  text or pin to the document edges, which flashed the full body or reversed
  the selection mid-gesture. Retarget clears `toolbarWanted`, so the previous
  adaptive toolbar doesn't linger during the gesture.
- **FIXED**: One rule for mobile inline hits during selection. When idle,
  links, inline code and COPY CODE all fire. During **message selection** or
  with a live **character range**, all three are suppressed. Previously,
  fixing one of them (COPY) kept breaking another (inline code). On desktop,
  message membership and arm-for-entry keep inline hits live, and a live range
  suppresses them everywhere.
- **FIXED**: Desktop message pan no longer wins on the empty line gutter or
  body surface padding, because `containsGlobal` now uses the surface bounds.
  While **text selection** is active, a click off the text dismisses it
  instead of starting a message drag-select.
- **FIXED**: Suppressing Flutter's text context menu when
  `onSecondaryMessageTap` is set now applies to `$Desktop` only
  (`secondaryMessageTapOwnsFullSlot`). `$Mobile` keeps the adaptive toolbar
  even when the host also wires secondary tap.

### Message menu
- **ADDED**: `showChatMessageMenu` opens a package-owned session: a dimmed
  scrim with an undimmed hole over a captured slot rect, an optional reaction
  strip, and host-defined action rows. Choosing an action or reaction
  completes the session once. A scrim tap, Escape, overlay back or presence
  abort completes it with `null`. IME visibility stays frozen through restored
  focus. Pre-IME back is a LIFO claim stack (`ChatPreImeBackBinding`); native
  `acquire`/`release` runs only while the stack is non-empty.
- **ADDED**: `ChatMessageMenuPresentation` (`sheet` / `popup`, ADR 016) takes
  its default from the **selection policy**. `$Mobile` shows a scrim sheet with
  the slot left undimmed. `$Desktop` shows a popup at the pointer with no
  viewport dim and no slot outline or lift. Pass `presentation:` to override
  one call. The optional `selectionPolicy:` sets the default when
  `presentation` is omitted. Both presentations share one session, which
  handles presence abort, dismissal by Escape, back or an outside tap, and
  action or reaction results. Reactions stay optional on either.
- **ADDED**: The session is a focus-preserving dialog route, so system back
  dismisses the menu before a page `PopScope`. The example registers an
  overlay-priority `OnBackInvokedCallback`, so gesture Back is claimed before
  the IME.
- **ADDED**: `ChatMessageMenuItem` is a sealed list entry: an action, an
  explicit `divider()`, or `custom()`. Destructive coloring no longer inserts a
  separator.
- **ADDED**: Restyle the menu with `ChatMessageMenuThemeData` (or
  `ChatScrollThemeData.menu`). Swap rows or the floating column through
  `itemBuilder` / `reactionBuilder` / `menuBuilder` without forking the
  session, scrim, placement or back handling. The default chrome widgets are
  public for composition.
- **ADDED**: When `onSecondaryMessageTap` is set, the viewport claims
  right-click on the entire **slot**, markdown glyphs included, and per-body
  text yields so Flutter's text context menu doesn't open on top. When the
  callback is null, selectable markdown keeps Flutter's text menu.
- **CHANGED**: `ChatScrollView.onIdleMessageTap` and `onSecondaryMessageTap`
  receive a [ChatMessageMenuRequest] (ADR 016) with:
  - the id, slot and tap;
  - the **point state**, Inside the body or Outside it in the slot, measured
    against the host-reported message surface (bubble);
  - **membership**: idle, upon-selected (**over-selection**) or elsewhere;
  - `hasTextSelection`, true when the subject has a live non-collapsed range;
  - `overlapsTextSelection`, tested against the highlight rects at the tap
    rather than the whole subject, plus an optional plain-text snapshot;
  - `selectUpToIds` when the tap is elsewhere and under the selection cap;
  - an optional **inline hit** (link or code).

  Opening the menu doesn't clear membership or text selection. The example
  catalogs drop both Copy and Copy Selected Text when text is selected but the
  press isn't on the range. Upon-selected rows use bulk labels, and elsewhere
  rows can offer Select up to. Hosts can pass `excludeActionIds` to the example
  `MessageMenu` or catalog without forking the presenter.
- **FIXED**: Surface and body paint registration stores the mounted
  [RenderBox] and resolves `localToGlobal` at hit time.
  `reportMessageSurfaceBounds` and `reportBodyPaintBounds` now take
  `RenderBox?` instead of a cached global [Rect]. Cached rects went stale when
  the list scrolled without rebuilding, so secondary taps registered as
  Outside. On desktop that opened a Select-only menu, which was easy to mistake
  for "elsewhere".
- **EXAMPLE**: An idle message tap opens the package presenter with a sample
  action and reaction set. Presence follows the demo data source (loaded id).
  The example assigns `ChatPreImeBackBinding.native` at startup, and
  `MainActivity` intercepts Back before the IME while a claim is active, so the
  first back dismisses the menu and leaves the keyboard up. Dart overlay back
  still works when native is missing (desktop). The package has no `android/`
  directory.

### Message selection
- **ADDED**: Message span selection. Long-press a present message and keep
  dragging past slop to grow or shrink a contiguous run of present neighbors.
  Select vs unselect polarity locks at the start, from the origin's membership
  after that press's own toggle. Moving back toward the origin drops or
  restores only this gesture's changes; members selected before the gesture
  stay put. The origin stays selected during a select span. Lifting ends the
  span and leaves the set as it is. A vertical drag that didn't start from this
  long-press still scrolls, and a press that never passes slop stays a
  single-message select.

  The span hit is the laid-out message row under the pointer, clamped into the
  scroll band. Date separators, gaps, shimmer, chunk errors, overlays and
  selection-disallowed rows are not hits, so the far end freezes over them.
  Absent ids take no height and never join the chain. Holding in the edge band
  auto-scrolls, and auto-scroll is then the only origin writer (follow-tail and
  close-path animate yield to it). The delta is zero when content fits or a
  boundary pin is active.

  `ChatSelectionController.spanYield` claims a long-press at
  `(messageId, globalOffset)`. When it claims, no span starts and
  `addSpanYieldedListener` fires, so the host can start text selection
  programmatically. The pinned floating date header is not a hit; tap and
  long-press go through to the message underneath.
- **ADDED**: Optional `ChatSelectionController.selectionAllowed` (default
  `null`, meaning [ChatSelectionAllowed.full]). A non-selectable id is never a
  span hit, never joins the selected set, and is left out of the
  present-neighbor span. The chrome wrapper follows `showsChrome`: `none` skips
  it, and `gutterOnly` wraps without a check. Assigning the predicate, or
  calling `reapplySelectionAllowed`, refilters the selected set and notifies
  `addSelectionAllowedListener`. If the gesture origin becomes absent during a
  live span, the span ends. The selected set is kept and the origin isn't
  retargeted, so delete recovery can write the origin again.
- **ADDED**: Optional `ChatSelectionController.selectionCap` (default `null`,
  unlimited). A select span doesn't grow past the cap, and auto-scroll in the
  grow direction stops. Shrinking toward the origin and unselect spans still
  work. Hosts that want a limit, such as 100, set it themselves. `capHits`
  increments on a refused add, so chrome can shake and play an error haptic
  without the selected set changing.
- **CHANGED**: The viewport owns long-press and tap instead of per-row
  detectors. Rows keep tap and long-press chrome only while no span is live.
  Fling-cancel still suppresses the long-press that would start a span.
- **FIXED**: `ChatSelectionController.selectionAllowed` returns
  [ChatSelectionAllowed]: `full`, `gutterOnly`, `none`, or custom
  `selectable`∪`chrome` bits, with the check shown only when both are set.
  Loaded rows with `showsChrome` mount `SelectableMessage`. `none` skips the
  wrapper. `gutterOnly` shifts for mode without a check and can't join the set.
  Assigning the predicate, or calling `reapplySelectionAllowed`, drops selected
  ids that are no longer selectable, notifies `addSelectionAllowedListener`,
  and invalidates the selection-allowed skip cache. This replaces the former
  `selectionAllowed` bool API.
- **FIXED**: `SelectableMessage` chrome rebuilds on facade notifications, not
  only on mode and select animation ticks. Clearing a drag preview while mode
  is entering no longer leaves `ChatMessageChangeTransition` painted in
  `selectedColor` with empty membership.
- **FIXED**: `DefaultSelectionChrome` paints the selected-row tint outside the
  checkbox `ClipRect`. Clipping the tint cut its anti-aliased edges and left a
  1-device-pixel seam of chat background between adjacent selected rows.

### Sender runs and message layout
- **ADDED**: `MessageRunLayout` and the sender-run resolver. First/last-in-run
  flags come from live present neighbors and reach `ChatMessageBuilder` as a
  fifth parameter, so position-specific chrome takes part in the skip-rebuild
  cache.
- **ADDED**: `ChatSenderRunLayout` is an `abstract interface class` passed as
  `ChatScrollView.senderRunLayout`. The package default,
  `DefaultChatSenderRunLayout`, clusters by sender, an optional `groupBy`
  bucket, and an optional `|createdAt|` window of 5 minutes (`maxClusterGap`).
  Pass a `null` gap to turn off the time window, or replace the whole policy
  without forking the viewport.
- **CHANGED**: `MessageRunLayout` resolution used to be a static
  `ChatSenderRunLayout.resolve` and is now an instance policy on
  `ChatScrollView.senderRunLayout` (default
  `DefaultChatSenderRunLayout.instance`). Same-sender neighbors farther apart
  than `maxClusterGap` end a run (large corners, unclustered top inset).
- **ADDED**: `MessageRunLayout.extras`, an optional host chrome bag on the
  run-layout snapshot (`Object?`, default `null`). It counts in skip-rebuild
  value equality, so a custom `ChatSenderRunLayout` can change per-id chrome
  without changing first/last clustering. The package default and degenerate
  layouts leave `extras` null, and the engine never reads it. To use it, wrap
  `DefaultChatSenderRunLayout`, close over host state, set `extras`, and cast
  it in `messageBuilder`. To invalidate, pass a new unequal policy instance, or
  keep one `Listenable` / `ChangeNotifier` policy and notify
  (`RenderChatScrollView` listens). Don't use
  `ChatDataSource.notifyDataChanged` for chrome-only updates.
- **FIXED**: Deleting the first of two same-sender messages no longer leaves
  the survivor without avatar and author when the message instance is
  unchanged.
- **ADDED**: `ChatMessageBody`, a slotted in-bubble layout (`content` +
  `meta`) with last-line packing and shrink-wrap. Meta sits on the last text
  line when it fits and wraps to the next row when it doesn't. The body is a
  real child, with no internal `TextPainter` and no type-marker discovery.
  Reply and media stay outside; compose them above it in the host bubble.
- **ADDED**: `ChatMessageBody.header`, an optional in-bubble band above the
  content that counts toward shrink-wrap width. When the header is wider than
  the text, meta trails at the body end. The inline-vs-wrap decision still uses
  the padded max width, not the header width.
- **ADDED**: `ChatMessageChangeTransition`, the message edit morph. Layout
  jumps to the incoming settled size while the background bounds animate
  through paint deltas (`ChatMessageChangeParams`). Old and new text crossfade
  inside a clip of the painted bubble, and the "edited" meta enters on the same
  250 ms list-item cubic.
- **ADDED**: `ChatBubbleMetrics`, pure resolvers from `ChatMessageThemeData` +
  `MessageRunLayout` to clustered `BorderRadius` and content insets. Hosts
  resolve chrome here instead of walking neighbors in `messageBuilder`.
- **ADDED**: `ChatMessageThemeData.bubbleRadius`, `cornerNearCap`, and the
  derived `nearRadius` and media radii give clustered outer corners on mid-run
  messages.
- **EXAMPLE**: Demo bubbles use `ChatMessageBody` to pack text with time and
  status, and `ChatBubbleMetrics` for run-clustered radii. Meta stays
  intrinsic-width, with no `Align` that would defeat shrink-wrap. The incoming
  avatar, sender name and bubble tail stay on the **last** message of a
  same-sender run. `ChatMessageChangeTransition` replaces the demo's
  OverflowBox/ClipRect size lerp.

### Navigation, alignment and highlight
- **ADDED**: `alignment` on `jumpTo` / `animateTo`, a vertical alignment in
  `0..1`. `0` is the top (the default), and `0.5` centers in the scroll band
  above the bottom inset. Boundary pins clamp when there isn't enough content,
  and tail navigation stays bottom-pinned.
- **FIXED**: The alignment band runs from `topPadding` to the bottom inset.
  `0` is the band top below chrome and `1` is the band bottom above the
  composer. `alignment: 0` no longer parks the message under the app bar or
  selection bar.
- **ADDED**: Center Band leave and reopen. Hosts observe a deferred
  `ValueListenable<ChatCenterBand?>` on [ChatScrollController], which holds the
  Message under the fixed 50% paint-band ray and `offsetFromMessageTop`. They
  restore with `jumpToCenterBand(messageId, offsetFromMessageTop)`, one layout
  navigation instead of a host-composed `jumpTo` + `scrollBy`. The Anchor
  origin stays engine-only. The ray hit is geometric, so it handles a tall
  message hit mid-bubble and mixed row heights. Listener safety matches
  `visibleRange`. See ADR 009 and `CONTEXT.md` (_Center Band_,
  _ChatCenterBand_).
- **FIXED**: The mouse wheel cancelled a pending tail pin but not a pending
  Center Band or alignment settle, so layout kept re-seating the restore ray
  under early wheel input after `jumpToCenterBand`. The wheel now clears those
  pending writers the same way drag does.
- **ADDED**: A translucent tint over the target message fades to zero after a
  successful `animateTo` lands. Configure it with
  `ChatScrollView.highlightColor` and `ChatScrollView.highlightDuration`. The
  tint is on by default; pass `highlightDuration: Duration.zero` to turn it
  off globally.
- **ADDED**: Pass `highlight: false` to `animateTo` to scroll with animation
  but without the post-settle tint, for example when returning to the newest
  message. The default stays `true`.
- **ADDED**: `ChatScrollController.highlight(id)` requests a one-slot
  attention wash without moving the Anchor origin, for open-at-message.
  `jumpTo(..., highlight: true)` writes the origin and then requests the
  highlight, so the jump's hard clear can't drop the wash. The default
  `highlight: false` stays geometry-only, and unbound `animateTo` forwards the
  same flag. A deferred highlight waits until the Message is loaded **and**
  built, with no TTL and no pending-only ticker. An absent or errored message
  drops the controller slot. Clearing rules:
  - a new request replaces the old one;
  - default `jumpTo`, `jumpToCenterBand`, overlay, controller swap and dispose
    hard-clear;
  - drag and `scrollBy` fade an armed wash and hard-clear a pending one;
  - detaching and remounting with the same controller keeps the request;
  - stitch-owned jumps still don't steal an in-flight navigate-select.

  `jumpToCenterBand` has no highlight flag (ADR 009). See
  `docs/architecture/11-animation-integration.md` and `CONTEXT.md`
  (_Message highlight_, _Deferred highlight_).
- **CHANGED**: Navigate-select highlight. With `highlight: true` (the default),
  a full-width underlay arms at flight start, holds through settle plus
  `ChatScrollThemeData.highlightDuration` (1 s by default), then fades over
  about 300 ms. It shares the controller attention slot with `highlight()` and
  `jumpTo(highlight: true)`. Drag and `scrollBy` fade an armed wash and
  hard-clear a pending one; default `jumpTo`, overlay, swap and dispose
  hard-clear. Stitch-owned teleports no longer wipe the tint mid-flight. The
  bubble's selected fill stays host-owned.
- **FIXED**: Jumping to an unloaded chunk no longer flashes the highlight tint
  on a skeleton row. The tint arms only after the message is in the data source
  and its row is built.
- **FIXED**: `_onJump` clears any active post-`animateTo` highlight, so a
  programmatic `jumpTo` doesn't leave a ticker tinting a target that's no
  longer visible.
- **TESTS**: `test/widgets/chat_navigation_alignment_test.dart` covers
  alignment centering, bottom inset, oldest clamp, tail override and
  `animateTo` settle.

### Animated navigation
- **CHANGED**: Close-path and stitch share a travel-scaled duration,
  `((travel / viewportHeight) + 1) * 200` ms clamped to 300–1300, with
  `Curves.easeOutQuint`. Caller `duration` and `curve` stay API-compatible.
  `duration ≤ 0` is still an instant `jumpTo`. Otherwise the path timing
  ignores short caller durations, so tall on-screen hops and matching stitches
  take the same time. Defaults are `300ms` / `easeOutQuint`.
- **ADDED**: `AnimateToBusyPolicy` / `AnimateToDisposition` control re-entry
  while an animate is in flight (`ignore` by default, or `replace`).
  `animateTo` returns a disposition, so a host such as search next/prev can
  advance its selection only when the call was accepted or coalesced, not when
  it was ignored.
- **ADDED**: Stitch settle commits at the current progress. On normal
  completion and on user cancel, dual-translate paint offsets bake into layout
  offsets through `StitchCancelSnapshot` (`stitch.commit`). Outgoing rows no
  longer snap back for one frame when paint stops applying stitch dy.
- **FIXED**: `animateTo` with an `alignment` other than `0`, for example to
  center a search result, no longer micro-jumps mid-animation. Close-path
  animation now owns offset interpolation for the whole duration. The
  layout-time alignment snap waits until settle, and until the real message is
  built if the target row is still loading. The animator rebases its aligned
  end offset when layout geometry changes mid-flight (bottom inset, message
  height, date-header relayout), so the viewport no longer jumps after the
  animation ends. Settle runs after the final tick reposition instead of
  fighting a stale end offset.
- **FIXED**: While a close-path animation is in flight, layout no longer
  renormalizes the anchor away from the target or garbage-collects the animate
  and navigation-alignment rows. This fixes drift, a wrong landing position,
  and the target row vanishing when skeleton placeholders are visible at the
  fetch boundary.
- **FIXED**: Landing on a message taller than the build zone no longer drops
  the adjacent neighbor from the built set, so the reverse `animateTo` stays on
  close-path instead of stitching as "not built".
- **FIXED**: The far path no longer relayouts every ticker frame because of
  range-coverage checks against the intentionally short stitch strip.
- **FIXED**: The layout freeze applies only after `stitchMeasured`, so the
  post-jump measure pass can still run `pinNewest` and a tall scroll-to-bottom
  starts from the message bottom. Freezing earlier pinned from the row top and
  caused a hitch mid-flight.
- **FIXED**: While jumped, fan-out skips outgoing capture ids
  (`_skipStitchOutgoingReposition`), so paint dual-translate doesn't stack on a
  layout walk that already moved those rows.
- **FIXED**: A tall scroll-to-bottom no longer stalls while the keyboard
  animates. Bottom-pad compensate shifts close-path start and end together
  (`shiftClosePathByInset`) by the same delta as the anchor, so
  `rebaseClosePathEnd` doesn't restart the travel clock on every inset frame.
  During close-path, compensate runs as soon as the pad changes, ahead of the
  next tick.
- **FIXED**: Cancelling an in-flight far-path stitch from
  `RenderChatScrollView.detach` no longer calls `markNeedsLayout` from
  `_onStitchCancelled` / `_onStitchComplete`. This happened on a route pop or
  Overlay rebuild while scroll-to-bottom or any other stitch was running, and
  it asserted under a host `_RenderLayoutBuilder.performLayout`
  ("RenderObject was mutated when none of its ancestors is actively performing
  layout"). Detach still clears stitch capture and navigation pins, without
  baking dual-translate into a tree that is leaving.

### Tail and follow-tail
- **ADDED**: Follow-tail auto-scroll and the `ChatScrollController.isAtTail`
  listenable. When the viewport is pinned to the newest message and a new one
  arrives, it scrolls so the new message stays at the bottom edge. When the
  user has scrolled away to read history, the anchor is left alone.
- **FIXED**: Opening at or jumping to the newest message no longer lands one
  message short of the tail. Tail-targeted `jumpTo` / `animateTo` force a
  one-shot bottom repin on the first layout, even when the viewport wasn't at
  the tail before. They keep repinning until the newest message is loaded and
  settled, including after a lazy backend fetch and composer inset changes.
- **FIXED**: Jump targets past `newestKnownId`, such as a message count passed
  instead of the last id, are clamped to the known tail, so no shimmer
  placeholder row appears below the real newest message. A `jumpTo(newest)`
  issued before mount is seeded on viewport attach, so the first layout
  matches a mounted tail jump.
- **FIXED**: Close-path scroll to the known conversation end animates to
  tail-pin geometry (message bottom on the bottom inset), instead of to the
  band top followed by a layout snap.
- **FIXED**: Scrolling up through history right after the viewport mounts no
  longer snaps back to the newest message. A user drag cancels the deferred
  tail settle from open-at-newest, and the boundary pin stays off while
  off-tail until an explicit jump to the newest message.
- **FIXED**: Scrolling off the newest message no longer yanks the viewport back
  while a pending tail pin is active. Repinning continues only for a tall or
  lazy tail settle, not after the user has left the tail.
- **FIXED**: Unlike drag, the mouse wheel didn't call `_cancelPendingTailPin`,
  so a pending tail pin or lazy load after jump-to-newest pulled wheel deltas
  back to the bottom edge. The wheel now preempts the pending pin like drag.
- **FIXED**: `_publishIsAtTail` skips snapshot writes while the viewport is in
  overlay mode, so follow-tail survives an overlay-to-normal transition.
- **TESTS**: `test/widgets/chat_jump_to_tail_test.dart` covers tail pin on
  open, jump and animate to newest, clamp past the tail, overscroll at the
  tail, lazy-fetch repin, scroll-away without snap-back, and a tall newest
  message with `bottomPadding`.

### Overscroll and boundaries
- **ADDED**: Paint-time edge stretch overscroll. A clamped-layout stretch
  (`ChatStretchOverscroll`) replaces the layout rubber band and bounceback
  below. Unconsumed dy at a reached oldest or newest pin paints a scale from
  the edge, on **messages only**; the floating date header and scrollbar stay
  fixed to the viewport. It handles drag pull, fling into the edge
  (`absorbImpact`), reverse fling into content, and a soft spring return. Short
  content still stretches (`OVER_SCROLL_ALWAYS`). Wheel, keyboard and
  `scrollBy` stay hard-clamped. See `docs/architecture/05-tier1-scroll.md` and
  `06-boundaries.md`.
- **ADDED**: Short-content no-scroll mode. When all loaded messages fit in the
  viewport, drag, fling and bounceback are suppressed, the two boundary pins no
  longer fight, and the scrollbar is hidden, as in a non-scrollable list.
- **ADDED**: Rubber-band overscroll at conversation boundaries, later replaced
  by the paint stretch above. Pulling past the oldest or newest message applied
  damping, and on release a short spring pulled the anchor back. Mouse wheel,
  keyboard, fling and `animateTo` kept the hard clamp. Tests that asserted a
  hard clamp on direct drag saw a ~200 ms bounceback instead and needed
  `pumpAndSettle()`.
- **FIXED**: While edge stretch kept the ticker alive, a tick-path
  `pinNewest` against the live pad ran before layout compensated. On keyboard
  dismiss that shifted the newest message twice, leaving it under the
  composer. A dirty pad now skips the tick pin, and stretch clears on a pad
  change.
- **FIXED**: `_layoutOverlayMode` resets `_dragInProgress` and clears any
  bounceback state, so `_clampBoundaries` is no longer silently suspended after
  an overlay transition.
- **FIXED**: `_onScrollBy` cancels any in-flight bounceback, so a programmatic
  scroll wins over the passive spring back.
- **FIXED**: `_signedOverscroll` returns the larger violation when both
  boundaries are violated at once (a short conversation pulled past both
  edges), so the bounceback pulls toward the dominant side.
- **PERFORMANCE**: `_applyOverscrollResistance` returns early when neither
  boundary is reached, which skips the per-drag-tick `_signedOverscroll` walk
  for the common mid-conversation drag.

### Insets
- **FIXED**: When the keyboard or composer inset grows or shrinks while
  scrolled in history, visible content shifts by the inset delta (anchor
  compensation) instead of only repinning the tail. Opening the keyboard
  mid-history no longer yanks the viewport as if the user were at the newest
  message.
- **FIXED**: A `bottomPadding` listenable swap repins the newest message at the
  new inset even when a concurrent `dataSource` update cleared
  `_wasAtTailLastLayout` in the same `updateRenderObject` cascade.

### Data loading and absent ids
- **ADDED**: Chunk prefetch during scroll. While the user flings or drags,
  `ChatChunkFetchScheduler` starts network fetches without waiting for the
  scroll to settle. It requests one leading chunk page in the direction of
  scroll velocity, with an optional one-chunk look-ahead past the laid-out
  band. It passes `allowWiden: false`, so a growing layout span can't cancel
  and restart a page in flight. After settle, the poll still requests the full
  laid-out band, which covers holes and any missed chunks. The
  destination-window load-gate and hole-only interval gating are unchanged.
  See `docs/architecture/04-layout-pipeline.md` §13.
- **ADDED**: `ChatDataSource.invalidate()` marks all loaded chunks stale so the
  viewport refetches on the next pass. It is lazy: in-range chunks get a fresh
  fetch from the existing poll, and off-range chunks stay dirty until visited.
  Use it after an SSE or WebSocket reconnect, on `AppLifecycleState.resumed`,
  or for pull-to-refresh.
- **ADDED**: `ChatScrollController.oldestKnownId` / `newestKnownId`, a
  read-only passthrough of the wired source's boundary ids, updated on attach,
  on boundary listener callbacks, and on each layout publish.
- **ADDED**: `ChatMessageStatus.absent`. `statusOf(id)` returns this flag when
  a message id is confirmed permanently absent within the conversation's known
  bounds.
- **CHANGED**: Confirmed-absent message ids never reach `messageBuilder`; they
  are excluded before `buildChild` and selection chrome. Deleting the layout
  anchor reassigns it to a present neighbor instead of leaving a shimmer or an
  empty selectable row. Integrators must not rely on returning zero-size
  widgets for absent status; returning `SizedBox.shrink()` is no longer
  needed.
- **ADDED**: Deleting a tall anchor message while scrolled into its interior no
  longer jumps the viewport. The reading position near the composer holds
  within 8 logical pixels.
- **CHANGED**: Chunk LRU eviction runs in two passes. At the `maxChunks`
  budget, off-layout chunks go first, so a `jumpTo` can admit the destination
  range. Under budget, off-screen chunks are kept, so `jumpTo` and scrolling
  back can reuse cached data without a refetch.
- **CHANGED**: Lazy-pagination fan-out no longer clamps upward layout to
  `oldestKnownId` while `reachedOldest` is false. `oldestKnownId` is the oldest
  _loaded_ page, not the conversation floor.
- **CHANGED**: The fetch poll no longer treats errored chunks as pending layout
  work. `ChatDataSource` backoff and `retryChunk` own retries instead.
- **FIXED**: When a batch of messages is deleted, ids in the deleted range are
  confirmed permanently absent after the first successful fetch. Layout skips
  absent ids entirely, so no shimmer or placeholder row appears for them.
  Absent slots contribute zero height, which keeps the scrollbar position
  proportional to real content across large deletion gaps.
- **FIXED**: Fan-out skips runs of absent ids in O(chunk) time instead of
  visiting every id, and skips fully-absent 64-slot chunks in O(1). A
  conversation with one real message at id 1 and one at id 10,001 renders
  exactly two rows with no stall.
- **FIXED**: The per-frame scroll reposition (`_repositionMessagesOnly`) used
  to stop at the first absent id. Absent ids are never in the render children
  map, so the `null` check ended the walk and left real messages past the gap
  with stale y-offsets. Messages now snap back into place every frame across
  any absent zone.
- **FIXED**: The post-fetch absent-marking pass used to skip null slots outside
  the initial `[oldestKnownId, newestKnownId]` range. Fetches triggered by
  paging older messages now mark absent any slot the server didn't return,
  wherever the slot falls relative to the initial boundaries.
- **FIXED**: `upsertMessage` and `upsertMessages` call a new
  `ChatScrollChunk.clearAbsentSlot`, so a server-pushed message at a previously
  deleted slot clears the absent flag and appears on the next frame without a
  chunk invalidation.
- **FIXED**: `invalidate()` clears the absent bitmask on every chunk, so the
  next fetch can re-confirm or restore each slot without a stale absent flag
  blocking it.
- **FIXED**: `invalidate()` no longer fires two `notifyDataChanged` events on a
  source with running fetches. The cancel-fetch and dirty-marking passes are
  coalesced.
- **FIXED**: The absent-skip helpers (`_nextNonAbsentIdDown` /
  `_nextNonAbsentIdUp`) return one past the boundary when every id in the range
  is absent, so fan-out always terminates.
- **FIXED**: The snap that brings the anchor back into view after a large
  absent collapse now fires only after scroll velocity reaches zero. It no
  longer fights fling physics, and the viewport doesn't stay blank after the
  scroll settles.
- **FIXED**: Each chunk stores confirmed-absent slots as per-slot flags
  (`0`/`1`) plus an absent-slot count, instead of a packed 64-bit integer mask.
  Slot 63, the O(1) fully-absent fan-out skip, and the invalidate/upsert clear
  paths now work on every platform, including dart2js/web.
- **FIXED**: `seedBoundaries` accepts explicit `null` ids, so removing the
  final message clears `oldestKnownId` / `newestKnownId` and the empty-chat
  overlay can appear.
- **FIXED**: After connect seeds only `newestKnownId` (lazy oldest),
  `insertMessage` / `insertMessages` no longer set `oldestKnownId = insertId`
  when the new id is at or past the tip. That broke the `oldest ≤ newest`
  assert on tail send. An insert now seeds the oldest id only when the id is
  strictly older than the known newest, or when it shrinks an existing oldest.
- **FIXED**: Scrolling up before the oldest page loads no longer leaves blank
  space. Layout fan-out and range-coverage checks use a floor of `0` until
  `reachedOldest` is true.
- **FIXED**: At `maxChunks`, `jumpTo` evicts stale chunks outside the new
  layout range before the destination chunk is fetched. Stale render children
  are dropped at the start of the jump layout, so renormalize and clamp don't
  fan across the old id span.
- **FIXED**: A `chunkErrorBuilder` swap always schedules a relayout, not only
  when chunk-error tiles are already mounted, so turning the builder on
  mid-flight replaces per-id shimmers with chunk tiles.
- **TESTS**: `chat_widgets_test`: **a failed fetch flips chunks to error and
  retries** is temporarily skipped (`skip: true`). The poll/backoff
  interaction still hangs under test; the other widget tests pass.
- **TESTS**: `test/widgets/chat_lazy_pagination_test.dart` covers
  partial-oldest-boundary pagination.
- **DOCS**: An architecture decision record for the position model documents
  the per-chat sequential id guarantee, the full-chunk `fetchRange` invariant,
  and why the fetch API is not cursor-based.

### Visible range, scrollbar and RTL
- **ADDED**: `ChatVisibleRange` boundary fractions, `firstVisibleFraction` and
  `lastVisibleFraction` (now `firstRow` / `lastRow.visibleFraction`, see
  Breaking changes): the share of each boundary message's exposable height
  inside the scrollable paint band. The denominator
  is `min(messageHeight, bandHeight)`, so a tall message reports `1.0` when it
  fills the band. They are published on every layout and scroll update,
  including when the ids don't change.
- **ADDED**: Chat scrollbar thumb and track colors come from
  `ChatScrollbarThemeData` on `ThemeData.extensions` or a nested `Theme`
  widget. Thumb position and drag-to-jump behavior are unchanged.
- **CHANGED**: Thumb position is height-weighted: the pixel offset at the top
  scroll-band edge over `(estimatedExtent − viewportBandHeight)`, using the
  average built row height to extrapolate unloaded ids. Thumb size scales with
  `viewportBandHeight / estimatedExtent`, as native scrollbars do. It clamps
  hard at the tail (`1.0`) and the oldest head (`0.0`). This replaces the
  id-linear band-edge mapping, which weighted every message id equally
  regardless of row height, so the thumb stuck or jumped at the tail when
  message sizes varied. `ChatScrollScrollbar` logs still include the legacy
  anchor and id-linear values for comparison.
- **FIXED**: Track, thumb travel, hit strip and drag progress mapping respect
  `ChatScrollView` `topPadding` and `bottomPadding`, the same scroll band used
  for message alignment. Thumb id mapping (Variant A) is unchanged.
- **ADDED**: `ChatScrollView` follows the ambient `Directionality` and accepts
  an explicit `textDirection` override. The scrollbar mirrors to the leading
  edge. With an override set, a `Directionality` widget wraps the message
  subtree, so `messageBuilder` reads the same direction the chrome uses.
- **CHANGED**: Ambient `Directionality.rtl` moves the scrollbar to the left
  edge. RTL hosts used to get it on the right. Force LTR with
  `ChatScrollView.textDirection: TextDirection.ltr` if needed.

### Input and keyboard shortcuts
- **ADDED**: `ChatKeyboardShortcuts`, a wrapper widget for desktop keyboard
  navigation (PageUp/Down, Home/End, ArrowUp/Down). It defaults to
  `autofocus: false`, so a sibling composer `TextField` keeps focus. Set
  `ChatKeyboardShortcuts.autofocus` to `true` if the wrapper should claim
  focus on mount.
- **ADDED**: `ChatScrollController.scrollBy(double pixels)`, a programmatic
  scroll API with `addScrollByListener` callbacks and a new
  `ChatProgrammaticScroll` typed event.
- **FIXED**: Tapping or pressing the viewport during a fling stops inertial
  scroll at once. A tap or long-press during a fling cancels the scroll without
  toggling or entering selection. Selection gestures on a still list are
  unchanged.
- **FIXED**: A controller swap during a drag re-creates the gesture recognizer
  and clears `_dragInProgress` instead of leaking drag state into the new
  controller.
- **PERFORMANCE**: `ChatKeyboardShortcuts` hoists its `Shortcuts` / `Actions`
  maps out of the per-rebuild `LayoutBuilder`, so a keyboard show or hide no
  longer reallocates the six action callbacks.

### Keyboard panel and panel catalog
- **ADDED**: `KeyboardPanelController` (chat_chrome), the host-owned source of
  truth for the keyboard-replacement panel. It provides typed listeners for
  open, search and tab; `open` / `close` / `openSearch` / `closeSearch` /
  `selectTab` / `handleBack`; inset claim and release through
  [ChatBottomInsetController]; and projection into [KeyboardPanel] motion
  without a GlobalKey on the panel State. See ADR 007 and
  `docs/panel-catalog/CONTEXT.md` (_KeyboardPanel_, _KeyboardPanelController_).
- **ADDED**: Panel Catalog Viewport. Keyboard-panel emoji, stickers and GIFs
  get an extent-scroll paint-leaf engine, instead of a permanent
  `SuperSliverList` body or a fork of Chat Scroll's message-id/anchor model.
  New repo-root packages:
  - **`packages/catalog_assets`** is a process-wide catalog asset cache
    (`CatalogAssetCache` / `MemoryCatalogAssetCache` /
    `FakeCatalogAssetCache`). It tracks key plus cache type and size class,
    readiness (`loading` / `ready` / `failed`), and attach/refcount retention;
    fetch and decode stay outside. Settled ready or failed entries survive the
    last detach, so a pager can leave and return. Loading-only orphans are
    dropped.
  - **`packages/panel_catalog`** has `PanelCatalogViewport` and the
    package-private `RenderPanelCatalog`. It provides absolute extent scroll,
    recycled paint leaves, section headers in the extent, and ballistic fling
    that suppresses the tap or long-press used to cancel it. Hit-testing is
    viewport-owned (`onLeafTap`, long-press start/move/end, optional
    `leafLongPressEligible`), presses get a scale and list-selector highlight,
    and theming goes through `PanelCatalogTheme` / `PanelCatalogThemeData`.
    `PanelCatalogController.jumpToSection` takes a near path (≤ 9 flat rows,
    `kFarPathDistanceGateFactor`) or a far path through `CatalogFarStitch`
    (capture, teleport, dual-translate; not a bare `jumpTo`). KeyboardPanel
    chrome stays in `chat_chrome`. Data-source notifications mirror chat
    (`addDataListener` / `notifyDataChanged`). See ADR 006 and
    `docs/panel-catalog/CONTEXT.md`.
  - The example KeyboardPanel hosts the viewport. Sticky search and the bottom
    bar follow catalog scroll events, and reselecting a type tab lands through
    `jumpToSection`.
  - A correctness suite and A/B benchmarks against SuperSliverList and
    SliverGrid live in `packages/panel_catalog/test/benchmark/`.
- **REMOVED**: The legacy `chat_chrome_emoji_*` recents migration and dual-read
  in emoji_data. Only `emoji_data_use_history` is persisted.
- **FIXED**: Sticky emoji search keeps focus and the cursor when keyword
  results flip between empty and non-empty. The empty-results overlay keeps a
  stable [Stack] slot ahead of the search field, so a null-aware insert or
  remove can't remount [EmojiSearchField].
- **FIXED**: Cold-start `rasterizeGlyphsForWarmup` yield timers are cancelled
  on detach and dispose (`cancelWarmup` + `shouldContinue: () => attached`), so
  widget-test teardown no longer finds a pending `Timer`.

### Internal refactors
No public API change in this group.

- **CHANGED**: Floating day-header state, the top-day scan, inline divider fade
  math and layout rebuild decisions moved to `ChatFloatingHeaderController` in
  `lib/src/chat_scroll/chat_floating_header_controller.dart`.
  `RenderChatScrollView` delegates to it and keeps `RenderBox` ownership and
  `buildFloatingHeader` inflation.
- **CHANGED**: `animateTo` close-path scroll, far-path crossfade and the
  post-settle highlight tint moved to `lib/src/chat_scroll/chat_animator.dart`.
  `ChatAnimator` implements `ChatScrollAnimator`, and `fadeLayer` stays on the
  render object. Debug asserts and doc comments spell out the
  `ChatChildManager` / `invokeLayoutCallback` contract on `ChatScrollElement`.
- **CHANGED**: The range-fetch state machine (token cancellation,
  exponential-backoff retry, `fetchingChunks` tracking) moved to
  `ChatRangeFetch` in `lib/src/chat_scroll/chat_range_fetch.dart`. `ChatDataSource` delegates
  `requestChunks`, `cancelFetch`, `retryChunk` and the fetch half of
  `invalidate` to it. Behavior is unchanged; the split makes the state machine
  unit-testable.

### Repository
- **CHANGED**: Shared libraries live under repo-root `packages/`:
  `catalog_assets`, `panel_catalog`, `emoji_data` and `chat_chrome`. The
  example app resolves chrome and data through path deps, and
  `keyboard_insets*` stay under `example/packages`. `chat_scroll_view` remains
  at the repo root. See `CONTEXT-MAP.md` and ADR 006.
- **DOCS**: The scroll runtime constitution lives under `docs/architecture/` as
  an OKF concept set, from the coordinate model through known limitations.
  `docs/chat_viewport_architecture.md` now points there.
- **TESTS**: Golden baselines for the demo widgets (bubbles, shimmer,
  chunk-error tile, empty state, initial skeleton, date separator). Linux only;
  see `test/golden/demo_widgets_golden_test.dart`.

### Example app
- **EXAMPLE**: The demo chat resumes at the stored last-read position instead
  of always jumping to the newest message. A first visit still opens at the
  tail. The read position is stored in memory when the user reaches the
  conversation tail, including through the new-messages pill. Off-tail open
  uses `kDemoLastReadOpenAlignment` (`0.5`).
- **EXAMPLE**: `DemoLastReadStore` and `resolveOpenAnchor`, demo-only helpers
  for per-conversation last-read persistence and open-anchor resolution. A
  stale id resolves to the previous surviving message, and an out-of-range id
  clamps to the oldest or newest.
- **EXAMPLE**: `NewMessagesPill.lastSeenNewestId`, a `ValueNotifier` baseline
  for the unread counter. It advances while scrolling toward newer messages and
  at the tail, and replaces `initialLastSeenNewestId`.
- **EXAMPLE**: `NewMessagesPill` advances the read baseline during scroll only
  when `lastVisibleFraction` crosses `visibilityThreshold` (default `0.5`) on a
  rising edge, so a one-pixel sliver no longer marks a message as read.
- **EXAMPLE**: The new-messages pill uses `animateTo(..., highlight: false)`,
  so the tail bubble isn't highlighted after a tap.
- **EXAMPLE**: System back or pop while in message selection mode clears the
  selection instead of leaving the screen.
- **EXAMPLE**: Entering selection drives `ChatScrollView.topPadding` from the
  `SelectionAppBar` slide animation, so the floating day header moves with the
  overlay instead of sitting behind it.
- **EXAMPLE**: `ChatComposer` takes optional `bottomInset` and
  `onSizeChanged`. Keyboard height is applied outside the composer's measure
  tree, so layout reports content height only.
- **FIXED**: Opening with only a few unread messages and large bubbles no
  longer flashes the new-messages pill away or zeroes the unread count when
  `isAtTail` flickers for a frame during layout settling. The pill applies
  stable at-tail hysteresis before dismissing or advancing the read baseline,
  and demo last-read persistence follows baseline changes instead of raw tail
  edges.
- **FIXED**: Tapping jump-to-newest no longer flashes "0 new messages" during
  the pill's fade-out. The last non-zero count stays until the opacity reaches
  zero.
- **FIXED**: The scroll-to-bottom badge keeps the unread count through the
  FAB's hide fade after tap-to-newest. The baseline may drop to zero
  mid-flight, but the badge doesn't clear before the opacity reaches 0.
- **FIXED**: A drag that aborts `animateTo(newest)` no longer latches
  stable-at-tail on the scroll-to-bottom FAB. Settle writes the read baseline
  only when layout confirms `isAtTail`.
- **FIXED**: `resolveOpenAnchor` trusts a stored id within known bounds even
  when the message isn't cached yet (metadata-only connect). The backward walk
  applies only to confirmed deletions. The backend `connect()` now seeds
  `oldestKnownId`, so an off-tail open doesn't fall back to id `0`.
- **FIXED**: `WidgetChatScreen` jumps to `newestKnownId` on connect instead of
  deriving the anchor from `totalMessages`.
- **FIXED**: `CommentsDataSource` and `GeneratedChatDataSource` skip ids marked
  removed in memory when they assemble `fetchRange` results.
- **TESTS**: `test/widgets/chat_open_at_last_read_test.dart` covers off-tail
  open, unread count, pill jump-to-newest (no zero flash), tail persistence,
  live arrivals and stale last-read recovery.
- **TESTS**: `test/widgets/chat_new_messages_pill_test.dart` covers progressive
  unread count on scroll, arrival into an empty source, and at-tail baseline
  updates.

### Demo backend
- **EXAMPLE**: A `supabase/` stack you can copy into a project replaces the
  Dart Shelf `backend/`. It has a Postgres schema aligned to `chat_protocol`,
  Edge Functions (`load_chats`, `load_chat`, `load_messages`, `send_message`,
  `get_read_state`, `update_read_state`), Realtime on `messages` (≥10k
  messages, id remap +1), and server-backed last-read through
  `chat_read_state` (seeded at message id **9951**). `BackendChatDataSource`
  calls the Edge Functions with lazy boundary discovery, without
  `GET /api/conversation` or `totalMessages`. Run `./scripts/dev.sh`, then
  `flutter run --dart-define-from-file=config/development.supabase.json`.
- **EXAMPLE**: `ChatComposer` is wired to `BackendChatDataSource.sendMessage`.
  The tail follows on send through the existing `notifyDataChanged`. A failure
  shows a SnackBar and keeps the composer text. Connect seeds `newestKnownId`
  from `load_chat`'s `ChatEntry.last_message.id`, not from `load_messages` or a
  total count.
- **EXAMPLE**: `ChatKeyboardShortcuts.preserveExternalFocus` keeps the soft
  keyboard up during viewport scroll and tap while composing. The demo screen
  enables it on `WidgetChatScreen`.
- **EXAMPLE**: A `chat_last_message` Postgres table plus an `AFTER INSERT`
  trigger on `messages` maintains `LastMessagePreview`. A backfill runs after
  the bulk demo seed. `load_chat` / `load_chats` read the denormalized row
  instead of scanning the tail.
- **DOCS**: Migrations carry three-layer SQL docs (`--` above tables and
  columns, plus `COMMENT ON`). `supabase/functions/_shared/` and the handler
  modules carry JSDoc with inline enum and error-slug tables.
- **EXAMPLE**: `protocol_enums.ts` holds canonical ChatKind, MessageKind,
  MessageFlags, UserFlags, Permission and RichStyle tables with hex values,
  reserved bit ranges, parse helpers and documented side effects (for example
  the DELETED tombstone).
- **REMOVED**: The `health` Edge Function, replaced by the protocol-shaped
  `load_chats` / `load_chat`.
- **REMOVED**: The Dart `backend/` package, replaced by the Supabase stack.
  It was a Dart HTTP server with SQLite storage, paginated
  `GET /api/messages`, conversation metadata, a seed script and tests.
- **EXAMPLE**: `BackendChatDataSource`, an HTTP-backed `ChatDataSource` for the
  demo backend. It loads conversation metadata on `connect()`, applies
  `rangeMeta` boundary updates from each fetch, and throws
  `BackendConnectionException` with a hint on what to check when the server is
  unreachable. `WidgetChatScreen` loads through
  `BackendChatDataSource.connect()`, and `DemoBackendError`
  shows connection failures with a retry button.
- **EXAMPLE**: `UserChatMessage.fromJson` decodes backend message payloads.
- **EXAMPLE**: `DemoConfig.backendUrl`, resolved from
  `--dart-define-from-file` (`config/development.json`,
  `config/development.android.json`, or the generated
  `config/development.android.device.json`).
- **EXAMPLE**: `scripts/dev.sh` seeds the database, starts the backend, and
  writes `config/development.android.device.json` with the host machine's LAN
  IP for physical-device debugging.
- **EXAMPLE**: VS Code launch configs for desktop, the Android emulator
  (`10.0.2.2`) and a USB Android device (Mac LAN IP).
- **FIXED**: `UserChatMessage.fromJson` no longer calls `DateTime.parse('')`
  when `updatedAt` is missing. The resulting `FormatException` marked every
  fetched chunk as errored and showed `DemoChunkErrorTile` for every message.
- **FIXED**: Debug and profile Android manifests allow cleartext HTTP for USB
  devices, and `dev.sh` writes the Mac LAN IP config automatically
  (gitignored).
- **TESTS**: `test/backend_chat_data_source_test.dart` covers backend parsing.
