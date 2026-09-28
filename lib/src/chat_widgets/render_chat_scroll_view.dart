// ignore_for_file: prefer_asserts_with_message

import 'dart:async' show scheduleMicrotask, unawaited;
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_animator.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_chunk_fetch_scheduler.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_day_header_delegate.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_floating_header_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_mutations.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_row_chrome_delegate.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_row_chrome_transition.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_activity.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_events.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_motion.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_sender_run_layout.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_stretch_overscroll.dart';
import 'package:chat_scroll_view/src/chat_scroll/navigation_placement.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_data_source_ext.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_opacity_paint.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_row_chrome.dart'
    show RenderChatRowChrome;
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_element.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_metrics.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_pointer.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_request.dart';
import 'package:chat_scroll_view/src/util/constants.dart';
import 'package:chat_scroll_view/src/util/logger.dart';
import 'package:flutter/foundation.dart'
    show Listenable, ValueListenable, precisionErrorTolerance;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:meta/meta.dart' show internal, visibleForTesting;

/// Parent data for a viewport child.
///
/// For a message: its [id], the [offset] of its top edge within the viewport
/// (viewport-local Y, may be negative), whether it [startsDay] (carries an
/// inline date divider), its [dayBucket] (day-grouping key, `null` until the
/// message loads), and the row chrome inputs ([paintTop], [headerZone],
/// [scrollActivity]). The floating day header reuses this type — only
/// [offset] is meaningful for it.
class ChatMessageParentData extends ParentData {
  /// Message id this render box represents; `0` for the floating day header.
  int id = 0;

  /// Viewport-local Y of this child's top edge; may be negative when scrolled
  /// off-screen.
  double offset = 0;

  /// `true` when this message carries an inline day separator above its body.
  bool startsDay = false;

  /// Group key (`DateTime`, record, string, anything equatable) — produced by
  /// the viewport's `groupBy` callback. `null` when the message has not loaded
  /// or grouping is disabled.
  Object? dayBucket;

  /// Viewport-local paint Y of this child's top edge: [offset] plus any
  /// paint-only translation (far-path stitch), mapped through the live edge
  /// effect. Row chrome resolves its delegates against it.
  double paintTop = 0;

  /// Floating day header zone as of the viewport's latest frame.
  ChatFloatingHeaderZone headerZone = ChatFloatingHeaderZone.none;

  /// Scroll activity in `[0, 1]` as of the viewport's latest frame; `1` when
  /// the viewport runs no activity clock.
  double scrollActivity = 1;

  /// Local Y of the message body within this child — the summed height of
  /// its row chrome. `0` when the child is the body alone. A
  /// `RenderChatRowChrome` writes it on every layout; pointer resolution
  /// treats a press above it as row chrome, so long-press selection and the
  /// message menu never start on chrome.
  double messageBodyTop = 0;
}

/// Kind of full-viewport overlay the element is asked to build. Internal
/// contract between `RenderChatScrollView` and `ChatScrollElement`.
///
/// * `loading` — the data source has nothing yet ([ChatDataSource.isInitialLoading]).
/// * `empty` — the data source confirmed the conversation has no messages
///   ([ChatDataSource.isEmpty]).
/// * `none` — no overlay, the viewport is in normal fan-out mode (used to ask
///   the element to drop a previously-built overlay).
@internal
enum ChatOverlayKind { none, loading, empty }

/// Contract the render object uses to lazily inflate / dispose children and to
/// signal viewport geometry moves for scroll-observer chrome.
///
/// Implemented by `ChatScrollElement` only. The render object calls the
/// build methods during `performLayout` (wrapped in `invokeLayoutCallback`)
/// and the remove methods to garbage-collect children outside the build
/// range. [dispatchViewportGeometryScrollNotification] is the post-layout /
/// Tier-1 wake-up for ancestor observers — not gated on
/// [invokeLayoutCallback]. Public API consumers should never implement or
/// call this directly.
@internal
abstract interface class ChatChildManager {
  /// Inflate or update the widget for message [id]; returns its render box.
  /// [startsNewDay] asks the element to prepend an inline group separator.
  /// [groupBucket] is the `groupBy` key when [startsNewDay] is true.
  /// [runLayout] is bucket-scoped sender-run position for skip-rebuild cache.
  ///
  /// Must only be called from within [invokeLayoutCallback]. Calling
  /// from any other context will assert in debug mode.
  RenderBox? buildChild(
    int id, {
    required bool startsNewDay,
    required MessageRunLayout runLayout,
    Object? groupBucket,
  });

  /// Deactivate the elements for [ids] that are no longer needed.
  ///
  /// Must only be called from within [invokeLayoutCallback]. Calling
  /// from any other context will assert in debug mode.
  void removeChildren(List<int> ids);

  /// Inflate / update / remove the floating group header for [bucket] and
  /// [firstMessageDate] (`null` removes it). Called during layout.
  ///
  /// Must only be called from within [invokeLayoutCallback]. Calling
  /// from any other context will assert in debug mode.
  RenderBox? buildFloatingHeader(Object? bucket, DateTime? firstMessageDate);

  /// Inflate or update the chunk-error tile for [chunkIndex]. Called when
  /// the chunk is in error state *and* a `chunkErrorBuilder` was supplied.
  ///
  /// Must only be called from within [invokeLayoutCallback]. Calling
  /// from any other context will assert in debug mode.
  RenderBox? buildChunkError(int chunkIndex, int firstId, int lastId);

  /// Deactivate chunk-error tiles for [chunkIndices] no longer in range.
  ///
  /// Must only be called from within [invokeLayoutCallback]. Calling
  /// from any other context will assert in debug mode.
  void removeChunkErrors(List<int> chunkIndices);

  /// After child Y offsets move, wake ancestor [ScrollNotificationObserver]
  /// listeners (deferred off layout). Safe outside [invokeLayoutCallback].
  void dispatchViewportGeometryScrollNotification();

  /// Inflate / update / remove the full-viewport overlay (loading or empty).
  /// Pass [ChatOverlayKind.none] to drop the currently-built overlay.
  ///
  /// Must only be called from within [invokeLayoutCallback]. Calling
  /// from any other context will assert in debug mode.
  RenderBox? buildOverlay(ChatOverlayKind kind);
}

/// Widget-based endless chat viewport render object.
///
/// Children are real [RenderBox]es (each a `RepaintBoundary`), keyed by
/// message id in a sparse [SplayTreeMap]. Layout is anchor-based — children
/// are positioned around [ChatScrollController.anchorMessageId], never against
/// a global content height. Scrolling repositions children and calls
/// [markNeedsPaint] (no layout, no rebuild — Tier 1); the framework moves the
/// cached child layers.
class RenderChatScrollView extends RenderBox {
  /// Creates the render object that lays out message children around the
  /// controller's anchor and drives scroll physics.
  RenderChatScrollView({
    required ChatDataSource dataSource,
    required ChatScrollController controller,
    required double cacheExtent,
    double extraBuildExtent = 0.0,
    bool ticking = true,
    bool reverse = false,
    ValueListenable<double>? bottomPadding,
    ValueListenable<double>? topPadding,
    Object Function(IChatMessage)? groupBy,
    ChatDayHeaderDelegate dayHeaderDelegate = const ChatFadingDayHeader(),
    ChatScrollActivityTiming? scrollActivityTiming,
    ChatSenderRunLayout senderRunLayout = DefaultChatSenderRunLayout.instance,
    ValueListenable<int?>? unreadBoundary,
    bool hasErrorBuilder = false,
    bool hasEmptyBuilder = false,
    bool hasLoadingBuilder = false,
    Color highlightColor = const Color(0x280A90F0),
    Duration highlightDuration = const Duration(
      milliseconds: kHighlightHoldDurationMs,
    ),
    TextDirection textDirection = TextDirection.ltr,
    ChatScrollbarThemeData scrollbarTheme = ChatScrollbarThemeData.light,
    ChatSelectionController? selectionController,
    ChatMessageMenuRequestCallback? onIdleMessageTap,
    ChatMessageMenuRequestCallback? onSecondaryMessageTap,
    bool Function(IChatMessage message)? isSelfMessage,
    ChatScrollPhysics physics = const ChatScrollPhysics.stretch(),
  }) : _motion = ChatScrollMotion(physics),
       _dataSource = dataSource,
       _controller = controller,
       _selectionController = selectionController,
       _onIdleMessageTap = onIdleMessageTap,
       _onSecondaryMessageTap = onSecondaryMessageTap,
       _isSelfMessage = isSelfMessage,
       _cacheExtent = cacheExtent,
       _extraBuildExtent = extraBuildExtent,
       _ticking = ticking,
       _reverse = reverse,
       _bottomPadding = bottomPadding,
       _topPadding = topPadding,
       _groupBy = groupBy,
       _dayHeaderDelegate = dayHeaderDelegate,
       _scrollActivityTiming = scrollActivityTiming,
       _senderRunLayout = senderRunLayout,
       _unreadBoundary = unreadBoundary,
       _hasErrorBuilder = hasErrorBuilder,
       _hasEmptyBuilder = hasEmptyBuilder,
       _hasLoadingBuilder = hasLoadingBuilder,
       _textDirection = textDirection,
       _scrollbarTheme = scrollbarTheme {
    _animator = ChatAnimator(
      controller: _controller,
      offsetToBuiltMessage: _offsetToBuiltMessage,
      messageIntersectsPaintBand: _messageIntersectsPaintBand,
      viewportHeight: () => hasSize ? size.height : 600.0,
      closePathEndOffsetFor: _closePathEndOffsetFor,
      isTailClosePathTarget: _isTailClosePathTarget,
      childForId: (id) => _children[id],
      // Paint Y (layout + stitch dual-translate) so highlight rides the row.
      offsetOfChild: (child) {
        final pd = _parentData(child);
        return pd.offset + _stitchPaintDyIfActive(pd.id);
      },
      heightOfChild: (child) => child.size.height,
      isHighlightReady: (id) =>
          _dataSource.getMessage(id) != null && _children.containsKey(id),
      shouldDropPendingHighlight: (id) {
        final status = _dataSource.statusOf(id);
        return status.isAbsent || status.isError;
      },
      isDestinationReady: (id) => _dataSource.getMessage(id) != null,
      requestDestinationWindow: (id) {
        final prev = _chunkFetchScheduler.navigationDestinationChunk;
        _chunkFetchScheduler.setNavigationDestinationId(id);
        // One-shot reopen only when the pin is newly established — not on
        // every stitch/load-gate reassert (that dirtied + notified every frame).
        final next = ChatScrollChunk.chunkOf(id);
        if (prev == next) return;
        scheduleMicrotask(() {
          if (!attached) return;
          _dataSource.reopenIdForFetch(id);
        });
      },
      clearDestinationWindow: _chunkFetchScheduler.clearNavigationDestination,
      markNeedsPaint: markNeedsPaint,
      markNeedsLayout: markNeedsLayout,
      ensureTicker: _ensureTicker,
      cancelFling: _cancelFling,
      cancelOverscroll: _cancelOverscroll,
      prepareStitchCapture: _prepareStitchCapture,
      onStitchCancelled: _onStitchCancelled,
      onStitchComplete: _onStitchComplete,
      highlightColor: highlightColor,
      highlightDuration: highlightDuration,
    );
  }

  /// Layout-pass counter for `anchor.*` diagnostics.
  int _fetchAnchorLayoutFrame = 0;

  int? _scrollbarLogLastAnchorId;
  double? _scrollbarLogLastAnchorH;
  double? _scrollbarLogLastProgress;
  int _scrollbarLogPaintCounter = 0;

  /// Layout-pass anchor snapshot for end-of-layout delta detection.
  int? _fetchLogAnchorIdAtLayoutStart;
  double? _fetchLogAnchorYAtLayoutStart;
  int? _fetchLogBandIdAtLayoutStart;
  double? _fetchLogBandBottomAtLayoutStart;

  /// Layout geometry captured before absent-anchor reassignment on delete.
  /// Consumed by [_preserveViewportAfterDelete].
  _BeforeDeleteLayoutSnapshot? _beforeDeleteLayout;

  /// True after [_preserveViewportAfterDelete] runs this layout pass.
  bool _deleteCollapseViewportPreservedThisLayout = false;

  /// Gates renormalize and tail pin until end of delete-recovery layout pass.
  bool _deleteCollapseRecoveryActive = false;

  /// [_BeforeDeleteLayoutSnapshot.wasAtTailBefore] for the active recovery pass.
  bool _deleteCollapseWasAtTailBefore = false;

  /// [_BeforeDeleteLayoutSnapshot.userPreemptedTailBefore] for the active recovery pass.
  bool _deleteCollapseUserPreemptedTailBefore = false;

  /// Band gap to match after delete; set when scroll was adjusted.
  double? _deleteCollapseExpectedBandGap;

  static const double _deleteCollapseEpsilon = 0.5;

  /// How far past the scroll-band bottom (`bottomEdge`) the newest message may
  /// sit and still count as [isAtTail] for follow-tail / send.
  ///
  /// Manual flings often die a few px into the composer pad. A tiny slop keeps
  /// follow-tail alive without a corrective pin-up — pin-up on small
  /// scroll-away fights the user leaving the tail. Forced pull-up stays on
  /// `repinBottom` only (jump / new newest / same-id height growth).
  static const double _tailEdgeSlop = 12;

  /// Set by `ChatScrollElement` in `mount`. Drives lazy child inflation.
  ChatChildManager? childManager;

  /// messageId -> message render box, sorted ascending (top-to-bottom).
  final SplayTreeMap<int, RenderBox> _children = SplayTreeMap<int, RenderBox>();

  /// chunkIndex -> chunk-error render box, sorted ascending. One tile per
  /// failed chunk in the build range. Kept separate from [_children] so a
  /// message at the chunk's first id (when the chunk just transitioned out
  /// of error) does not collide with the lingering chunk-error tile —
  /// distinct slot namespaces avoid silent overwrites in the render layer.
  final SplayTreeMap<int, RenderBox> _chunkErrors =
      SplayTreeMap<int, RenderBox>();

  // --- Configurable inputs ---------------------------------------------------

  ChatDataSource _dataSource;
  set dataSource(ChatDataSource value) {
    if (identical(_dataSource, value)) return;
    if (attached) {
      _dataSource
        ..removeDataListener(_onDataChanged)
        ..removeBoundaryListener(_onBoundaryChanged)
        ..removeMutationListener(_onMutation);
    }
    // Don't cancel the OLD source's in-flight fetch — the consumer may be
    // sharing it with another viewport (split-pane chat, brief route-
    // transition coexistence). The old source's results landing into its
    // own chunks is harmless; we just stop listening. The consumer owns the
    // source's lifecycle and calls `dispose()` when truly done.
    _dataSource = value;
    // Reset state that was implicitly scoped to the previous source:
    //   * follow-tail snapshot — the old `newest > _lastSeenNewestId` test
    //     would otherwise compare ids across unrelated conversations and
    //     auto-pin (or fail to auto-pin) on first layout of the new source.
    //   * floating-header bucket / date — belongs to the old data; the new
    //     source has a different grouping.
    //   * laid-out chunk range — the next layout publishes fresh values.
    _wasAtTailLastLayout = false;
    _lastSeenNewestId = null;
    _lastNewestLaidOutId = null;
    _lastNewestLaidOutHeight = null;
    _lastLaidOutBottomPad = null;
    _bottomPadCompensationBase = null;
    _userPreemptedTailSettle = false;
    _floatingHeaderController.resetOnDataSourceChange();
    _chunkFetchScheduler.resetLayoutRange();
    if (attached) {
      _dataSource
        ..addDataListener(_onDataChanged)
        ..addBoundaryListener(_onBoundaryChanged)
        ..addMutationListener(_onMutation);
      _publishBoundaries();
    }
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  ChatScrollController _controller;
  set controller(ChatScrollController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      // Cancel a mid-flight fling too — its next tick would apply physics
      // fling delta to the NEW controller's anchor, continuing motion across
      // an unrelated controller swap.
      _cancelFling();
      _cancelAnimate(fadeHighlight: false);
      _cancelOverscroll();
      // Hard-clear leftover wash and the old controller's attention slot.
      // Swap is teardown of that navigator, not a same-controller rebuild —
      // keeping the slot would late-arm if the old controller is rebound.
      _clearHighlight();
      _controller.dropHighlightRequest();
      // Mid-drag controller swap: the new controller would otherwise see
      // `_dragInProgress=true` with no matching `ChatUserDragStart`, and
      // the next layout's `_clampBoundaries` would stay suspended.
      _dragInProgress = false;
      _pendingScrollDelta = 0.0;
      _userPreemptedTailSettle = false;
      if (_drag != null) {
        _drag!.dispose();
        _drag = _buildDragRecognizer();
      }
      _controller
        ..removeJumpListener(_onJump)
        ..removeScrollByListener(_onScrollBy)
        ..animator = null
        ..visibleRange = null
        ..centerBand = null
        ..isAtTail = false;
    }
    _controller = value;
    if (attached) {
      _controller
        ..addJumpListener(_onJump)
        ..addScrollByListener(_onScrollBy)
        ..animator = _animator;
    }
    markNeedsLayout();
  }

  ChatSelectionController? _selectionController;
  set selectionController(ChatSelectionController? value) {
    if (identical(_selectionController, value)) return;
    _selectionController = value;
    _selectionPointer?.selection = value;
  }

  ChatMessageMenuRequestCallback? _onIdleMessageTap;
  set onIdleMessageTap(ChatMessageMenuRequestCallback? value) {
    if (identical(_onIdleMessageTap, value)) return;
    _onIdleMessageTap = value;
    _selectionPointer?.onIdleMessageTap = value == null
        ? null
        : _dispatchIdleMessageTap;
  }

  ChatMessageMenuRequestCallback? _onSecondaryMessageTap;
  set onSecondaryMessageTap(ChatMessageMenuRequestCallback? value) {
    if (identical(_onSecondaryMessageTap, value)) return;
    _onSecondaryMessageTap = value;
    _selectionPointer?.onSecondaryMessageTap = value == null
        ? null
        : _dispatchSecondaryMessageTap;
  }

  /// See [ChatScrollView.isSelfMessage].
  bool Function(IChatMessage message)? _isSelfMessage;
  set isSelfMessage(bool Function(IChatMessage message)? value) {
    if (identical(_isSelfMessage, value)) return;
    _isSelfMessage = value;
  }

  /// Fling and edge-effect pairing for user-driven motion. See
  /// [ChatScrollView.physics].
  ///
  /// An equal value is a no-op. An unequal value cancels a fling in flight
  /// (emitting [ChatFlingEnd]), drops the edge effect to rest, and replaces
  /// the runtime; a drag in progress continues on the new pair.
  ChatScrollPhysics get physics => _motion.physics;
  set physics(ChatScrollPhysics value) {
    if (_motion.physics == value) return;
    _cancelFling();
    _cancelOverscroll();
    _motion = ChatScrollMotion(value);
    if (hasSize) _resolveRowChromeFrame();
    markNeedsPaint();
  }

  double _cacheExtent;
  set cacheExtent(double value) {
    if (_cacheExtent == value) return;
    _cacheExtent = value;
    markNeedsLayout();
  }

  /// Extra pixels beyond [cacheExtent] that are still built — off-screen and
  /// paint-culled, but their elements (and any `State`) survive. Distance-based
  /// only; unrelated to the `KeepAlive` widget.
  double _extraBuildExtent;
  set extraBuildExtent(double value) {
    if (_extraBuildExtent == value) return;
    _extraBuildExtent = value;
    markNeedsLayout();
  }

  /// Whether the scroll [Ticker] is allowed to tick. Driven by `TickerMode`,
  /// so a viewport on an inactive route does not animate a fling off-screen.
  bool _ticking;
  set ticking(bool value) {
    if (_ticking == value) return;
    _ticking = value;
    _ticker?.muted = !value;
    _activity?.muted = !value;
    _rowChromeTransitions?.muted = !value;
    if (!value) _cancelFling();
  }

  /// Whether to prefer pinning the *newest* message to the bottom edge when
  /// the conversation is short enough to fit in the viewport (`reverse:
  /// true`, chat-style). The default `false` is list-style: short content
  /// stacks at the top.
  bool _reverse;
  set reverse(bool value) {
    if (_reverse == value) return;
    _reverse = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  /// Empty space reserved after the newest message — compensation for bottom
  /// chrome stacked over the viewport (the composer, attachment previews,
  /// status strips). Reactive: when its value changes the viewport relayouts
  /// so the newest message keeps clearing whatever sits on top of it.
  ValueListenable<double>? _bottomPadding;
  set bottomPadding(ValueListenable<double>? value) {
    if (identical(_bottomPadding, value)) return;
    final oldValue = _bottomPad;
    final newValue = value?.value ?? 0.0;
    if (attached) _bottomPadding?.removeListener(_onBottomPaddingChanged);
    _bottomPadding = value;
    if (attached) _bottomPadding?.addListener(_onBottomPaddingChanged);
    // Swapping the listenable is itself a value change when the new current
    // differs from the old one — compensate on the next layout, the same as
    // `_onBottomPaddingChanged` would have done.
    if (oldValue != newValue) {
      _bottomPaddingDirty = true;
      _bottomPadCompensationBase ??= oldValue;
    }
    markNeedsLayout();
  }

  double get _bottomPad => _bottomPadding?.value ?? 0.0;

  /// Set when [bottomPadding] changed; consumed by the next [performLayout]
  /// to shift the anchor by the inset delta (composer / keyboard follow).
  bool _bottomPaddingDirty = false;

  /// [bottomPadding] value applied on the previous layout — seeds on first
  /// layout without scrolling so an initial inset does not jump content.
  double? _lastLaidOutBottomPad;

  /// Pre-change bottom inset captured when [bottomPadding] starts changing.
  /// Survives a concurrent [dataSource] swap in the same `updateRenderObject`
  /// cascade that clears [_lastLaidOutBottomPad].
  double? _bottomPadCompensationBase;

  /// One-shot: a programmatic jump/animate targeted the known tail — force
  /// `pinNewest` with `repinBottom` on the next layout even when
  /// `_wasAtTailLastLayout` is still false (initial open, return-to-tail).
  bool _pinTailOnJump = false;

  /// While true, keep forcing tail repin on each layout until
  /// [anchorMessageId] sits at [newestKnownId] and [_computeIsAtTail] is
  /// true — covers lazy fetch (shimmer → real height) and composer inset
  /// settling after a pre-mount `jumpTo`.
  bool _pendingTailPinUntilSettled = false;

  /// Set when the user takes scroll control (drag) while attach/jump tail
  /// settle is pending — blocks [pinNewest] from yanking back until an
  /// explicit tail navigation (`jumpTo` / `animateTo` newest) clears it.
  bool _userPreemptedTailSettle = false;

  /// `isAtTail` snapshot taken at the end of the previous layout. Combined
  /// with [_lastSeenNewestId] this drives the follow-tail behavior: when the
  /// viewport was at the tail in the previous layout and the newest id has
  /// since advanced, the next layout repins the (now-larger) newest message
  /// to the bottom edge — auto-scroll the chat to the new message.
  bool _wasAtTailLastLayout = false;
  int? _lastSeenNewestId;

  /// While self-insert [animateTo] owns the follow, skip instant
  /// `tailAdvanced` [repinBottom] so close-path can scroll instead of teleport.
  bool _deferTailAdvancedRepin = false;

  /// Bumps when a new self-insert follow starts — stale `whenComplete` no-ops.
  int _selfInsertFollowGen = 0;

  /// Newest row height from the previous layout — detects same-id growth
  /// (edit / content resize) so [repinBottom] can pull up without treating
  /// every user scroll-away as a forced tail pin.
  int? _lastNewestLaidOutId;
  double? _lastNewestLaidOutHeight;

  /// Empty space reserved at the *top* of the viewport — compensation for top
  /// chrome (an app bar). The floating day header rests just below it.
  ///
  /// Not compensated like the bottom inset: a change moves the scroll band's
  /// top edge and leaves on-screen rows in place, except that a held
  /// navigation placement is re-applied against the new edge on the next
  /// layout ([_lastLaidOutTopPad]).
  ValueListenable<double>? _topPadding;
  set topPadding(ValueListenable<double>? value) {
    if (identical(_topPadding, value)) return;
    if (attached) _topPadding?.removeListener(_onTopPaddingChanged);
    _topPadding = value;
    if (attached) _topPadding?.addListener(_onTopPaddingChanged);
    markNeedsLayout();
  }

  double get _topPad => _topPadding?.value ?? 0.0;

  /// Groups messages into sections for the date separators / floating header.
  /// `null` turns the feature off entirely.
  Object Function(IChatMessage)? _groupBy;
  set groupBy(Object Function(IChatMessage)? value) {
    // `==` instead of `identical`: an instance-method tear-off
    // (`widget.someMethod`) is not necessarily identical across accesses but
    // *is* equal — so `identical` would force a relayout every parent rebuild
    // while `==` correctly recognises the unchanged callback.
    if (_groupBy == value) return;
    _groupBy = value;
    markNeedsLayout();
  }

  /// Day header policy. See [ChatScrollView.dayHeaderDelegate].
  ChatDayHeaderDelegate _dayHeaderDelegate;
  set dayHeaderDelegate(ChatDayHeaderDelegate value) {
    if (_dayHeaderDelegate == value) return;
    _dayHeaderDelegate = value;
    markNeedsLayout();
  }

  /// Scroll-activity clock timing; `null` keeps activity at `1`. See
  /// [ChatScrollView.scrollActivityTiming].
  ChatScrollActivityTiming? _scrollActivityTiming;
  set scrollActivityTiming(ChatScrollActivityTiming? value) {
    if (_scrollActivityTiming == value) return;
    _scrollActivityTiming = value;
    if (!attached) return;
    if (value == null) {
      _activity?.dispose();
      _activity = null;
    } else if (_activity case final activity?) {
      activity.timing = value;
    } else {
      _activity = _createActivityClock(value);
    }
    markNeedsLayout();
  }

  /// Live while attached with a non-null [_scrollActivityTiming].
  ChatScrollActivityClock? _activity;

  /// A clock that starts idle: the list opens with idle-hidden chrome hidden.
  ChatScrollActivityClock _createActivityClock(
    ChatScrollActivityTiming timing,
  ) =>
      ChatScrollActivityClock(timing: timing, onChanged: _onActivityChanged)
        ..muted = !_ticking;

  void _onActivityChanged() {
    if (!hasSize) return;
    _resolveRowChromeFrame();
    markNeedsPaint();
  }

  /// Releases the activity hold once nothing moves the list — a finger held
  /// still mid-drag keeps it.
  void _releaseActivityIfSettled() {
    final activity = _activity;
    if (activity == null || !activity.isHolding) return;
    if (_dragInProgress ||
        _motion.fling.isFlinging ||
        _animator.isAnimating ||
        _pendingScrollDelta != 0.0 ||
        _spanAutoScrollOccupying) {
      return;
    }
    activity.release();
  }

  /// Host policy for [MessageRunLayout]. See [ChatScrollView.senderRunLayout].
  ///
  /// When the policy is also a [Listenable], the viewport listens and
  /// [markNeedsLayout]s on notify so live [MessageRunLayout.extras] inputs
  /// re-resolve without swapping the policy instance or calling
  /// [ChatDataSource.notifyDataChanged].
  ChatSenderRunLayout _senderRunLayout;
  set senderRunLayout(ChatSenderRunLayout value) {
    if (_senderRunLayout == value) return;
    if (attached) _detachSenderRunLayoutListener();
    _senderRunLayout = value;
    if (attached) _attachSenderRunLayoutListener();
    markNeedsLayout();
  }

  void _attachSenderRunLayoutListener() {
    final policy = _senderRunLayout;
    if (policy case final Listenable listenable) {
      listenable.addListener(_onSenderRunLayoutChanged);
    }
  }

  void _detachSenderRunLayoutListener() {
    final policy = _senderRunLayout;
    if (policy case final Listenable listenable) {
      listenable.removeListener(_onSenderRunLayoutChanged);
    }
  }

  void _onSenderRunLayoutChanged() => markNeedsLayout();

  /// Unread boundary id. See [ChatScrollView.unreadBoundary].
  ///
  /// Listened to while attached. The element reads the value when it builds
  /// a row and keeps a per-id "built with unread separator" bit in its skip
  /// cache, so a changed value re-inflates only the rows whose bit flips —
  /// the old and the new boundary row. This side owns the geometry: a value
  /// change is a row chrome change that the next layout turns into
  /// transitions ([_startUnreadSeparatorTransitions]), and every layout that
  /// moves a transition frame holds the reading position across it
  /// ([_holdRowChromeReference]) — unless a changed row is the target of the
  /// armed navigation placement, which is then re-applied instead
  /// ([_isNavigationTargetChromeChange]).
  ///
  /// Swapping in a listenable with a different current value is a value
  /// change; swapping in one with the same value only moves the subscription.
  ValueListenable<int?>? _unreadBoundary;
  set unreadBoundary(ValueListenable<int?>? value) {
    if (identical(_unreadBoundary, value)) return;
    final changed = _unreadBoundary?.value != value?.value;
    if (attached) _unreadBoundary?.removeListener(_onUnreadBoundaryChanged);
    _unreadBoundary = value;
    if (attached) _unreadBoundary?.addListener(_onUnreadBoundaryChanged);
    if (changed) _onUnreadBoundaryChanged();
  }

  void _onUnreadBoundaryChanged() {
    _rowChromeChanged = true;
    markNeedsLayout();
  }

  /// Enter / exit legs of the unread separator, one per boundary row. Live
  /// while attached; muted with [_ticking].
  ChatRowChromeTransitionClock? _rowChromeTransitions;

  /// A moved transition frame is a row chrome change: the next layout hands
  /// the frame to its row and holds the reading position across it.
  void _onRowChromeTransitionChanged() {
    _rowChromeChanged = true;
    markNeedsLayout();
  }

  /// Whether row [id]'s unread separator is still exiting after the boundary
  /// left it. The element keeps building the separator on that row until
  /// the exit ends, so the row rebuilds once, after the separator is gone.
  bool isUnreadSeparatorExiting(int id) =>
      _rowChromeTransitions?.isExiting(id) ?? false;

  /// Reading direction for paint mirroring (scrollbar position, future RTL
  /// chrome). Hit-tests against the scrollbar's trailing-edge strip read
  /// this too.
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsPaint();
  }

  /// Whether the host widget exposes a chunk-error builder — drives the
  /// fan-out's "skip ids in errored chunks, build one error tile instead"
  /// branch. The builder itself lives on the widget; the element looks it
  /// up when [ChatChildManager.buildChunkError] is called.
  bool _hasErrorBuilder;
  set hasErrorBuilder(bool value) {
    if (_hasErrorBuilder == value) return;
    _hasErrorBuilder = value;
    markNeedsLayout();
  }

  /// Whether the host exposes an empty-state builder — drives the empty-mode
  /// overlay path in [performLayout].
  bool _hasEmptyBuilder;
  set hasEmptyBuilder(bool value) {
    if (_hasEmptyBuilder == value) return;
    _hasEmptyBuilder = value;
    markNeedsLayout();
  }

  /// Whether the host exposes an initial-loading builder — drives the
  /// loading-mode overlay path in [performLayout].
  bool _hasLoadingBuilder;
  set hasLoadingBuilder(bool value) {
    if (_hasLoadingBuilder == value) return;
    _hasLoadingBuilder = value;
    markNeedsLayout();
  }

  // --- Layout state ----------------------------------------------------------

  int _accessTick = 0;

  /// Scroll velocity EMA and last ticker timestamp — used to rebase close-path
  /// animation targets after [performLayout] when geometry changes mid-flight.
  Duration? _lastTickElapsed;

  /// Exponential moving average of the per-frame scroll delta (px/frame,
  /// signed). Positive = anchor moving down = revealing older messages.
  /// Drives the directional build-ahead lead.
  double _scrollVelocity = 0;
  static const double _leadFrames = 4;

  /// Set when a row chrome input outside the data source changed (the
  /// unread boundary, or a separator transition frame); consumed by the next
  /// [performLayout], which holds the reading position across the resulting
  /// row height change.
  bool _rowChromeChanged = false;

  /// Unread boundary value as of the latest [performLayout]. With the
  /// current value it names the rows whose unread separator flips on a
  /// [_rowChromeChanged] pass — the old and the new boundary row.
  int? _laidOutUnreadBoundary;

  /// Top inset the latest normal-mode [performLayout] used; `null` before
  /// the first. A difference on the next pass re-applies a held navigation
  /// placement — the top inset itself is not compensated.
  double? _lastLaidOutTopPad;

  // --- Ticker / scroll physics ----------------------------------------------

  Ticker? _ticker;
  double _pendingScrollDelta = 0;

  /// Chunk fetch poll, jump-fetch dispatch, and LRU eviction are owned by
  /// [_chunkFetchScheduler]; the render object publishes the laid-out chunk
  /// range at the end of `performLayout`.
  late final ChatChunkFetchScheduler _chunkFetchScheduler =
      ChatChunkFetchScheduler(
        dataSource: _dataSource,
        requestRange: _dataSource.requestChunks,
        anchorChunkIndex: () =>
            ChatScrollChunk.chunkOf(_controller.anchorMessageId),
      );

  /// Floating day-header state, scan, and divider fade math —
  /// [ChatFloatingHeaderController]. The render object owns the header
  /// [RenderBox] and calls `buildFloatingHeader` during layout.
  final ChatFloatingHeaderController _floatingHeaderController =
      ChatFloatingHeaderController();

  /// Runtime of [physics]: the fling runner and the edge-effect state.
  /// Replaced whole on an unequal [physics] swap.
  ChatScrollMotion _motion;

  VerticalDragGestureRecognizer? _drag;

  ChatSelectionPointer? _selectionPointer;

  /// Pointer that caught an in-flight fling or edge spring; tap and
  /// long-press are suppressed until this pointer lifts.
  int? _flingCancelPointer;

  // --- Edge effect -----------------------------------------------------------
  //
  // Layout is always clamped. Drag motion first goes to the edge effect's
  // claim; the remainder a reached pin cannot consume feeds its pull, and a
  // fling that reaches a pin hands it the leftover velocity. The effect is
  // painted on messages only ([_edgeTransform]); hit-testing, the reported
  // paint transform, and row chrome paint tops use the same matrix. Idle
  // stacking still uses the short-content pin.

  /// `true` from `_onDragStart` until `_onDragEnd`.
  bool _dragInProgress = false;

  // --- animateTo + highlight ([ChatAnimator]) ------------------------------

  /// Scroll/highlight animation state — [ChatAnimator].
  late final ChatAnimator _animator;

  /// Outgoing message ids retained during far-path stitch (GC pin + frozen Y).
  final Set<int> _stitchOutgoingIds = <int>{};

  /// Pre-jump viewport tops for [_stitchOutgoingIds].
  final Map<int, double> _stitchFrozenTops = <int, double>{};

  /// Pre-jump heights for [_stitchOutgoingIds] — measure must not depend on
  /// live children (fan-out after jump may have dropped them for a frame).
  final Map<int, double> _stitchFrozenHeights = <int, double>{};

  /// Dedupes `stitch.gc` logs across layout spam during one stitch.
  String? _stitchGcLogSig;

  /// Anchor id before stitch jump — direction heuristic.
  int? _stitchAnchorIdBeforeJump;

  /// Post-animate highlight duration — forwarded to [ChatAnimator].
  Duration get highlightDuration => _animator.highlightDuration;
  set highlightDuration(Duration value) => _animator.highlightDuration = value;

  /// Post-animate highlight colour — forwarded to [ChatAnimator].
  Color get highlightColor => _animator.highlightColor;
  set highlightColor(Color value) => _animator.highlightColor = value;

  /// Snapshot visible rows before stitch `jumpTo` (outgoing strip for
  /// dual-translate + GC presence pin).
  void _prepareStitchCapture(int targetId) {
    _stitchOutgoingIds.clear();
    _stitchFrozenTops.clear();
    _stitchFrozenHeights.clear();
    _stitchGcLogSig = null;
    _stitchAnchorIdBeforeJump = _controller.anchorMessageId;
    // Direction is known at capture — used for paint even before measure.
    _stitchTowardNewer = targetId > (_stitchAnchorIdBeforeJump ?? targetId);
    if (!hasSize) {
      fine(.animate, 'stitch.capture', {
        'target': targetId,
        'hasSize': false,
        'anchorBefore': _stitchAnchorIdBeforeJump,
        'towardNewer': _stitchTowardNewer,
      });
      return;
    }
    final viewportHeight = size.height;
    for (final entry in _children.entries) {
      final child = entry.value;
      final top = _parentData(child).offset;
      final height = child.size.height;
      final bottom = top + height;
      if (bottom > 0 && top < viewportHeight) {
        _stitchOutgoingIds.add(entry.key);
        _stitchFrozenTops[entry.key] = top;
        _stitchFrozenHeights[entry.key] = height;
      }
    }
    fine(.animate, 'stitch.capture', {
      'target': targetId,
      'anchorBefore': _stitchAnchorIdBeforeJump,
      'towardNewer': _stitchTowardNewer,
      'vh': LogFormat.f(viewportHeight),
      'outgoingN': _stitchOutgoingIds.length,
      'outgoingIds': LogFormat.ids(_stitchOutgoingIds),
      'stripH': LogFormat.f(_stitchOutgoingStripBottom()),
    });
  }

  /// Bottom of the captured outgoing strip (max frozen top+height), or 0.
  double _stitchOutgoingStripBottom() {
    var bottom = 0.0;
    for (final id in _stitchOutgoingIds) {
      final top = _stitchFrozenTops[id];
      final height = _stitchFrozenHeights[id];
      if (top == null || height == null) continue;
      final bot = top + height;
      if (bot > bottom) bottom = bot;
    }
    return bottom;
  }

  /// Top of the captured outgoing strip (min frozen top), or 0 when empty.
  double _stitchOutgoingStripTop() {
    var top = double.infinity;
    for (final id in _stitchOutgoingIds) {
      final t = _stitchFrozenTops[id];
      if (t == null) continue;
      if (t < top) top = t;
    }
    return top == double.infinity ? 0.0 : top;
  }

  /// User or host cancelled mid-stitch — bake dual-translate at [snapshot.progress]
  /// into layout offsets so the viewport stays where it was painted, then refan.
  ///
  /// During [detach] (route pop while stitch is in flight) skip bake /
  /// [markNeedsLayout]: the tree is leaving, and a host [LayoutBuilder] /
  /// Overlay may still be inside `performLayout`.
  void _onStitchCancelled(StitchCancelSnapshot snapshot) {
    _chunkFetchScheduler.clearNavigationDestination();
    _pinTailOnJump = false;
    _pendingTailPinUntilSettled = false;
    if (_detaching) {
      _clearStitchCapture();
      return;
    }
    if (hasSize && snapshot.jumped && snapshot.measured) {
      _commitStitchAtProgress(snapshot);
    } else if (hasSize) {
      _renormalizeAnchor();
    }
    _clearStitchCapture();
    markNeedsLayout();
  }

  /// Normal stitch completion — bake paint dy at final progress before clearing
  /// capture so outgoing rows do not snap back into the viewport for one frame.
  void _onStitchComplete(StitchCancelSnapshot snapshot) {
    if (_detaching) {
      _clearStitchCapture();
      return;
    }
    if (hasSize && snapshot.jumped && snapshot.measured) {
      _commitStitchAtProgress(snapshot);
    }
    _clearStitchCapture();
    markNeedsLayout();
  }

  /// Apply stitch paint translation to layout offsets at cancel/complete time.
  void _commitStitchAtProgress(StitchCancelSnapshot snapshot) {
    final hasLiveOutgoing = _stitchOutgoingIds.any(_children.containsKey);
    if (!hasLiveOutgoing) {
      _renormalizeAnchor();
      return;
    }
    final travel = math.max<double>(snapshot.scrollLength, 1);
    final t = snapshot.progress;
    final towardNewer = snapshot.towardNewer;
    for (final entry in _children.entries) {
      final dy = _stitchPaintDyFor(
        id: entry.key,
        towardNewer: towardNewer,
        travel: travel,
        progress: t,
        hasLiveOutgoing: hasLiveOutgoing,
      );
      if (dy == 0) continue;
      final pd = _parentData(entry.value);
      _setOffset(entry.value, pd.offset + dy);
    }
    final fromId = _controller.anchorMessageId;
    final fromY = _controller.anchorPixelOffset;
    _syncAnchorOffsetAfterStitchCommit();
    _renormalizeAnchor();
    _fetchAnchorEvent('stitch.commit', {
      ..._fetchAnchorSnapshot(),
      'target': snapshot.targetId,
      'progress': LogFormat.ratio(snapshot.progress),
      'scrollLen': LogFormat.f(travel),
      'fromId': fromId,
      'fromY': LogFormat.f(fromY),
      'toId': _controller.anchorMessageId,
      'toY': LogFormat.f(_controller.anchorPixelOffset),
    });
  }

  /// Keep [ChatScrollController.anchorPixelOffset] aligned with the anchor row
  /// after commit bake so the next full layout does not refan from stale Y.
  void _syncAnchorOffsetAfterStitchCommit() {
    final resolved = _resolveAnchorBox();
    if (resolved == null) return;
    final top = _parentData(resolved.box).offset;
    if ((_controller.anchorPixelOffset - top).abs() <= 0.5) return;
    _controller.reassignAnchor(_controller.anchorMessageId, top);
  }

  double _stitchPaintDyFor({
    required int id,
    required bool towardNewer,
    required double travel,
    required double progress,
    required bool hasLiveOutgoing,
  }) {
    if (!hasLiveOutgoing) return 0;
    if (_stitchOutgoingIds.contains(id)) {
      return towardNewer ? -travel * progress : travel * progress;
    }
    return towardNewer ? travel * (1 - progress) : -travel * (1 - progress);
  }

  void _clearStitchCapture() {
    _stitchOutgoingIds.clear();
    _stitchFrozenTops.clear();
    _stitchFrozenHeights.clear();
    _stitchGcLogSig = null;
    _stitchAnchorIdBeforeJump = null;
    _stitchTowardNewer = true;
  }

  /// Toward-newer heuristic captured before jump (also used pre-measure paint).
  bool _stitchTowardNewer = true;

  /// Layout GC-pinned outgoing rows at their frozen tops (not in fan-out).
  void _layoutStitchOutgoingPinned(BoxConstraints cc) {
    if (!_animator.farAnimateActive || _stitchOutgoingIds.isEmpty) return;
    for (final id in _stitchOutgoingIds) {
      final child = _children[id];
      if (child == null) continue;
      child.layout(cc, parentUsesSize: true);
      final frozen = _stitchFrozenTops[id];
      if (frozen != null) {
        _parentData(child).offset = frozen;
      }
    }
  }

  /// After stitch jump layout: freeze outgoing offsets and measure travel.
  void _refreezeStitchOutgoing() {
    if (!_animator.farAnimateActive || _stitchOutgoingIds.isEmpty) return;
    for (final id in _stitchOutgoingIds) {
      final child = _children[id];
      final frozen = _stitchFrozenTops[id];
      if (child == null || frozen == null) continue;
      _parentData(child).offset = frozen;
    }
  }

  void _finishStitchMeasureIfNeeded() {
    if (!_animator.farAnimateActive ||
        !_animator.farAnimateJumped ||
        _animator.stitchMeasured) {
      return;
    }
    if (!hasSize) return;

    _refreezeStitchOutgoing();

    // Prefer capture-time strip extents — live children may be gone after the
    // jump fan-out even when GC-pinned for a later frame.
    final oldT = _stitchOutgoingStripTop();
    final oldH = _stitchOutgoingStripBottom();
    var liveOutgoing = 0;
    for (final id in _stitchOutgoingIds) {
      if (_children.containsKey(id)) liveOutgoing++;
    }

    var incomingTop = 0.0;
    var incomingBottom = 0.0;
    var hasIncoming = false;
    for (final entry in _children.entries) {
      if (_stitchOutgoingIds.contains(entry.key)) continue;
      final top = _parentData(entry.value).offset;
      final bot = top + entry.value.size.height;
      if (!hasIncoming) {
        incomingTop = top;
        incomingBottom = bot;
        hasIncoming = true;
      } else {
        if (top < incomingTop) incomingTop = top;
        if (bot > incomingBottom) incomingBottom = bot;
      }
    }

    final towardNewer = _stitchTowardNewer;
    final viewportHeight = size.height;
    final finalHeight = towardNewer ? oldH : viewportHeight - oldT;
    // Full-strip travel: outgoing strip + incoming extents (including
    // off-screen tall parts). Duration scales with travel separately.
    final scrollLength = hasIncoming
        ? finalHeight +
              (towardNewer ? -incomingTop : incomingBottom - viewportHeight)
        : math.max(finalHeight, viewportHeight);
    final travel = math.max<double>(scrollLength.abs(), 1);
    fine(.animate, 'stitch.measureGeom', {
      'target': _animator.animateTargetId,
      'towardNewer': towardNewer,
      'vh': LogFormat.f(viewportHeight),
      'oldT': LogFormat.f(oldT),
      'oldH': LogFormat.f(oldH),
      'finalH': LogFormat.f(finalHeight),
      'hasIncoming': hasIncoming,
      'inTop': hasIncoming ? LogFormat.f(incomingTop) : null,
      'inBot': hasIncoming ? LogFormat.f(incomingBottom) : null,
      'scrollLen': LogFormat.f(travel),
      'outgoingN': _stitchOutgoingIds.length,
      'outgoingLive': liveOutgoing,
      'childN': _children.length,
    });

    _animator.applyStitchMeasure(
      scrollLength: travel,
      towardNewer: towardNewer,
      viewportHeight: viewportHeight,
      elapsed: _lastTickElapsed,
    );
  }

  /// Paint-time Y delta for stitch dual-translate.
  ///
  /// While jumped but not yet measured, still offset incoming fully off-screen
  /// (viewport-height provisional) so no frame shows destination at rest —
  /// translation starts from the first post-layout paint.
  double _stitchPaintDy(int id) {
    if (!_animator.farAnimateActive || !_animator.farAnimateJumped) {
      return 0;
    }
    // Without a live outgoing strip, dual-translate would only shove incoming
    // fully off-screen → blank viewport for the whole stitch.
    final hasLiveOutgoing = _stitchOutgoingIds.any(_children.containsKey);
    if (!hasLiveOutgoing) return 0;

    final towardNewer = _animator.stitchMeasured
        ? _animator.stitchTowardNewer
        : _stitchTowardNewer;
    final travel = _animator.stitchMeasured
        ? _animator.stitchScrollLength
        : (hasSize ? size.height : 600.0);
    final t = _animator.stitchMeasured ? _animator.stitchProgress : 0.0;
    if (_stitchOutgoingIds.contains(id)) {
      return towardNewer ? -travel * t : travel * t;
    }
    return towardNewer ? travel * (1 - t) : -travel * (1 - t);
  }

  void _onAnimateSettled(int targetId) {
    _markPinTailOnJumpIfNeeded(_clampJumpTarget(targetId));

    // Close-path animation finished — the animator owned offset each tick.
    // Try one alignment snap; if the target row is still a skeleton, leave
    // the placement pending so [performLayout] applies it once the real
    // message is built (same contract as [jumpTo]). [_applyNavigationPlacement]
    // holds once landed; do not clear here unconditionally — that dropped
    // deferred alignment and regressed post-load landing for non-zero alignment.
    if (_controller.navigationPlacement case AlignmentPlacement(
      :final alignment,
    ) when alignment != 0.0) {
      _applyNavigationPlacement();
    }

    if (_pinTailOnJump) markNeedsLayout();
  }

  // --- Fetch poll ------------------------------------------------------------

  // --- Scrollbar -------------------------------------------------------------
  //
  // Thumb progress maps the anchor over the full known id extent (oldest…newest).
  // Track paint uses a uniform colour from [scrollbarTheme]; loaded/unloaded
  // honesty is in the viewport, not per-range track segments. Paint does not
  // read [ChatDataSource.chunks].

  final ChatScrollbar _scrollbar = ChatScrollbar();

  ChatScrollbarThemeData _scrollbarTheme;

  /// Resolved scrollbar colours pushed from [ChatScrollElement] / [ChatScrollView].
  ChatScrollbarThemeData get scrollbarTheme => _scrollbarTheme;

  /// Updates track/thumb colours; triggers repaint only (no layout).
  set scrollbarTheme(ChatScrollbarThemeData value) {
    if (_scrollbarTheme == value) return;
    _scrollbarTheme = value;
    markNeedsPaint();
  }

  /// Retained clip layer — reused across repaints via `oldLayer`.
  final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

  /// Edge-effect transform layer — reused while the message layer is
  /// transformed.
  final LayerHandle<TransformLayer> _edgeLayer = LayerHandle<TransformLayer>();

  // --- Day separators --------------------------------------------------------

  /// The floating day header, pinned to the top — one extra child render box
  /// beyond the id-keyed messages. Built lazily during layout (like a message)
  /// by `ChatScrollElement`. `null` when day separators are off, or no day is
  /// known yet.
  RenderBox? _floatingHeader;
  set floatingHeader(RenderBox? value) {
    if (identical(_floatingHeader, value)) return;
    if (_floatingHeader != null) dropChild(_floatingHeader!);
    _floatingHeader = value;
    if (value != null) adoptChild(value);
  }

  // --- Full-viewport overlay (loading / empty) ------------------------------

  /// The single full-viewport overlay child (loading skeleton or empty state)
  /// or `null` when the viewport is in normal fan-out mode.
  RenderBox? _overlay;

  /// The kind of overlay currently built (matches [_overlay]'s identity); used
  /// to skip a redundant rebuild when the mode doesn't change.
  ChatOverlayKind _overlayKind = ChatOverlayKind.none;

  set overlay(RenderBox? value) {
    if (identical(_overlay, value)) return;
    if (_overlay != null) dropChild(_overlay!);
    _overlay = value;
    if (value != null) adoptChild(value);
  }

  /// Force the floating header to rebuild on the next layout — used when its
  /// builder reference changes, which the day-bucket gate cannot detect.
  void invalidateFloatingHeader() {
    _floatingHeaderController.invalidate();
    markNeedsLayout();
  }

  // --- Scroll semantics state -----------------------------------------------

  bool _canRevealOlder = false;
  bool _canRevealNewer = false;

  // --- Debug instrumentation (zero-cost in release via assert) --------------

  final Stopwatch _debugSw = Stopwatch();

  /// Wall-clock duration of the most recent `performLayout` (debug builds only).
  Duration debugLastLayoutDuration = Duration.zero;

  /// Wall-clock duration of the most recent `paint` (debug builds only).
  Duration debugLastPaintDuration = Duration.zero;

  /// Monotonic frame counter incremented on each layout pass.
  int debugLayoutFrameId = 0;

  /// Monotonic frame counter incremented on each paint pass.
  int debugPaintFrameId = 0;

  /// Count of message children currently in the sparse child map.
  int get debugChildCount => _children.length;

  /// Count of chunk-error overlay children currently built.
  int get debugChunkErrorCount => _chunkErrors.length;

  /// Number of pagination chunks tracked by the data source.
  int get debugChunkCount => _dataSource.chunks.length;

  /// Lowest chunk index included in the last layout fan-out.
  int get debugLayoutMinChunk => _chunkFetchScheduler.layoutMinChunk;

  /// Highest chunk index included in the last layout fan-out.
  int get debugLayoutMaxChunk => _chunkFetchScheduler.layoutMaxChunk;

  /// Smallest message id with a built child, or `null` when empty.
  int? get debugFirstId => _children.isEmpty ? null : _children.firstKey();

  /// Largest message id with a built child, or `null` when empty.
  int? get debugLastId => _children.isEmpty ? null : _children.lastKey();

  /// Paint stretch in `[-1, 1]`. Zero at rest and under any edge effect
  /// other than stretch.
  @visibleForTesting
  double get debugStretchOverscroll => switch (_motion.edge) {
    final ChatStretchOverscroll stretch => stretch.overscroll,
    _ => 0,
  };

  /// Whether a floating header child is currently attached (may still be
  /// hidden by [debugFloatingHeaderVisible]).
  @visibleForTesting
  bool get debugHasFloatingHeader => _floatingHeader != null;

  /// Whether the floating header would be painted this frame (suppressed above
  /// the oldest boundary during short content).
  @visibleForTesting
  bool get debugFloatingHeaderVisible =>
      _floatingHeader != null && _shouldShowFloatingHeader();

  /// Viewport-local Y of the floating header's top edge, if built.
  @visibleForTesting
  double? get debugFloatingHeaderOffset =>
      _floatingHeader == null ? null : _parentData(_floatingHeader!).offset;

  /// Calendar date shown in the floating header, if any.
  DateTime? get debugHeaderDate => _floatingHeaderController.headerDate;

  /// Debug-only: group bucket the floating header was last built for.
  Object? get debugHeaderBucket => _floatingHeaderController.headerBucket;

  /// Message id currently receiving the post-navigation highlight tint.
  int? get debugHighlightTargetId => _animator.highlightTargetId;

  /// Message id waiting until it is a loaded Message with a built child
  /// before the highlight arms.
  int? get debugPendingHighlightTargetId => _animator.pendingHighlightTargetId;

  /// Highlight animation progress in `0..1` for [debugHighlightTargetId].
  /// Solid hold stays at `1.0`; fade declines toward `0`.
  double get debugHighlightFactor => _animator.highlightFactor;

  /// Current highlight phase for tests (`idle` / `solid` / `fading`).
  ChatHighlightPhase get debugHighlightPhase => _animator.highlightPhase;

  /// Whether far-path stitch is in flight (post-jump dual-translate).
  bool get debugFarAnimateActive => _animator.farAnimateActive;

  /// Whether stitch has already run its teleport `jumpTo`.
  bool get debugFarAnimateJumped => _animator.farAnimateJumped;

  /// Whether any [animateTo] (close, stitch, or preferBuilt wait) is in flight.
  bool get debugIsAnimating => _animator.isAnimating;

  /// Whether close-path vs stitch is deferred under the navigation load-gate.
  bool get debugLoadGateWaiting => _animator.loadGateWaiting;

  /// Alias for [debugLoadGateWaiting].
  bool get debugPreferBuiltWaiting => debugLoadGateWaiting;

  /// Outgoing ids retained during stitch (GC pin + frozen paint Y).
  Set<int> get debugStitchOutgoingIds => Set<int>.of(_stitchOutgoingIds);

  /// Stitch progress `0..1` after measure (0 before measure / when idle).
  double get debugStitchProgress => _animator.stitchProgress;

  /// Measured stitch travel (px) after layout measure; `0` before measure.
  double get debugStitchScrollLength => _animator.stitchScrollLength;

  /// Currently built message ids (fan-out + stitch-pinned outgoing).
  Set<int> get debugBuiltMessageIds => _children.keys.toSet();

  /// Resolved opacity (0..1) of the built child [id]'s first row chrome item
  /// — its inline day separator — or `1` when the row has no chrome. `null`
  /// when [id] is not currently built.
  double? debugDividerOpacity(int id) => switch (_children[id]) {
    null => null,
    final RenderChatRowChrome row when row.chromeCount > 0 =>
      row.debugChromeEffect(0).opacity,
    _ => 1.0,
  };

  /// Opacity the floating header resolved to this frame.
  @visibleForTesting
  double get debugFloatingHeaderOpacity => _headerEffect.opacity;

  /// Current scroll activity; `1` without an activity clock.
  @visibleForTesting
  double get debugScrollActivity => _activity?.value ?? 1.0;

  /// Whether the built child [id] carries an inline day separator, or `false`
  /// when [id] is not currently built.
  bool debugStartsDay(int id) {
    final child = _children[id];
    return child != null && _parentData(child).startsDay;
  }

  void _fetchAnchorEvent(String tag, Map<String, Object?> fields) {
    fine(.anchor, tag, fields);
  }

  void _scrollbarEvent(String tag, Map<String, Object?> fields) {
    fine(.scrollbar, tag, fields);
  }

  /// Message built closest to the bottom inset — proxy for "what the user was
  /// reading" near the composer when investigating post-fetch jumps.
  ({int id, double top, double bottom, double gapToBottomEdge})?
  _bottomBandMessage() {
    if (!hasSize) return null;
    final bottomEdge = size.height - _bottomPad;
    int? bestId;
    double? bestTop;
    double? bestBottom;
    var bestGap = double.infinity;
    for (final entry in _children.entries) {
      final top = _parentData(entry.value).offset;
      final bottom = top + entry.value.size.height;
      if (bottom <= 0 || top >= bottomEdge) continue;
      final gap = (bottom - bottomEdge).abs();
      if (gap < bestGap) {
        bestGap = gap;
        bestId = entry.key;
        bestTop = top;
        bestBottom = bottom;
      }
    }
    if (bestId == null) return null;
    return (
      id: bestId,
      top: bestTop!,
      bottom: bestBottom!,
      gapToBottomEdge: bestGap,
    );
  }

  Map<String, Object?> _fetchAnchorSnapshot() {
    final anchorId = _controller.anchorMessageId;
    final anchorY = _controller.anchorPixelOffset;
    final resolved = _resolveAnchorBox();
    double? anchorTop;
    double? anchorBottom;
    double? anchorH;
    if (resolved != null) {
      anchorTop = _parentData(resolved.box).offset;
      anchorH = resolved.box.size.height;
      anchorBottom = anchorTop + anchorH;
    }
    final bottomEdge = hasSize ? size.height - _bottomPad : null;
    final band = _bottomBandMessage();
    final anchorStatus = _dataSource.statusOf(anchorId);
    return {
      'layout': _fetchAnchorLayoutFrame,
      'anchorId': anchorId,
      'anchorY': LogFormat.f(anchorY),
      'anchorFetching': anchorStatus.isFetching,
      'anchorAbsent': anchorStatus.isAbsent,
      'anchorDirty': anchorStatus.isDirty,
      'anchorLoaded': _dataSource.getMessage(anchorId) != null,
      'anchorTop': anchorTop == null ? null : LogFormat.f(anchorTop),
      'anchorBottom': anchorBottom == null ? null : LogFormat.f(anchorBottom),
      'anchorH': anchorH == null ? null : LogFormat.f(anchorH),
      'bottomEdge': bottomEdge == null ? null : LogFormat.f(bottomEdge),
      'bandId': band?.id,
      'bandTop': band == null ? null : LogFormat.f(band.top),
      'bandBottom': band == null ? null : LogFormat.f(band.bottom),
      'bandGap': band == null ? null : LogFormat.f(band.gapToBottomEdge),
      'bandFullyAboveInset':
          band != null && bottomEdge != null && band.bottom <= bottomEdge + 0.5,
      'isAtTail': hasSize ? _computeIsAtTail() : null,
      'wasAtTail': _wasAtTailLastLayout,
      'pendingTailPin': _pendingTailPinUntilSettled,
      'userPreemptedTail': _userPreemptedTailSettle,
      'drag': _dragInProgress,
      'fling': _motion.fling.isFlinging,
      'builtCount': _children.length,
    };
  }

  List<int> _fetchingChunkIndices() {
    final fetching = <int>[];
    for (final entry in _dataSource.chunks.entries) {
      if (entry.value.status.isFetching) fetching.add(entry.key);
    }
    fetching.sort();
    return fetching;
  }

  // --- RenderBox configuration ----------------------------------------------

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ChatMessageParentData) {
      child.parentData = ChatMessageParentData();
    }
  }

  ChatMessageParentData _parentData(RenderBox child) =>
      child.parentData! as ChatMessageParentData;

  // --- Child management (called by ChatScrollElement) -----------------------

  /// Adopt [child] for message [id]. Called via `insertRenderObjectChild`.
  void insertChild(RenderBox child, int id) {
    _children[id] = child;
    adoptChild(child);
    _parentData(child).id = id;
  }

  /// Drop the child for message [id]. Called via `removeRenderObjectChild`.
  void removeChild(int id) {
    final child = _children.remove(id);
    if (child == null) return;
    dropChild(child);
  }

  /// Adopt a chunk-error tile for [chunkIndex]. Kept in a separate map from
  /// message tiles so a frame that flips a chunk from errored → valid (or
  /// vice versa) can coexist a chunk-error tile and a message at the same
  /// position id without overwriting either side's render box.
  void insertChunkError(RenderBox child, int chunkIndex) {
    _chunkErrors[chunkIndex] = child;
    adoptChild(child);
    _parentData(child).id = ChatScrollChunk.firstIdOf(chunkIndex);
  }

  /// Drop the chunk-error tile for [chunkIndex].
  void removeChunkError(int chunkIndex) {
    final child = _chunkErrors.remove(chunkIndex);
    if (child == null) return;
    dropChild(child);
  }

  // --- RenderObject lifecycle -----------------------------------------------

  /// Runs [fn] inside `invokeLayoutCallback` and marks the element-side
  /// [ChatChildManager] as inside a layout callback (debug asserts).
  void _invokeChildManagerLayout(void Function() fn) {
    invokeLayoutCallback<BoxConstraints>((_) {
      final manager = childManager;
      assert(() {
        if (manager is ChatScrollElement) {
          manager.insideLayoutCallback = true;
        }
        return true;
      }());
      try {
        fn();
      } finally {
        assert(() {
          if (manager is ChatScrollElement) {
            manager.insideLayoutCallback = false;
          }
          return true;
        }());
      }
    });
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _chunkFetchScheduler.onAttach();
    for (final child in _children.values) {
      child.attach(owner);
    }
    for (final child in _chunkErrors.values) {
      child.attach(owner);
    }
    _floatingHeader?.attach(owner);
    _overlay?.attach(owner);
    _ticker = Ticker(_onTick)..muted = !_ticking;
    if (_scrollActivityTiming case final timing?) {
      _activity = _createActivityClock(timing);
    }
    _rowChromeTransitions = ChatRowChromeTransitionClock(
      onChanged: _onRowChromeTransitionChanged,
    )..muted = !_ticking;
    _dataSource
      ..addDataListener(_onDataChanged)
      ..addBoundaryListener(_onBoundaryChanged)
      ..addMutationListener(_onMutation);
    _controller
      ..addJumpListener(_onJump)
      ..addScrollByListener(_onScrollBy)
      ..animator = _animator;
    _publishBoundaries();
    _bottomPadding?.addListener(_onBottomPaddingChanged);
    _topPadding?.addListener(_onTopPaddingChanged);
    _attachSenderRunLayoutListener();
    _unreadBoundary?.addListener(_onUnreadBoundaryChanged);
    _drag = _buildDragRecognizer();
    _selectionPointer = ChatSelectionPointer(debugOwner: this)
      ..messageIdAt = _presentMessageIdAt
      ..spanHitAt = _spanHitAt
      ..spanChain = _selectSpanChain
      ..flingCancelSuppresses = () =>
          _controller.flingCancelSuppressesLongPress;
    _selectionPointer!
      ..onSpanSessionChanged = _onSpanSessionChanged
      ..selection = _selectionController
      ..onIdleMessageTap = _onIdleMessageTap == null
          ? null
          : _dispatchIdleMessageTap
      ..onSecondaryMessageTap = _onSecondaryMessageTap == null
          ? null
          : _dispatchSecondaryMessageTap;
    _displayRefreshHz = _readDisplayRefreshHz();
    _seedTailNavigationOnAttach();
  }

  /// Pre-mount `jumpTo(newest)` sets the controller anchor before this
  /// render object exists — seed tail-pin + fetch so the first layout
  /// behaves like a mounted jump.
  void _seedTailNavigationOnAttach() {
    final newest = _dataSource.newestKnownId;
    if (!_dataSource.reachedNewest || newest == null) return;
    final targetId = _clampJumpTarget(_controller.anchorMessageId);
    if (targetId != _controller.anchorMessageId) {
      _controller.reassignAnchor(targetId, 0);
    }
    if (_controller.anchorMessageId != newest) return;
    _markPinTailOnJumpIfNeeded(newest);
    _chunkFetchScheduler.queueJumpFetch();
  }

  /// Build a new drag recognizer. `onCancel` is intentionally NOT wired:
  /// `VerticalDragGestureRecognizer` fires `onCancel` whenever the gesture
  /// arena resolves against it (e.g. a child `TextButton` wins the arena on
  /// tap). In that case `onStart` never fired, so there is nothing to
  /// clean up — and a spurious `_dragInProgress=false` write here would
  /// race with overlay-mode entry. The mid-drag-cancelled-pointer case
  /// (rare in chat UIs) is handled by overlay entry, controller swap, and
  /// the per-frame `_clampBoundaries` guard.
  VerticalDragGestureRecognizer _buildDragRecognizer() =>
      VerticalDragGestureRecognizer(
          supportedDevices: const <PointerDeviceKind>{
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
            PointerDeviceKind.trackpad,
          },
        )
        ..onStart = _onDragStart
        ..onUpdate = _onDragUpdate
        ..onEnd = _onDragEnd;

  /// True while [detach] is running — stitch-cancel must not [markNeedsLayout]
  /// (Overlay / host [LayoutBuilder] may be mid-`performLayout` during route pop).
  bool _detaching = false;

  @override
  void detach() {
    _detaching = true;
    try {
      _cancelFling();
      _controller.flingCancelSuppressesLongPress = false;
      _flingCancelPointer = null;
      _ticker?.dispose();
      _ticker = null;
      _activity?.dispose();
      _activity = null;
      _rowChromeTransitions?.dispose();
      _rowChromeTransitions = null;
      _chunkFetchScheduler.onDetach();
      _pinTailOnJump = false;
      _pendingTailPinUntilSettled = false;
      _userPreemptedTailSettle = false;
      _lastLaidOutBottomPad = null;
      _bottomPadCompensationBase = null;
      // Drop our listener first — cancelFetch notifies, and a `markNeedsLayout`
      // on a detaching render object is brittle even if currently harmless.
      // We do cancel the running fetch / retry timer here: the dominant case is
      // a single viewport owning a single data source, and a viewport removal
      // should not leave a background retry storm running. Consumers that
      // share one source across viewports must reattach into a new viewport
      // synchronously, or accept the cancelled fetch (it'll be re-armed by
      // the new viewport's first layout).
      _dataSource
        ..removeDataListener(_onDataChanged)
        ..removeBoundaryListener(_onBoundaryChanged)
        ..removeMutationListener(_onMutation)
        ..cancelFetch();
      _controller
        ..removeJumpListener(_onJump)
        ..removeScrollByListener(_onScrollBy)
        ..animator = null
        // Mirror the controller-swap path: once no viewport is bound, the
        // last-published state no longer reflects anything observable.
        ..visibleRange = null
        ..centerBand = null
        ..isAtTail = false;
      _cancelAnimate(fadeHighlight: false);
      _bottomPadding?.removeListener(_onBottomPaddingChanged);
      _topPadding?.removeListener(_onTopPaddingChanged);
      _detachSenderRunLayoutListener();
      _unreadBoundary?.removeListener(_onUnreadBoundaryChanged);
      _rowChromeChanged = false;
      _drag?.dispose();
      _drag = null;
      _selectionPointer?.dispose();
      _selectionPointer = null;
      super.detach();
      // Detach children after super: `this` is now detached, so each child's
      // `attached == parent.attached` invariant holds during child.detach().
      for (final child in _children.values) {
        child.detach();
      }
      for (final child in _chunkErrors.values) {
        child.detach();
      }
      _floatingHeader?.detach();
      _overlay?.detach();
    } finally {
      _detaching = false;
    }
  }

  @override
  void redepthChildren() {
    _children.values.forEach(redepthChild);
    _chunkErrors.values.forEach(redepthChild);
    final header = _floatingHeader;
    if (header != null) redepthChild(header);
    final overlay = _overlay;
    if (overlay != null) redepthChild(overlay);
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    _children.values.forEach(visitor);
    _chunkErrors.values.forEach(visitor);
    final header = _floatingHeader;
    if (header != null) visitor(header);
    final overlay = _overlay;
    if (overlay != null) visitor(overlay);
  }

  /// Message and chunk-error children sit under [_edgeTransform]; the
  /// floating header and the overlay do not.
  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    final pd = child.parentData! as ChatMessageParentData;
    if (!identical(child, _floatingHeader) && !identical(child, _overlay)) {
      if (_edgeTransform case final edge?) transform.multiply(edge);
    }
    transform.translateByDouble(0, pd.offset, 0, 1);
  }

  // --- Typed listeners -------------------------------------------------------

  void _onDataChanged() {
    _abortSpanIfOriginAbsent();
    _fetchAnchorEvent('fetch.data', {
      ..._fetchAnchorSnapshot(),
      'fetchingChunks': LogFormat.ids(_fetchingChunkIndices(), max: 8),
    });
    markNeedsLayout();
  }

  /// Ends a live span when its gesture origin is confirmed absent so
  /// delete recovery can write the origin. Keeps the selected set.
  void _abortSpanIfOriginAbsent() {
    final pointer = _selectionPointer;
    final origin = pointer?.spanOriginId;
    if (pointer == null || origin == null) return;
    if (!_dataSource.statusOf(origin).isAbsent) return;
    pointer.abortSpan();
  }

  /// Host message widgets should lerp their reported [RenderBox] height during
  /// edit transitions so fan-out does not jump. The viewport does not yet own
  /// a parallel extent spring — see docs/architecture/11-animation-integration.
  void _onMutation(ChatMutation mutation) {
    switch (mutation) {
      case UpdateMutation() || UpdateBatchMutation():
        // Relayout is already requested via [notifyDataChanged]; this branch
        // is the reserved seam for future viewport-owned extent springs.
        markNeedsLayout();
      case InsertMutation(:final messageId):
        // [insertMessage] notifies mutations *before* writeMessageSilent —
        // defer so [getMessage] can resolve for [isSelfMessage].
        _scheduleSelfInsertFollow([messageId]);
      case InsertBatchMutation(:final ids):
        _scheduleSelfInsertFollow(ids);
      case RemoveBatchMutation(:final ids):
        _cancelAnimateIfPresencePinnedRemoved(ids);
    }
  }

  /// Explicit host delete of the animate target or stitch outgoing strip
  /// cancels navigation — no mid-flight soft-retarget / blank band.
  void _cancelAnimateIfPresencePinnedRemoved(List<int> removedIds) {
    if (!_animator.isAnimating) return;
    final pinned = _stitchPresencePinnedIds();
    if (pinned.isEmpty) return;
    for (final id in removedIds) {
      if (pinned.contains(id)) {
        _cancelAnimate();
        return;
      }
    }
  }

  /// After storage write, if any [ids] match [_isSelfMessage], jump to newest.
  void _scheduleSelfInsertFollow(List<int> ids) {
    if (_isSelfMessage == null || ids.isEmpty) return;
    scheduleMicrotask(() {
      if (!attached) return;
      final pred = _isSelfMessage;
      if (pred == null) return;
      for (final id in ids) {
        final msg = _dataSource.getMessage(id);
        if (msg != null && pred(msg)) {
          _followTailOnSelfInsert();
          return;
        }
      }
    });
  }

  /// Self-authored inserts: scroll to newest even off-tail via [animateTo]
  /// (smooth — not [jumpTo] teleport).
  ///
  /// When already at the tail, skips [animateTo] entirely — layout
  /// `tailAdvanced` [repinBottom] pins the new row (no redundant scroll /
  /// stitch flicker). Off-tail still animates with [preferBuilt].
  ///
  /// Off-tail does **not** arm [_pinTailOnJump] up front: that forces
  /// [repinBottom] before close-path can run. Pinning happens on settle via
  /// [_onAnimateSettled]. While animate is in flight, [_deferTailAdvancedRepin]
  /// blocks at-tail `tailAdvanced` instant pin.
  void _followTailOnSelfInsert() {
    final newest = _dataSource.newestKnownId;
    if (newest == null || !_dataSource.reachedNewest) return;
    _userPreemptedTailSettle = false;

    // Already following the bottom — new row is layout-owned.
    if (_wasAtTailLastLayout || _controller.isAtTail.value) {
      markNeedsLayout();
      return;
    }

    final gen = ++_selfInsertFollowGen;
    _deferTailAdvancedRepin = true;
    // Fire-and-forget from mutation/microtask. highlight:false — own send
    // should not flash highlight chrome.
    unawaited(
      _controller
          .animateTo(
            newest,
            highlight: false,
            loadPolicy: AnimateToLoadPolicy.preferBuilt,
          )
          .whenComplete(() {
            if (gen != _selfInsertFollowGen) return;
            _deferTailAdvancedRepin = false;
            // Settle path already marks pin. If this call was ignored while
            // another animate ran, ensure a later layout can still pin.
            if (!_animator.isAnimating && attached) {
              _markPinTailOnJumpIfNeeded(newest);
              markNeedsLayout();
            }
          }),
    );
  }

  void _onBottomPaddingChanged() {
    _bottomPaddingDirty = true;
    _bottomPadCompensationBase ??= _lastLaidOutBottomPad;
    // An edge effect keeps the ticker alive; tick-path pinNewest would use
    // the live pad before layout compensate and double-shift content under
    // the composer.
    if (_motion.edge.isActive) {
      _cancelOverscroll();
    }
    // Close-path: apply inset shift before the next tick can rebase against
    // the new bottomEdge and restart the travel clock (otherwise tall
    // scroll-to-bottom freezes for the keyboard animation).
    if (_animator.isAnimating && !_animator.farAnimateActive) {
      _compensateBottomPaddingChange();
    }
    markNeedsLayout();
  }

  /// Shift the anchor by the bottom-inset delta so visible content keeps the
  /// same screen position when the reserved band grows or shrinks (keyboard,
  /// composer). Runs on every inset change, not only at the tail.
  void _compensateBottomPaddingChange() {
    final current = _bottomPad;
    if (!_bottomPaddingDirty) {
      _lastLaidOutBottomPad ??= current;
      return;
    }
    _bottomPaddingDirty = false;
    final previous =
        _bottomPadCompensationBase ?? _lastLaidOutBottomPad ?? current;
    _bottomPadCompensationBase = null;
    _lastLaidOutBottomPad = current;
    final delta = previous - current;
    if (delta == 0.0) return;
    _fetchAnchorEvent('layout.bottomPadCompensate', {
      ..._fetchAnchorSnapshot(),
      'prev': LogFormat.f(previous),
      'current': LogFormat.f(current),
      'delta': LogFormat.f(delta),
    });
    _controller.applyScrollDelta(delta);
    // Keep close-path travel clock running: inset moves the whole segment by
    // the same delta so the next tick's rebase is a no-op.
    if (_animator.isAnimating && !_animator.farAnimateActive) {
      _animator.shiftClosePathByInset(delta);
    }
  }

  void _onTopPaddingChanged() => markNeedsLayout();

  /// When [reachedNewest], never anchor past [newestKnownId] — consumers may
  /// pass `totalMessages` (a count) instead of the last id.
  int _clampJumpTarget(int messageId) {
    final newest = _dataSource.newestKnownId;
    if (_dataSource.reachedNewest && newest != null && messageId > newest) {
      return newest;
    }
    return messageId;
  }

  /// Drop deferred tail-settle state — user scroll or off-tail geometry
  /// preempts programmatic pin from attach / jump / lazy load.
  void _cancelPendingTailPin() {
    _pendingTailPinUntilSettled = false;
    _pinTailOnJump = false;
    _userPreemptedTailSettle = true;
  }

  /// Measured dual-translate flight only — not the post-jump measure layout.
  /// Measure layout must still run tail [pinNewest] so scroll-to-bottom lands
  /// on the message bottom before travel is measured; freezing earlier caused
  /// animating from the row top then teleporting mid-flight.
  bool _shouldFreezeStitchLayout() =>
      _animator.farAnimateActive &&
      _animator.farAnimateJumped &&
      _animator.stitchMeasured;

  /// Outgoing stitch rows keep capture-time layout offsets; fan-out from the
  /// jumped anchor would stack them against incoming ids and double-apply travel
  /// once paint adds [_stitchPaintDy].
  bool _skipStitchOutgoingReposition(int id) =>
      _animator.farAnimateActive &&
      _animator.farAnimateJumped &&
      _stitchOutgoingIds.contains(id);

  /// Tail-targeted navigation should pin the newest above the bottom inset
  /// even on the first layout (`_wasAtTailLastLayout` still false).
  void _markPinTailOnJumpIfNeeded(int targetId) {
    final newest = _dataSource.newestKnownId;
    if (_dataSource.reachedNewest && newest != null && targetId == newest) {
      _userPreemptedTailSettle = false;
      _pinTailOnJump = true;
      _pendingTailPinUntilSettled = true;
    }
  }

  /// Re-pin after lazy chunk load or bottom inset change until the tail
  /// actually settles — without yanking the user who scrolled away.
  void _applyPendingTailPin() {
    if (!_pendingTailPinUntilSettled) return;
    final newest = _dataSource.newestKnownId;
    if (!_dataSource.reachedNewest || newest == null) {
      _fetchAnchorEvent('layout.pendingTailPin', {
        ..._fetchAnchorSnapshot(),
        'action': 'clear',
        'reason': 'no-newest',
      });
      _pendingTailPinUntilSettled = false;
      return;
    }
    if (_controller.anchorMessageId != newest) {
      _fetchAnchorEvent('layout.pendingTailPin', {
        ..._fetchAnchorSnapshot(),
        'action': 'clear',
        'reason': 'anchor!=newest',
        'newestId': newest,
      });
      _pendingTailPinUntilSettled = false;
      return;
    }
    final messageLoaded = _dataSource.getMessage(newest) != null;
    if (messageLoaded && _computeIsAtTail()) {
      _fetchAnchorEvent('layout.pendingTailPin', {
        ..._fetchAnchorSnapshot(),
        'action': 'clear',
        'reason': 'at-tail-loaded',
        'newestId': newest,
      });
      _pendingTailPinUntilSettled = false;
      return;
    }
    if (messageLoaded && !_computeIsAtTail()) {
      final last = _boundaryBox(newest);
      if (last != null) {
        final pd = _parentData(last);
        final bottomEdge = size.height - _bottomPad;
        // Newest top at or below the inset line: the user scrolled off the
        // tail (anchor id may still be `newest` until renormalize drifts).
        // Tall / lazy settle keeps the top above the inset while the bottom
        // hangs below — only that case continues repinning.
        if (pd.offset >= bottomEdge - 0.5) {
          _fetchAnchorEvent('layout.pendingTailPin', {
            ..._fetchAnchorSnapshot(),
            'action': 'clear',
            'reason': 'user-scrolled-off-tail',
            'newestId': newest,
            'newestTop': LogFormat.f(pd.offset),
            'bottomEdge': LogFormat.f(bottomEdge),
          });
          _pendingTailPinUntilSettled = false;
          return;
        }
      }
    }
    _fetchAnchorEvent('layout.pendingTailPin', {
      ..._fetchAnchorSnapshot(),
      'action': 'repin',
      'newestId': newest,
      'newestLoaded': messageLoaded,
      'isAtTail': _computeIsAtTail(),
    });
    _pinTailOnJump = true;
  }

  /// Top offset for [messageHeight] at [alignment] within the scroll band
  /// (y = [topPad] .. bottom inset). `0` = band top; `1` = band bottom.
  double _alignedTopForMessage(double messageHeight, double alignment) {
    final topEdge = _topPad;
    final bottomEdge = size.height - _bottomPad;
    final travel = bottomEdge - topEdge - messageHeight;
    if (travel <= 0) return topEdge;
    return topEdge + alignment.clamp(0.0, 1.0) * travel;
  }

  /// Whether close-path [ChatScrollController.animateTo] should end at tail-pin
  /// geometry (`newest.bottom == bottomEdge`) rather than band alignment.
  bool _isTailClosePathTarget(int targetId) {
    final newest = _dataSource.newestKnownId;
    return _dataSource.reachedNewest && newest != null && targetId == newest;
  }

  /// Anchor top offset so [messageHeight] row's bottom sits on the bottom inset
  /// line — same geometry [pinNewest] applies in layout.
  double _tailPinnedTopForMessage(double messageHeight) {
    final bottomEdge = size.height - _bottomPad;
    return bottomEdge - messageHeight;
  }

  /// Close-path animate endpoint: tail pin for known-newest target, else
  /// [_alignedTopForMessage]. The animator adds its own pixel offset to the
  /// aligned seat.
  double _closePathEndOffsetFor(
    int targetId,
    double messageHeight,
    double alignment,
  ) {
    if (_isTailClosePathTarget(targetId)) {
      return _tailPinnedTopForMessage(messageHeight);
    }
    return _alignedTopForMessage(messageHeight, alignment);
  }

  /// Applies the armed [ChatScrollController.navigationPlacement] after the
  /// anchor message is laid out, and advances its lifecycle. Returns whether
  /// the anchor offset moved.
  ///
  /// Seats the target by kind:
  /// - [AlignmentPlacement] — top at [_alignedTopForMessage] plus
  ///   [AlignmentPlacement.pixelOffset].
  /// - [CenterBandPlacement] — the fixed 50% paint-band ray hits
  ///   `target top + offsetFromMessageTop`, the offset clamped into
  ///   `[0, height)` so the ray stays inside the rect [_publishCenterBand]
  ///   reads.
  ///
  /// Runs after [_resolveTailOrTarget] in the same pass: an alignment that
  /// decided for the tail is already released and never reaches this seat,
  /// and one that decided for the target is seated here like a plain jump.
  ///
  /// **Pending** (not yet landed on a loaded row): snaps the target on every
  /// layout, so a skeleton target that loads with a new height is re-seated.
  /// Once the snap lands on a loaded row the placement becomes **held**.
  ///
  /// **Held**: snaps again only when [reapplyHold] is set — the scroll band's
  /// top edge moved, or the target row's row chrome changed this pass.
  /// Otherwise it stays silent so bottom inset compensation, the boundary
  /// clamp, and height changes elsewhere keep their effect instead of being
  /// snapped back on every layout.
  ///
  /// **Release without a snap:**
  /// - A held target that is no longer the anchor (absent-anchor
  ///   reassignment, renormalize). A pending one is kept, because a far-path
  ///   animate arms the placement while the anchor still sits on the
  ///   outgoing strip.
  /// - A known-newest alignment target: the tail pin owns that geometry. A
  ///   Center Band target on the newest is still placed and held, so a
  ///   mid-bubble restore on the conversation newest keeps its offset. An
  ///   undecided tail-or-target jump is kept, unseated, until
  ///   [_resolveTailOrTarget] decides it on the layout that loads the row.
  /// - A Center Band placement on an empty scroll band.
  ///
  /// **Dual-writer guard:** close-path `animateTo` arms an alignment
  /// placement and [ChatAnimator.tickAnimate] interpolates
  /// [anchorPixelOffset] each tick. Snapping here on every [performLayout]
  /// while that animation runs fights the interpolator and produces the
  /// non-zero-alignment micro-jump. A measured stitch owns paint translation
  /// the same way. Deferred [jumpTo] and post-[animateTo] settle call this
  /// when neither is in flight.
  bool _applyNavigationPlacement({bool reapplyHold = false}) {
    if (_animator.farAnimateActive &&
        _animator.farAnimateJumped &&
        _animator.stitchMeasured) {
      return false;
    }
    final placement = _controller.navigationPlacement;
    if (placement == null) return false;
    if (_animator.isAnimating && !_animator.farAnimateActive) {
      return false;
    }
    final targetId = placement.messageId;
    if (_controller.anchorMessageId != targetId) {
      if (placement.isHeld) _controller.releaseNavigationPlacement();
      return false;
    }
    if (placement is AlignmentPlacement && _isTailClosePathTarget(targetId)) {
      if (placement.tailFitFraction == null) {
        _controller.releaseNavigationPlacement();
      }
      return false;
    }
    if (placement.isHeld && !reapplyHold) return false;

    final child = _boundaryBox(targetId);
    if (child == null || !child.hasSize) {
      return false;
    }
    final rowHeight = child.size.height;

    final double desiredTop;
    final String event;
    final Map<String, Object?> kindFields;
    switch (placement) {
      case AlignmentPlacement(:final alignment, :final pixelOffset):
        desiredTop = _alignedTopForMessage(rowHeight, alignment) + pixelOffset;
        event = 'layout.align';
        kindFields = {
          'alignment': LogFormat.f(alignment),
          'pixelOffset': LogFormat.f(pixelOffset),
        };
      case CenterBandPlacement(:final offsetFromMessageTop):
        final topEdge = _topPad;
        final bandHeight = size.height - _bottomPad - topEdge;
        if (bandHeight <= 0 || !bandHeight.isFinite) {
          _controller.releaseNavigationPlacement();
          return false;
        }
        final maxOffset = math.max<double>(0, rowHeight - 1e-6);
        final offset = offsetFromMessageTop.clamp(0.0, maxOffset);
        desiredTop = topEdge + bandHeight * 0.5 - offset;
        event = 'layout.centerBand';
        kindFields = {'offset': LogFormat.f(offset)};
    }

    final currentTop = _controller.anchorPixelOffset;
    final moved = (desiredTop - currentTop).abs() >= 0.5;
    if (moved) {
      _fetchAnchorEvent(event, {
        ..._fetchAnchorSnapshot(),
        'targetId': targetId,
        'from': LogFormat.f(currentTop),
        'to': LogFormat.f(desiredTop),
        ...kindFields,
        'childH': LogFormat.f(rowHeight),
        'held': placement.isHeld,
      });
      _controller.reassignAnchor(targetId, desiredTop);
      _repositionFromAnchor();
    }
    if (_dataSource.getMessage(targetId) != null) {
      _controller.holdNavigationPlacement();
    }
    return moved;
  }

  /// Decides an undecided tail-or-target jump (an [AlignmentPlacement] with
  /// a [AlignmentPlacement.tailFitFraction]) once its target is laid out as
  /// a loaded message row, and tells the host.
  ///
  /// Runs after renormalize and before [_applyNavigationPlacement], so the
  /// outcome and any unread boundary change the host makes for it reach the
  /// placement and the tail pin of this same pass:
  ///
  /// - **Tail** — [_layOutNewestBelow] yields the newest row, and the span
  ///   from the target's body top (below its row chrome) to that row's
  ///   bottom is at most the fraction of the viewport height — the whole
  ///   viewport, not the scroll band. The placement is released, the anchor
  ///   moves onto the newest row at its current offset, and the jump-to-tail
  ///   pin is armed, so the boundary clamp puts the newest row's bottom on
  ///   the bottom inset.
  /// - **Target** — no newest row, or a longer span. The placement stays
  ///   armed without the fraction and [_applyNavigationPlacement] seats and
  ///   holds it.
  ///
  /// Listeners run inside [invokeLayoutCallback], where the viewport's
  /// boundary listener may mark it dirty. When the unread boundary changed,
  /// this pass consumes the row chrome change — the next layout must not
  /// replay it as a hold — and re-fans, so every row is rebuilt against the
  /// new boundary before the target is seated or the tail pinned, and no
  /// painted frame shows the separator the host just removed or lacks the
  /// one it just added. The re-fan leaves this pass's hold inputs
  /// (`reapplyHold`, the row chrome reference) as computed before it; they
  /// do not apply, because the placement is still pending on the target
  /// outcome and gone on the tail outcome.
  ///
  /// Silent until this pass lays out the target row as a loaded message: a
  /// skeleton target defers the decision to the layout that loads it. The
  /// span reads only rows in [built]; a child this pass did not lay out
  /// keeps the geometry of an earlier pass, such as skeleton heights from
  /// before the chunk loaded.
  void _resolveTailOrTarget(
    BoxConstraints cc,
    Set<int> built,
    Set<int> builtChunks,
  ) {
    if (_controller.navigationPlacement
        case AlignmentPlacement(
          messageId: final targetId,
          tailFitFraction: final fraction?,
        )
        when _dataSource.getMessage(targetId) != null &&
            built.contains(targetId)) {
      final newest = _layOutNewestBelow(targetId, cc, built, builtChunks);
      final span = switch ((_children[targetId], newest)) {
        (final target?, (_, final last)) =>
          _parentData(last).offset +
              last.size.height -
              _parentData(target).offset -
              _parentData(target).messageBodyTop,
        _ => null,
      };
      final limit = fraction * size.height;
      final tail = switch ((newest, span)) {
        ((final id, final last), final span?) when span <= limit => (id, last),
        _ => null,
      };
      final outcome = switch (tail) {
        null => TailOrTargetOutcome.target,
        _ => TailOrTargetOutcome.tail,
      };
      _fetchAnchorEvent('layout.tailOrTarget', {
        ..._fetchAnchorSnapshot(),
        'targetId': targetId,
        'span': switch (span) {
          final span? => LogFormat.f(span),
          null => null,
        },
        'limit': LogFormat.f(limit),
        'outcome': outcome.name,
      });
      switch (tail) {
        case (final newestId, final last):
          _controller
            ..releaseNavigationPlacement()
            ..reassignAnchor(newestId, _parentData(last).offset);
          _markPinTailOnJumpIfNeeded(newestId);
        case null:
          _controller.markTailFitDecided();
      }
      _dispatchTailOrTarget(outcome, cc, built, builtChunks);
    }
  }

  /// Hands [outcome] to the controller's tail-or-target listeners inside a
  /// layout callback, then re-fans when a listener changed the unread
  /// boundary — see [_resolveTailOrTarget].
  void _dispatchTailOrTarget(
    TailOrTargetOutcome outcome,
    BoxConstraints cc,
    Set<int> built,
    Set<int> builtChunks,
  ) {
    final boundaryBefore = _unreadBoundary?.value;
    invokeLayoutCallback<BoxConstraints>(
      (_) => _controller.notifyTailOrTarget(outcome),
    );
    final boundaryAfter = _unreadBoundary?.value;
    if (boundaryAfter == boundaryBefore) return;
    _laidOutUnreadBoundary = boundaryAfter;
    _rowChromeChanged = false;
    // The outcome frame paints the decided geometry: no leg on either row.
    if (_rowChromeTransitions case final transitions?) {
      if (boundaryBefore != null) transitions.cancel(boundaryBefore);
      if (boundaryAfter != null) transitions.cancel(boundaryAfter);
      transitions.takeChanged();
    }
    built.clear();
    builtChunks.clear();
    _layoutFromAnchor(cc, built, builtChunks);
  }

  /// The newest message's id and laid-out row, when it lies close enough
  /// below the laid-out target [targetId] for a tail-or-target span to be
  /// measured; `null` when the newest message is not known
  /// ([ChatDataSource.reachedNewest]) or not loaded, or when it lies too far
  /// below the target to fit any fraction.
  ///
  /// Mutates the layout when this pass's fan-out left a loaded newest row
  /// out of [built] — a child kept from an earlier pass does not count: the
  /// rows are re-fanned with the target's body top on the viewport's top
  /// edge. Fan-out builds at least a viewport height below the anchor
  /// ([_fanOutFromAnchor] fills to `size.height` plus the cache extent), so
  /// a newest row still unbuilt is farther than a fraction of `1` allows.
  /// The re-fan moves the anchor onto the target; the pending placement or
  /// the tail pin re-seats it later in the pass.
  (int, RenderBox)? _layOutNewestBelow(
    int targetId,
    BoxConstraints cc,
    Set<int> built,
    Set<int> builtChunks,
  ) {
    final newest = _dataSource.newestKnownId;
    if (!_dataSource.reachedNewest || newest == null) return null;
    if (_dataSource.getMessage(newest) == null) return null;
    if (!built.contains(newest)) {
      if (_children[targetId] case final target?) {
        _controller.reassignAnchor(
          targetId,
          -_parentData(target).messageBodyTop,
        );
        built.clear();
        builtChunks.clear();
        _layoutFromAnchor(cc, built, builtChunks);
      }
    }
    return switch (_children[newest]) {
      final last? when built.contains(newest) => (newest, last),
      _ => null,
    };
  }

  /// Clamp a pre-mount [jumpTo] anchor that landed past [newestKnownId].
  /// [_onJump] handles the mounted case; this covers the listener gap.
  void _normalizeAnchorToKnownTail() {
    final anchorId = _controller.anchorMessageId;
    final targetId = _clampJumpTarget(anchorId);
    if (targetId == anchorId) return;
    _controller
      ..reassignAnchor(targetId, 0)
      ..syncNavigationPlacementTarget(targetId);
    if (!_controller.hasPendingNavigationCenterBand) {
      _markPinTailOnJumpIfNeeded(targetId);
    }
  }

  void _onJump(int messageId) {
    final targetId = _clampJumpTarget(messageId);
    if (targetId != messageId) {
      _controller.reassignAnchor(targetId, 0);
    }
    _controller.syncNavigationPlacementTarget(targetId);
    // Center Band mid-bubble restore on newest must not arm jump-to-tail pin —
    // that would fight [_applyNavigationPlacement] on the next layout.
    if (!_controller.hasPendingNavigationCenterBand) {
      _markPinTailOnJumpIfNeeded(targetId);
    }
    _cancelFling();
    // Stitch teleport is not a host jump — highlight stays armed through
    // dual-translate. Clearing here made navigate-select look like
    // "highlight only after settle".
    final stitchOwnedJump =
        _animator.farAnimateActive && _animator.animateTargetId == targetId;
    if (!stitchOwnedJump) {
      // Host / scrollbar jump — hard-clear leftover navigate tint.
      _clearHighlight();
    }
    _cancelOverscroll();
    // Scrollbar / discrete jump elsewhere must clear load-gate destination
    // pin; otherwise poll + jump-fetch keep requesting only the animate
    // window while this layout shows unloaded tiles. Stitch's own jumpTo
    // uses [animateTargetId] — keep that flight alive.
    if (_animator.animateCompleter != null &&
        _animator.animateTargetId != targetId) {
      _cancelAnimate(fadeHighlight: false);
    } else if (_chunkFetchScheduler.isOutsideNavigationDestination(targetId)) {
      // Orphan pin (animate already finished/cancelled incompletely) — drop it
      // so fetch follows the thumb again.
      _chunkFetchScheduler.clearNavigationDestination();
    }
    // Poll debounce + jump-fetch safety net — see [ChatChunkFetchScheduler.onJump].
    _chunkFetchScheduler.onJump();
    _activity?.pulse();
    markNeedsLayout();
  }

  void _onScrollBy(double delta) {
    _cancelFling();
    _cancelAnimate(fadeHighlight: false);
    _cancelHighlightForPan();
    _cancelOverscroll();
    _activity?.pulse(navigation: false);
    // Drop any drag delta accumulated since the last tick: the controller
    // has already shifted the anchor by `delta`; applying the pending drag
    // on top would make the drag appear to accelerate by `delta` for one
    // frame. The user keeps dragging from the new anchor.
    _pendingScrollDelta = 0.0;
    markNeedsLayout();
  }

  void _onBoundaryChanged() {
    _publishBoundaries();
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  // --- Layout ----------------------------------------------------------------

  @override
  void performLayout() {
    assert(() {
      _debugSw
        ..reset()
        ..start();
      return true;
    }());
    assert(childManager != null, 'childManager not wired by ChatScrollElement');
    assert(
      constraints.hasBoundedHeight && constraints.hasBoundedWidth,
      'RenderChatScrollView needs bounded constraints; got $constraints. '
      'Give it a finite size — wrap it in an Expanded, a sized SizedBox, or '
      'Positioned.fill.',
    );

    // Mode selection.
    //
    // * Empty wins over loading: a confirmed-empty conversation is terminal,
    //   while initial-loading is unknown — if both flip true simultaneously
    //   (a fetch resolves with `[]` and seeds the empty boundary), we want
    //   the empty UI immediately, not a skeleton.
    // * An empty conversation always skips the message fan-out, even when
    //   no `emptyBuilder` is wired: there are no ids to build, so shimmer
    //   placeholders for negative / large ids would be wrong.
    final ChatOverlayKind overlayKind;
    if (_dataSource.isEmpty) {
      overlayKind = _hasEmptyBuilder
          ? ChatOverlayKind.empty
          : ChatOverlayKind.none;
    } else if (_hasLoadingBuilder && _dataSource.isInitialLoading) {
      overlayKind = ChatOverlayKind.loading;
    } else {
      overlayKind = ChatOverlayKind.none;
    }

    _compensateBottomPaddingChange();

    final rowChromeChanged = _rowChromeChanged;
    _rowChromeChanged = false;
    final unreadBoundaryBefore = _laidOutUnreadBoundary;
    _laidOutUnreadBoundary = _unreadBoundary?.value;

    if (_dataSource.isEmpty || overlayKind != ChatOverlayKind.none) {
      _layoutOverlayMode(overlayKind);
      _rowChromeTransitions?.retainWhere(_children.containsKey);
      assert(() {
        debugLastLayoutDuration = _debugSw.elapsed;
        _debugSw.stop();
        debugLayoutFrameId++;
        return true;
      }());
      return;
    }

    // Normal mode: drop a previously-built overlay before fanning out.
    if (_overlayKind != ChatOverlayKind.none || _overlay != null) {
      _invokeChildManagerLayout(() {
        childManager!.buildOverlay(ChatOverlayKind.none);
      });
      _overlayKind = ChatOverlayKind.none;
    }

    _fetchAnchorLayoutFrame++;
    _fetchLogAnchorIdAtLayoutStart = _controller.anchorMessageId;
    _fetchLogAnchorYAtLayoutStart = _controller.anchorPixelOffset;
    final bandAtStart = _bottomBandMessage();
    _fetchLogBandIdAtLayoutStart = bandAtStart?.id;
    _fetchLogBandBottomAtLayoutStart = bandAtStart?.bottom;
    _fetchAnchorEvent('layout.begin', {
      ..._fetchAnchorSnapshot(),
      'fetchingChunks': LogFormat.ids(_fetchingChunkIndices(), max: 8),
    });
    // Drop pre-jump children so renormalize/clamp do not fan across the wrong
    // id span — but keep stitch presence pins (outgoing strip + animate target).
    if (_chunkFetchScheduler.jumpFetchPending) {
      final stitchPinned = _stitchPresencePinnedIds();
      final staleMessages = <int>[
        for (final id in _children.keys)
          if (!stitchPinned.contains(id)) id,
      ];
      final staleErrorChunks = _chunkErrors.keys.toList();
      if (staleMessages.isNotEmpty || staleErrorChunks.isNotEmpty) {
        _invokeChildManagerLayout(() {
          if (staleMessages.isNotEmpty) {
            childManager!.removeChildren(staleMessages);
          }
          if (staleErrorChunks.isNotEmpty) {
            childManager!.removeChunkErrors(staleErrorChunks);
          }
        });
      }
    }

    // Children span the full viewport width; each message widget centers its
    // own content column. A full-width child lets selection chrome tint the
    // whole row without bleeding past a narrower content box.
    final childConstraints = BoxConstraints.tightFor(width: size.width);

    _normalizeAnchorToKnownTail();

    // Held navigation placement triggers. When the placement is re-placed
    // this pass (its target's own row chrome changed, or a held target meets
    // a moved band top), the row chrome hold stands down — one origin writer
    // per pass.
    final topPad = _topPad;
    final topPadMoved = switch (_lastLaidOutTopPad) {
      final last? => last != topPad,
      null => false,
    };
    _lastLaidOutTopPad = topPad;
    final unreadBoundaryAfter = _laidOutUnreadBoundary;
    final boundaryMoved = unreadBoundaryBefore != unreadBoundaryAfter;
    if (boundaryMoved) {
      _startUnreadSeparatorTransitions(
        unreadBoundaryBefore,
        unreadBoundaryAfter,
      );
    }
    final chromeChangedRows = <int>{
      if (boundaryMoved) ...{?unreadBoundaryBefore, ?unreadBoundaryAfter},
      ...?_rowChromeTransitions?.takeChanged(),
    };
    final targetChromeChanged =
        rowChromeChanged && _isNavigationTargetChromeChange(chromeChangedRows);
    final reapplyHold = topPadMoved || targetChromeChanged;
    final placementOwnsPass =
        targetChromeChanged ||
        (topPadMoved &&
            (_controller.navigationPlacement?.isHeld ?? false) &&
            _isNavigationTargetAnchored());

    final rowChromeReference = rowChromeChanged && !placementOwnsPass
        ? _recordRowChromeReference()
        : null;

    // Delete recovery (absent anchor delete):
    //   record geometry → reassign neighbor → purge tombstones → fan-out →
    //   preserve viewport → [optional refan if band null] → skip renormalize →
    //   match band gap (pre-clamp) → clamp → [refan] → match band gap (post-clamp, 1 pass).
    _recordLayoutBeforeDelete();
    _reassignAnchorIfAbsent();
    _purgeAbsentBuiltChildren();

    final built = <int>{};
    final builtChunks = <int>{};
    _layoutFromAnchor(childConstraints, built, builtChunks);

    _preserveViewportAfterDelete();
    // Primary scroll shift is done; refan only when no band row exists yet
    // (mid-scroll off-screen — successor not intersecting the scroll band).
    if (_deleteCollapseRecoveryActive && _bottomBandMessage() == null) {
      built.clear();
      builtChunks.clear();
      _layoutFromAnchor(childConstraints, built, builtChunks);
    }
    if (_holdRowChromeReference(rowChromeReference)) {
      built.clear();
      builtChunks.clear();
      _layoutFromAnchor(childConstraints, built, builtChunks);
    }

    final anchorBefore = _controller.anchorMessageId;
    final anchorYBefore = _controller.anchorPixelOffset;
    if (!_skipRenormalizeDuringClosePath() &&
        !_skipRenormalizeDuringDeleteRecovery()) {
      _renormalizeAnchor();
    }
    final anchorAfterRenorm = _controller.anchorMessageId;
    final anchorYAfterRenorm = _controller.anchorPixelOffset;
    if (anchorAfterRenorm != anchorBefore ||
        (anchorYAfterRenorm - anchorYBefore).abs() > 0.5) {
      _fetchAnchorEvent('layout.renormalize', {
        ..._fetchAnchorSnapshot(),
        'anchorBefore': anchorBefore,
        'anchorAfter': anchorAfterRenorm,
        'yBefore': LogFormat.f(anchorYBefore),
        'yAfter': LogFormat.f(anchorYAfterRenorm),
      });
    }
    _resolveTailOrTarget(childConstraints, built, builtChunks);
    final navigationMoved = _applyNavigationPlacement(reapplyHold: reapplyHold);
    // Forcibly re-pin newest to the bottom edge when:
    // * follow-tail insert: viewport was at the tail and newest **id** advanced
    //   (new row lives below the previous bottomEdge), or
    // * same-id height growth while at tail (edit animation): without
    //   `repinBottom`, `pinNewest` only fires when `bottom < bottomEdge`, so a
    //   taller newest expands **under** the composer instead of upward.
    // Do **not** set `repinBottom` merely because `_wasAtTailLastLayout` —
    // that yanks the user back when they scroll away from the tail.
    // Near-miss manual flings (a few px into the pad) use [_tailEdgeSlop]
    // for `isAtTail` / follow only — not a forced pin-up on scroll-away.
    // Bottom inset changes are handled by [_compensateBottomPaddingChange] —
    // not here — so scrolling up in history is not yanked to the tail when
    // the keyboard opens.
    final newest = _dataSource.newestKnownId;
    final tailAdvanced =
        _wasAtTailLastLayout &&
        newest != null &&
        (_lastSeenNewestId == null || newest > _lastSeenNewestId!);
    final newestBox = newest != null ? _boundaryBox(newest) : null;
    final newestHeight = newestBox?.size.height;
    final newestHeightGrew =
        _wasAtTailLastLayout &&
        newest != null &&
        newestHeight != null &&
        _lastNewestLaidOutId == newest &&
        _lastNewestLaidOutHeight != null &&
        newestHeight > _lastNewestLaidOutHeight! + 0.5;
    // Span auto-scroll occupies the origin writer while the pointer sits in
    // the edge band — follow-tail and pending tail-pin must not also write.
    final occupyingSpanAutoScroll = _spanAutoScrollOccupying;
    final stitchLayoutFrozen = _shouldFreezeStitchLayout();
    if (!occupyingSpanAutoScroll && !stitchLayoutFrozen) {
      _applyPendingTailPin();
    }
    // Self-insert animate owns follow-tail motion: skip instant pin on id
    // advance (teleport). Same-id height growth still repins (edit expand).
    // A placement that seated its target this pass owns the origin: the
    // previous layout's tail state may come from skeleton rows that the
    // clamp pinned before the target's chunk loaded.
    final followTailRepin =
        !navigationMoved &&
        ((!_deferTailAdvancedRepin && tailAdvanced) || newestHeightGrew);
    final repinBottom =
        !stitchLayoutFrozen &&
        ((!occupyingSpanAutoScroll && _pinTailOnJump) ||
            (_dataSource.reachedNewest &&
                _wasAtTailLastLayout &&
                followTailRepin &&
                !occupyingSpanAutoScroll));
    if (repinBottom || _pendingTailPinUntilSettled || _pinTailOnJump) {
      _fetchAnchorEvent('layout.tailPinFlags', {
        ..._fetchAnchorSnapshot(),
        'repinBottom': repinBottom,
        'tailAdvanced': tailAdvanced,
        'newestHeightGrew': newestHeightGrew,
        'pinTailOnJump': _pinTailOnJump,
        if (stitchLayoutFrozen) 'frozen': 'stitchMeasured',
      });
    }
    _pinTailOnJump = false;
    // The tail pin takes the geometry: a held placement re-applied later
    // would drag the followed newest back under the bottom inset.
    if (repinBottom && (_controller.navigationPlacement?.isHeld ?? false)) {
      _controller.releaseNavigationPlacement();
    }
    // Fine-tune band gap before clamp — up to 3 passes; clamp may shift geometry.
    if (_deleteCollapseRecoveryActive &&
        _deleteCollapseExpectedBandGap != null) {
      _matchExpectedBandGap();
    }
    final clamped = _clampBoundaries(repinBottom: repinBottom);
    if (clamped) _cancelFling();

    // Re-fan from the corrected anchor. When pass 1 ran with the anchor far
    // off-screen it builds every message between the anchor and the viewport;
    // re-fanning from the renormalized (visible) anchor yields the tight set,
    // so the off-screen extras fall outside `built` and are collected below.
    if (!stitchLayoutFrozen &&
        (clamped ||
            _controller.anchorMessageId != anchorBefore ||
            navigationMoved)) {
      _fetchAnchorEvent('layout.refan', {
        ..._fetchAnchorSnapshot(),
        'clamped': clamped,
        'navigationMoved': navigationMoved,
        'anchorIdChanged': _controller.anchorMessageId != anchorBefore,
      });
      built.clear();
      builtChunks.clear();
      _layoutFromAnchor(childConstraints, built, builtChunks);
    }

    // One corrective pass after clamp/refan — avoid fighting pin logic in a loop.
    if (_deleteCollapseRecoveryActive &&
        _deleteCollapseExpectedBandGap != null) {
      _matchExpectedBandGap(maxPasses: 1);
    }

    // Garbage-collect children outside the build range. Messages and chunk-
    // error tiles travel through separate element-side channels. During
    // close-path animation the animate / nav targets stay built even when
    // fan-out would otherwise collect them at the cache margin.
    final gcPinned = _gcPinnedDuringClosePath();
    final staleMessages = <int>[
      for (final id in _children.keys)
        if (!built.contains(id) && !gcPinned.contains(id)) id,
    ];
    if (_animator.farAnimateActive && _stitchOutgoingIds.isNotEmpty) {
      final live = _stitchOutgoingIds.where(_children.containsKey).length;
      final wouldDrop = staleMessages.where(_stitchOutgoingIds.contains).length;
      // Once per stitch (or when pin health changes) — spam layouts otherwise.
      final sig = '$live/${gcPinned.length}/$wouldDrop';
      if (_stitchGcLogSig != sig) {
        _stitchGcLogSig = sig;
        fine(.animate, 'stitch.gc', {
          'pinned': gcPinned.length,
          'outgoingLive': live,
          'wouldDropOutgoing': wouldDrop,
          'staleN': staleMessages.length,
          'builtN': built.length,
        });
      }
    } else {
      _stitchGcLogSig = null;
    }
    final staleErrorChunks = <int>[
      for (final ci in _chunkErrors.keys)
        if (!builtChunks.contains(ci)) ci,
    ];
    if (staleMessages.isNotEmpty || staleErrorChunks.isNotEmpty) {
      _fetchAnchorEvent('layout.gc', {
        ..._fetchAnchorSnapshot(),
        'removed': LogFormat.ids(staleMessages, max: 12),
        'removedCount': staleMessages.length,
        'removedChunks': LogFormat.ids(staleErrorChunks, max: 4),
      });
      _invokeChildManagerLayout(() {
        if (staleMessages.isNotEmpty) {
          childManager!.removeChildren(staleMessages);
        }
        if (staleErrorChunks.isNotEmpty) {
          childManager!.removeChunkErrors(staleErrorChunks);
        }
      });
    }
    _rowChromeTransitions?.retainWhere(_children.containsKey);

    // Stitch outgoing stay outside fan-out `built` — layout + re-freeze so
    // they remain paint-valid for dual-translate.
    _layoutStitchOutgoingPinned(childConstraints);

    // Track the laid-out chunk range (for fetch + eviction). Messages and
    // chunk-error tiles together span the visible chunks — collapse both
    // through `chunkOf` to find the inclusive range.
    final int minChunk;
    final int maxChunk;
    if (_children.isEmpty && _chunkErrors.isEmpty) {
      minChunk = 0;
      maxChunk = -1;
    } else {
      var computedMin = _children.isEmpty
          ? _chunkErrors.firstKey()!
          : ChatScrollChunk.chunkOf(_children.firstKey()!);
      var computedMax = _children.isEmpty
          ? _chunkErrors.lastKey()!
          : ChatScrollChunk.chunkOf(_children.lastKey()!);
      if (_chunkErrors.isNotEmpty) {
        final eMin = _chunkErrors.firstKey()!;
        final eMax = _chunkErrors.lastKey()!;
        if (eMin < computedMin) computedMin = eMin;
        if (eMax > computedMax) computedMax = eMax;
      }
      minChunk = computedMin;
      maxChunk = computedMax;
    }
    // Fetch poll, LRU eviction, jump-fetch — [ChatChunkFetchScheduler].
    _chunkFetchScheduler.onLayoutComplete(minChunk, maxChunk);
    _updateScrollSemantics();
    _publishControllerState();
    _updateFloatingHeader();
    _animator.tryArmPendingHighlight();

    if (_animator.loadGateWaiting) {
      _animator.onLayoutOpportunity(viewportHeight: size.height);
    }
    _refreezeStitchOutgoing();
    _finishStitchMeasureIfNeeded();

    if (_animator.isAnimating && !_animator.farAnimateActive) {
      _animator.rebaseClosePathEnd(elapsed: _lastTickElapsed);
    }
    _resolveRowChromeFrame();

    final anchorYEnd = _controller.anchorPixelOffset;
    final anchorDy = _fetchLogAnchorYAtLayoutStart == null
        ? null
        : anchorYEnd - _fetchLogAnchorYAtLayoutStart!;
    final bandAtEnd = _bottomBandMessage();
    final bandBottomDy =
        _fetchLogBandBottomAtLayoutStart == null || bandAtEnd == null
        ? null
        : bandAtEnd.bottom - _fetchLogBandBottomAtLayoutStart!;
    final idChanged =
        _fetchLogAnchorIdAtLayoutStart != _controller.anchorMessageId;
    final bandIdChanged = _fetchLogBandIdAtLayoutStart != bandAtEnd?.id;
    if ((anchorDy != null && anchorDy.abs() > 0.5) ||
        idChanged ||
        (bandBottomDy != null && bandBottomDy.abs() > 1.0) ||
        bandIdChanged) {
      _fetchAnchorEvent('layout.jump', {
        ..._fetchAnchorSnapshot(),
        'anchorDy': anchorDy == null ? null : LogFormat.f(anchorDy),
        'anchorIdChanged': idChanged,
        'bandIdWas': _fetchLogBandIdAtLayoutStart,
        'bandIdNow': bandAtEnd?.id,
        'bandBottomDy': bandBottomDy == null ? null : LogFormat.f(bandBottomDy),
        'clamped': clamped,
        'refan':
            clamped ||
            _controller.anchorMessageId != anchorBefore ||
            navigationMoved,
      });
    }
    _deleteCollapseViewportPreservedThisLayout = false;
    _deleteCollapseRecoveryActive = false;
    _deleteCollapseWasAtTailBefore = false;
    _deleteCollapseUserPreemptedTailBefore = false;
    _deleteCollapseExpectedBandGap = null;
    _beforeDeleteLayout = null;

    if (_spanAutoScrollOccupying) _applyLiveSpanHit();
    _fetchAnchorEvent('layout.end', _fetchAnchorSnapshot());
    if (LogCategory.scrollbar.enabled) {
      final computed = _computeScrollbarProgress();
      if (computed != null) {
        _scrollbarEvent(
          'layout.end',
          _scrollbarProgressFields(computed, reason: 'layout'),
        );
      }
    }

    assert(() {
      debugLastLayoutDuration = _debugSw.elapsed;
      _debugSw.stop();
      debugLayoutFrameId++;
      return true;
    }());
  }

  /// Run a layout pass in overlay mode: drop the message fan-out, build a
  /// single full-viewport child, place it at (0,0). Message tiles, chunk-
  /// error tiles, and the floating day header are all GC'd.
  void _layoutOverlayMode(ChatOverlayKind kind) {
    final staleMessages = _children.keys.toList();
    final staleErrorChunks = _chunkErrors.keys.toList();

    _invokeChildManagerLayout(() {
      if (staleMessages.isNotEmpty) {
        childManager!.removeChildren(staleMessages);
      }
      if (staleErrorChunks.isNotEmpty) {
        childManager!.removeChunkErrors(staleErrorChunks);
      }
      if (_floatingHeader != null) {
        childManager!.buildFloatingHeader(null, null);
      }
      if (_overlayKind != kind) {
        childManager!.buildOverlay(kind);
      }
    });
    _overlayKind = kind;

    final overlay = _overlay;
    if (overlay != null) {
      overlay.layout(BoxConstraints.tight(size), parentUsesSize: false);
      _parentData(overlay).offset = 0.0;
    }

    _floatingHeaderController.clearForOverlay();
    _scrollVelocity = 0.0;
    _pendingScrollDelta = 0.0;
    _cancelFling();
    _cancelAnimate(fadeHighlight: false);
    // Overlay owns the viewport — leftover wash and the controller slot
    // must not survive. Paint-only clear would late-arm on remount.
    // The overlay-branch `_clearHighlight()` in `_onTick` is unreachable
    // once the ticker has stopped, so this layout path is the authority.
    _controller.dropHighlightRequest();
    _clearHighlight();
    // Clear drag + bounceback state so that the next normal-mode layout's
    // `_clampBoundaries` is not silently suppressed by stale flags. The
    // ticker is about to stop, so the overlay branch of `_onTick` can no
    // longer reset them.
    _dragInProgress = false;
    _cancelOverscroll();
    // An active drag survives a hit-test entry if the gesture arena already
    // assigned the pointer to our recognizer. handleEvent's overlay-mode
    // guard only blocks *new* pointers — the recognizer will keep dispatching
    // onUpdate for the already-tracked pointer, mutating the anchor while
    // the overlay paints. Re-creating the recognizer drops the active
    // tracking without affecting future drag setup in normal mode.
    if (_drag != null) {
      _drag!.dispose();
      _drag = _buildDragRecognizer();
    }
    _ticker?.stop();
    // Fetch poll + LRU eviction — [ChatChunkFetchScheduler].
    _chunkFetchScheduler.onLayoutCleared();
    _updateScrollSemantics();
    _publishControllerState();
  }

  /// Build + lay out + position children fanning out from the anchor, in a
  /// single `invokeLayoutCallback` (lazy inflation is legal during layout
  /// only inside such a callback).
  void _layoutFromAnchor(
    BoxConstraints cc,
    Set<int> built,
    Set<int> builtChunks,
  ) {
    _invokeChildManagerLayout(() => _fanOutFromAnchor(cc, built, builtChunks));
  }

  /// Inclusive lower id bound for upward layout fan-out.
  ///
  /// While [ChatDataSource.reachedOldest] is false, [ChatDataSource.oldestKnownId]
  /// is the oldest *loaded* page — not the conversation edge. Clamping
  /// fan-out there prevents building placeholders for older chunks and
  /// deadlocks lazy pagination.
  int? get _fanOutOldestBound =>
      _dataSource.reachedOldest ? _dataSource.oldestKnownId : 0;

  /// Records band / anchor geometry before absent-anchor reassignment.
  ///
  /// When [ChatScrollController.anchorMessageId] is confirmed-absent (e.g.
  /// deleted while scrolled to that row), reassign to a present neighbor before
  /// fan-out so `_buildMessage(anchorId)` never targets a tombstone slot.
  ///
  /// Tail delete prefers [ChatDataSource.getPreviousPresentMessage]; reading
  /// history prefers [ChatDataSource.getNextPresentMessage]. Preserves
  /// [ChatScrollController.anchorPixelOffset] for the handoff; scroll adjustment
  /// in [_preserveViewportAfterDelete] keeps the visible band stable — not
  /// [_renormalizeAnchor].
  void _recordLayoutBeforeDelete() {
    final anchorId = _controller.anchorMessageId;
    if (!_dataSource.statusOf(anchorId).isAbsent) return;

    final resolved = _resolveAnchorBox();
    final staleBox = _children[anchorId];
    final deletedHeight = resolved != null && resolved.box.hasSize
        ? resolved.box.size.height
        : (staleBox != null && staleBox.hasSize ? staleBox.size.height : null);
    final band = _bottomBandMessage();
    _beforeDeleteLayout = _BeforeDeleteLayoutSnapshot(
      deletedId: anchorId,
      deletedHeight: deletedHeight,
      anchorYBefore: _controller.anchorPixelOffset,
      bandIdBefore: band?.id,
      bandBottomBefore: band?.bottom,
      bandGapBefore: band?.gapToBottomEdge,
      bottomEdgeBefore: size.height - _bottomPad,
      userPreemptedTailBefore: _userPreemptedTailSettle,
      wasAtTailBefore: _computeIsAtTail(),
    );
  }

  /// Keeps the viewport reading position stable when the layout anchor row
  /// disappears.
  ///
  /// Called once per delete layout pass, after [_reassignAnchorIfAbsent] and the
  /// first [_layoutFromAnchor]. Does **not** refan — only shifts
  /// [ChatScrollController.anchorPixelOffset] and repositions existing children.
  ///
  /// See [_scrollDeltaForDelete] for the delta decision tree; see
  /// [_matchExpectedBandGap] for post-clamp gap correction.
  void _preserveViewportAfterDelete() {
    final before = _beforeDeleteLayout;
    if (before == null) return;
    _beforeDeleteLayout = null;

    const eps = _deleteCollapseEpsilon;
    final bottomEdge = size.height - _bottomPad;
    final bandAfterLayout = _bottomBandMessage();
    final resolvedAnchor = _resolveAnchorBox();
    final anchorHeightAfter = resolvedAnchor?.box.size.height ?? 0.0;

    final scrollDelta = _scrollDeltaForDelete(
      before: before,
      bottomEdge: bottomEdge,
      bandAfterLayout: bandAfterLayout,
      anchorHeightAfter: anchorHeightAfter,
    );

    final applied = scrollDelta.abs() > eps;
    if (applied) {
      _shiftLayoutByScrollDelta(
        scrollDelta,
        expectedBandBottom: before.bandBottomBefore,
      );
    }

    _deleteCollapseViewportPreservedThisLayout = true;
    _deleteCollapseRecoveryActive = true;
    _deleteCollapseWasAtTailBefore = before.wasAtTailBefore;
    _deleteCollapseUserPreemptedTailBefore = before.userPreemptedTailBefore;
    if (applied) {
      _deleteCollapseExpectedBandGap = before.bandGapBefore;
    }

    final bandAfter = _bottomBandMessage();
    _fetchAnchorEvent('layout.deleteCollapse', {
      ..._fetchAnchorSnapshot(),
      'deletedId': before.deletedId,
      'deletedHeight': before.deletedHeight == null
          ? null
          : LogFormat.f(before.deletedHeight!),
      'anchorYBefore': LogFormat.f(before.anchorYBefore),
      'scrollDelta': LogFormat.f(scrollDelta),
      'anchorHeightAfter': LogFormat.f(anchorHeightAfter),
      'bandIdBefore': before.bandIdBefore,
      'bandBottomBefore': before.bandBottomBefore == null
          ? null
          : LogFormat.f(before.bandBottomBefore!),
      'bandBottomAfterPre': bandAfterLayout == null
          ? null
          : LogFormat.f(bandAfterLayout.bottom),
      'bandBottomAfter': bandAfter == null
          ? null
          : LogFormat.f(bandAfter.bottom),
      'bottomEdge': LogFormat.f(bottomEdge),
      'userPreemptedTailBefore': before.userPreemptedTailBefore,
      'pinNewestSuppressed':
          before.userPreemptedTailBefore && _deleteCollapseRecoveryActive,
      'isAtTailAfter': _computeIsAtTail(),
      'refan': false,
    });
  }

  /// How much to shift [ChatScrollController.anchorPixelOffset] after delete.
  ///
  /// Called after pass-1 fan-out with the **neighbor** as anchor. Goal: keep the
  /// user's reading position — measured by [_bottomBandMessage] bottom relative
  /// to [bottomEdge] — stable when the deleted row collapses to zero height.
  ///
  /// Positive delta moves content down (same sign as
  /// [ChatScrollController.applyScrollDelta]).
  ///
  /// ## Inputs (all from pre-delete snapshot + post fan-out geometry)
  ///
  /// - [before.anchorYBefore] — deleted row top before reassignment; `≈ 0` means
  ///   the user was at the **top** of the tall message (zero scroll delta for
  ///   very tall rows).
  /// - [before.bandIdBefore] / [before.bandBottomBefore] — which built row's
  ///   bottom was closest to the composer inset before delete.
  /// - [bandAfterLayout] — same probe **after** neighbor reassignment + fan-out,
  ///   before any scroll shift (often a different id / much higher bottom).
  /// - [anchorHeightAfter] — laid-out height of the **new** anchor (successor);
  ///   used to compute collapsed extent when band bottom cannot be measured.
  ///
  /// ## Decision tree (first matching branch wins)
  ///
  /// 1. Top-anchored delete — preserve absent-anchor handoff or medium-tall band fix.
  /// 2. Deleted row **was** the band — restore band bottom or shift by collapsed height.
  /// 3. Another row was the band — band-bottom delta only.
  /// 4. No measurable band — shift by at most the portion of deleted height that
  ///    lived above the viewport top.
  double _scrollDeltaForDelete({
    required _BeforeDeleteLayoutSnapshot before,
    required double bottomEdge,
    required ({int id, double top, double bottom, double gapToBottomEdge})?
    bandAfterLayout,
    required double anchorHeightAfter,
  }) {
    const eps = _deleteCollapseEpsilon;
    final viewportHeight = bottomEdge;

    // ── Branch 1: top-anchored delete (deleted top on or above viewport top) ──
    //
    // User sees the start of the deleted message. Absent-anchor reassignment
    // already hands off to the neighbor at the same anchorY; for very tall rows
    // (≥ 2× viewport) that handoff is correct — scroll delta must stay 0
    // (next message top stays at former deleted top).
    if (before.anchorYBefore >= -eps) {
      final keepZeroAnchorOffset =
          before.deletedHeight != null &&
          before.deletedHeight! >= 2 * viewportHeight;
      // Medium-tall exception (~1.0–1.5× viewport): anchorY stays 0 but the
      // visible band was the deleted row's bottom — without a shift the band
      // jumps silently. Measure band-bottom delta instead.
      if (!keepZeroAnchorOffset &&
          before.bandIdBefore == before.deletedId &&
          bandAfterLayout != null &&
          before.bandBottomBefore != null) {
        return before.bandBottomBefore! - bandAfterLayout.bottom;
      }
      return 0;
    }

    // ── Branch 2: deleted row was the visible band ──
    //
    // bandIdBefore == deletedId  →  the message whose bottom was nearest the
    // composer is the one being removed. After collapse the successor becomes
    // anchor; band bottom drops by roughly (deletedHeight - anchorHeightAfter).
    if (before.bandIdBefore == before.deletedId &&
        before.deletedHeight != null &&
        anchorHeightAfter > 0) {
      // bandBottomBefore > bottomEdge  →  user was reading the lower interior
      // of a tall message whose bottom extended past the scroll band.
      final bandExtendsBelowEdge =
          before.bandBottomBefore != null &&
          before.bandBottomBefore! > bottomEdge + eps;
      if (bandExtendsBelowEdge) {
        // Prefer direct band-bottom measurement when fan-out produced a band row.
        if (bandAfterLayout != null && before.bandBottomBefore != null) {
          return before.bandBottomBefore! - bandAfterLayout.bottom;
        }
        // Analytic fallback: shift by how much vertical extent disappeared
        // (full deleted height minus the short successor now at anchor).
        return before.deletedHeight! - anchorHeightAfter;
      }
      // Band bottom was on-screen (mid-scroll interior): same band-bottom delta.
      if (bandAfterLayout != null && before.bandBottomBefore != null) {
        return before.bandBottomBefore! - bandAfterLayout.bottom;
      }
      return before.deletedHeight! - anchorHeightAfter;
    }

    // ── Branch 3: band was a different row (e.g. message below the anchor) ──
    //
    // Deleting the anchor shrinks the stack above the band row; band bottom
    // moves up by the collapsed height. Restoring bandBottomBefore fixes it.
    if (bandAfterLayout != null && before.bandBottomBefore != null) {
      return before.bandBottomBefore! - bandAfterLayout.bottom;
    }

    // ── Branch 4: no band probe — conservative height-based shift ──
    //
    // aboveViewport = portion of deleted row that lived above y=0 (scrolled
    // off the top). Cannot shift more than deletedHeight — only removes extent
    // that could have affected what is visible.
    if (before.deletedHeight != null) {
      final aboveViewport = math.max<double>(0, -before.anchorYBefore);
      return math.min(before.deletedHeight!, aboveViewport);
    }

    return 0;
  }

  /// Applies [delta] to the anchor offset and repositions children in place.
  ///
  /// When [expectedBandBottom] is set, performs one small follow-up shift if the
  /// measured band bottom is still off by at most 200 logical px.
  void _shiftLayoutByScrollDelta(double delta, {double? expectedBandBottom}) {
    const eps = _deleteCollapseEpsilon;
    _controller.applyScrollDelta(delta);
    _repositionFromAnchor();
    if (expectedBandBottom == null) return;
    final band = _bottomBandMessage();
    if (band == null) return;
    final followUp = expectedBandBottom - band.bottom;
    if (followUp.abs() <= eps || followUp.abs() > 200) return;
    _controller.applyScrollDelta(followUp);
    _repositionFromAnchor();
  }

  bool _skipRenormalizeDuringDeleteRecovery() =>
      _deleteCollapseViewportPreservedThisLayout ||
      _deleteCollapseRecoveryActive;

  /// Fine-tunes scroll so the visible band gap matches [_deleteCollapseExpectedBandGap].
  ///
  /// [_preserveViewportAfterDelete] applies the primary [scrollDelta]; this method
  /// closes residual error when later layout steps (especially
  /// [_clampBoundaries] `pinNewest` / `pinOldest`) nudge geometry again.
  ///
  /// **Gap** = [_bottomBandMessage].gapToBottomEdge — distance from the band
  /// row's bottom to the scroll band bottom (`height - bottomPad`). The expected
  /// value was captured before delete in [_recordLayoutBeforeDelete].
  ///
  /// ## [maxPasses]
  ///
  /// Maximum correction iterations **per call**. Each pass: measure band → compute
  /// [gapCorrection] → [ChatScrollController.applyScrollDelta] →
  /// [_repositionFromAnchor]. Multiple passes can be needed because each nudge may
  /// change which row [_bottomBandMessage] picks as the band.
  ///
  /// [performLayout] calls this twice during delete recovery:
  ///
  /// - **Before clamp** — default [maxPasses] = 3: converge before pins run.
  /// - **After clamp** (and optional refan) — [maxPasses] = 1: single nudge only;
  ///   clamp already moved geometry and further loops would fight pin logic.
  ///
  /// ## [tolerance] (8 logical px)
  ///
  /// Stop when `|currentGap - expectedGap| ≤ tolerance`. This is the viewport
  /// stability bar for delete recovery (same threshold as widget tests), not the
  /// machine epsilon [_deleteCollapseEpsilon].
  ///
  /// ## Early exits inside the loop
  ///
  /// - No band row to measure.
  /// - [gapCorrection] ≤ [_deleteCollapseEpsilon] — already negligible.
  /// - [gapCorrection] > 200 — too large for a fine-tune nudge.
  /// - [gapCorrection] > 0 and correction would push the entire band row off-screen
  ///   (short successor after a tall delete — cannot restore a below-edge gap).
  void _matchExpectedBandGap({int maxPasses = 3}) {
    final expectedGap = _deleteCollapseExpectedBandGap;
    if (expectedGap == null || !_deleteCollapseRecoveryActive) return;
    const eps = _deleteCollapseEpsilon;
    const tolerance = 8.0;
    for (var pass = 0; pass < maxPasses; pass++) {
      final band = _bottomBandMessage();
      if (band == null) return;

      // Close enough — viewport stable for reading position near composer.
      final gapDelta = (band.gapToBottomEdge - expectedGap).abs();
      if (gapDelta <= tolerance) return;

      // Positive gapCorrection → band is too high (gap too small); scroll up.
      // applyScrollDelta uses the opposite sign (see body below).
      final gapCorrection = expectedGap - band.gapToBottomEdge;
      if (gapCorrection.abs() <= eps || gapCorrection.abs() > 200) return;

      final bottomEdge = size.height - _bottomPad;
      // Would expanding gap push the whole band row above the viewport top?
      if (gapCorrection > 0 &&
          band.bottom + gapCorrection - bottomEdge > band.bottom - band.top) {
        return;
      }
      _controller.applyScrollDelta(-gapCorrection);
      _repositionFromAnchor();
    }
  }

  /// Whether a row chrome change on this pass touches the armed navigation
  /// placement's target while that target is the anchor: the target is among
  /// [changedRows] — the old and the new unread boundary row on the pass
  /// that moves the boundary, and every row whose separator transition
  /// frame moved since the previous pass.
  ///
  /// When true the placement is re-applied instead of running the row chrome
  /// hold, on every frame of the transition, so a separator added to the
  /// target grows at the placement (for alignment `0`, from the band top)
  /// with the body below it, rather than growing upward past the band top
  /// to keep the band bottom row still.
  ///
  /// Only the unread boundary drives row chrome today; a new row chrome
  /// source must report its rows here too.
  bool _isNavigationTargetChromeChange(Set<int> changedRows) =>
      _isNavigationTargetAnchored() &&
      changedRows.contains(_controller.anchorMessageId);

  /// Turns an unread boundary move from [from] to [to] into separator
  /// transitions, before this pass fans out.
  ///
  /// The old row exits when it was laid out last frame carrying the
  /// separator; the new row enters when it was laid out last frame as a
  /// loaded message. Any other row changes without a transition: its leg is
  /// cancelled, so it is built settled (or without the separator) on this
  /// pass.
  void _startUnreadSeparatorTransitions(int? from, int? to) {
    final transitions = _rowChromeTransitions;
    if (transitions == null) return;
    if (from != null) {
      if (_children[from] case final RenderChatRowChrome row
          when row.hasSize && row.hasTransitioningItem) {
        transitions.exit(from);
      } else {
        transitions.cancel(from);
      }
    }
    if (to != null) {
      if ((_children[to]?.hasSize ?? false) &&
          _dataSource.getMessage(to) != null) {
        transitions.enter(to);
      } else {
        transitions.cancel(to);
      }
    }
  }

  /// Whether the armed navigation placement's target is the current anchor —
  /// the only state in which [_applyNavigationPlacement] places it instead
  /// of releasing it.
  bool _isNavigationTargetAnchored() =>
      _controller.navigationPlacement?.messageId == _controller.anchorMessageId;

  /// Captures the reading position before a row chrome change re-lays out
  /// the rows: the **reference row** and its bottom edge measured from the
  /// anchor row's top.
  ///
  /// The reference row is the highest-id built message whose top sits above
  /// the scroll band bottom (`height - bottomPad`) — the row at the band
  /// bottom, or the newest row when content ends above it. Holding its
  /// bottom edge keeps the bodies at and below a changed row in place while
  /// that row is on screen or above it (the rows above absorb the change),
  /// keeps the newest row pinned at the tail, and lets chrome that changes
  /// below the band grow off screen without moving what is visible.
  ///
  /// Not [_bottomBandMessage]: that probe picks the row whose bottom is
  /// nearest the band bottom, which can be a row above the one straddling
  /// the edge. A changed row between the two would then grow downward into
  /// the band instead of upward.
  ///
  /// Measured relative to the anchor, both edges from the same frame's
  /// offsets, so a scroll delta or a jump queued since that frame does not
  /// skew the result. `null` — nothing to hold — before the first layout,
  /// while an animation or a stitch freeze owns the anchor, or when the
  /// anchor row is not built.
  _RowChromeReference? _recordRowChromeReference() {
    if (_animator.isAnimating || _shouldFreezeStitchLayout()) return null;
    final anchor = _resolveAnchorBox();
    if (anchor == null || !anchor.box.hasSize) return null;
    final bottomEdge = size.height - _bottomPad;
    (int id, double bottom)? reference;
    for (final MapEntry(key: id, value: child) in _children.entries) {
      if (!child.hasSize) continue;
      final top = _parentData(child).offset;
      if (top >= bottomEdge) continue;
      reference = (id, top + child.size.height);
    }
    return switch (reference) {
      (final id, final bottom) => (
        anchorId: _controller.anchorMessageId,
        referenceId: id,
        bottomFromAnchor: bottom - _parentData(anchor.box).offset,
      ),
      null => null,
    };
  }

  /// Shifts the scroll origin so the row captured by
  /// [_recordRowChromeReference] keeps its screen Y after the pass-1
  /// fan-out re-laid out rows with changed row chrome.
  ///
  /// Silent when [reference] is `null`, when delete recovery owns this pass,
  /// when the anchor id changed since the capture (reassignment or a jump to
  /// another row — the relative measure no longer applies), or when either
  /// row is no longer built. Runs before renormalize, navigation alignment,
  /// and the boundary clamp, so an explicit jump alignment and the tail pin
  /// still have the last word.
  ///
  /// Returns whether the origin moved. The shift only repositions built
  /// rows, so the caller re-fans to fill the band edge the shift uncovered.
  bool _holdRowChromeReference(_RowChromeReference? reference) {
    if (reference == null || _deleteCollapseRecoveryActive) return false;
    if (_controller.anchorMessageId != reference.anchorId) return false;
    final anchor = _resolveAnchorBox();
    final row = _children[reference.referenceId];
    if (anchor == null || row == null) return false;
    final bottomFromAnchor =
        _parentData(row).offset +
        row.size.height -
        _parentData(anchor.box).offset;
    final delta = reference.bottomFromAnchor - bottomFromAnchor;
    // Exact: a transition moves the chrome a fraction of a pixel per frame,
    // and every skipped shift would add to the drift.
    if (delta.abs() <= precisionErrorTolerance) return false;
    _shiftLayoutByScrollDelta(delta);
    _fetchAnchorEvent('layout.rowChromeHold', {
      ..._fetchAnchorSnapshot(),
      'referenceId': reference.referenceId,
      'delta': LogFormat.f(delta),
    });
    return true;
  }

  void _reassignAnchorIfAbsent() {
    final anchorId = _controller.anchorMessageId;
    if (!_dataSource.statusOf(anchorId).isAbsent) return;
    // Presence pin: do not soft-retarget the animate target mid wait/flight.
    // Explicit delete cancels first via [RemoveBatchMutation]; remaining
    // Absent while pinned is treated as false Absent for navigation.
    if (_stitchPresencePinnedIds().contains(anchorId)) return;

    final newest = _dataSource.newestKnownId;
    final atTail =
        _dataSource.reachedNewest && newest != null && anchorId == newest;

    final candidate = atTail
        ? (_dataSource.getPreviousPresentMessage(anchorId) ??
              _dataSource.getNextPresentMessage(anchorId))
        : (_dataSource.getNextPresentMessage(anchorId) ??
              _dataSource.getPreviousPresentMessage(anchorId));

    if (candidate == null) return;

    _controller.reassignAnchor(candidate.id, _controller.anchorPixelOffset);
  }

  /// Deactivates message elements for ids that became confirmed-absent since
  /// the last layout — prevents ghost rows and stale skip-cache entries.
  void _purgeAbsentBuiltChildren() {
    final presencePinned = _stitchPresencePinnedIds();
    final absentBuilt = <int>[
      for (final id in _children.keys)
        if (_dataSource.statusOf(id).isAbsent && !presencePinned.contains(id))
          id,
    ];
    if (absentBuilt.isEmpty) return;
    _invokeChildManagerLayout(() {
      childManager!.removeChildren(absentBuilt);
    });
  }

  void _fanOutFromAnchor(
    BoxConstraints cc,
    Set<int> built,
    Set<int> builtChunks,
  ) {
    final anchorId = _controller.anchorMessageId;
    final fanOldest = _fanOutOldestBound;
    final newest = _dataSource.newestKnownId;

    // Build zone = cacheExtent + keep-alive band, plus a directional lead
    // biased toward travel so a fast fling does not outrun the built range.
    final base = _cacheExtent + _extraBuildExtent;
    final lead = (_scrollVelocity.abs() * _leadFrames).clamp(0.0, size.height);
    final topExtent = base + (_scrollVelocity > 0 ? lead : 0.0);
    final bottomExtent = base + (_scrollVelocity < 0 ? lead : 0.0);
    final lowerBound = size.height + bottomExtent;
    final topBound = -topExtent;

    // Anchor: chunk-error tile when the anchor's chunk failed and a builder
    // was supplied; the actual message otherwise. The anchor's "size" then
    // determines where downward fan-out begins.
    //
    // Confirmed-absent anchors are reassigned in [_reassignAnchorIfAbsent]
    // before fan-out; [_buildMessage] also returns null for absent ids. Non-
    // anchor absent ids are skipped in the loops below — zero height, no
    // [ChatChildManager.buildChild] / messageBuilder invocation.
    //
    // No fallback to `_buildMessage` on a null chunk-error build: the chunk
    // is errored, so 64 per-message slots would surface `status.isError`
    // through `messageBuilder` — a one-frame flash of the very UI the
    // chunk-error builder was wired to replace. Bail and let the next layout
    // (after the builder swap settles) place the right tile.
    final anchorChunkIndex = ChatScrollChunk.chunkOf(anchorId);
    final RenderBox? anchor;
    final bool anchorIsError;
    if (_isChunkErrored(anchorChunkIndex)) {
      anchor = _buildChunkError(anchorChunkIndex, cc);
      anchorIsError = anchor != null;
      if (anchor == null) return;
    } else {
      anchor = _buildMessage(anchorId, cc);
      anchorIsError = false;
      if (anchor == null) return;
    }
    final anchorTop = _controller.anchorPixelOffset;
    _setOffset(anchor, anchorTop);
    if (anchorIsError) {
      builtChunks.add(anchorChunkIndex);
    } else {
      built.add(anchorId);
    }

    // Fan downward (newer messages).
    var y = anchorTop + anchor.size.height;
    var id = anchorIsError
        ? ChatScrollChunk.firstIdOf(anchorChunkIndex + 1)
        : anchorId + 1;
    while (y < lowerBound && (newest == null || id <= newest)) {
      final chunkIndex = ChatScrollChunk.chunkOf(id);
      if (_isChunkErrored(chunkIndex)) {
        final tile = _buildChunkError(chunkIndex, cc);
        if (tile == null) break;
        _setOffset(tile, y);
        builtChunks.add(chunkIndex);
        y += tile.size.height;
        id = ChatScrollChunk.firstIdOf(chunkIndex + 1);
        continue;
      }
      // Skip absent IDs — they are permanently non-existent and contribute
      // zero height. Use the helper to advance past runs of absent slots in
      // O(chunk) time rather than O(ID) time. Presence-pinned ids stay live
      // for stitch / load-gate (false Absent must not collapse the strip).
      if (_dataSource.statusOf(id).isAbsent && !isPresencePinned(id)) {
        final bound = newest ?? id;
        id = _nextNonAbsentIdDown(id + 1, bound);
        continue;
      }
      final child = _buildMessage(id, cc);
      // null means the element declined (host unmounted); treat as a genuine
      // stop, not an absent skip — it is NOT safe to advance id++ here.
      if (child == null) break;
      _setOffset(child, y);
      built.add(id);
      y += child.size.height;
      id++;
    }

    // Fan upward (older messages).
    y = anchorTop;
    id = anchorIsError
        ? ChatScrollChunk.firstIdOf(anchorChunkIndex) - 1
        : anchorId - 1;
    while (y > topBound && (fanOldest == null || id >= fanOldest)) {
      final chunkIndex = ChatScrollChunk.chunkOf(id);
      if (_isChunkErrored(chunkIndex)) {
        final tile = _buildChunkError(chunkIndex, cc);
        if (tile == null) break;
        y -= tile.size.height;
        _setOffset(tile, y);
        builtChunks.add(chunkIndex);
        id = ChatScrollChunk.firstIdOf(chunkIndex) - 1;
        continue;
      }
      // Skip absent IDs — permanently non-existent, contribute zero height.
      // Presence-pinned ids stay live for stitch / load-gate.
      if (_dataSource.statusOf(id).isAbsent && !isPresencePinned(id)) {
        final bound = fanOldest ?? id;
        id = _nextNonAbsentIdUp(id - 1, bound);
        continue;
      }
      final child = _buildMessage(id, cc);
      if (child == null) break;
      y -= child.size.height;
      _setOffset(child, y);
      built.add(id);
      id--;
    }

    // Tall anchors alone can fill past the build zone so id±1 never enters
    // fan-out — reverse hops then stitch with reason=notBuilt. Keep one
    // present neighbor beyond each overshooting edge so scrollTo-style
    // `found` / close-path can win on the way back.
    if (!anchorIsError) {
      _ensureTallAnchorEdgeNeighbors(
        cc: cc,
        built: built,
        anchorId: anchorId,
        anchorTop: anchorTop,
        anchorHeight: anchor.size.height,
        lowerBound: lowerBound,
        topBound: topBound,
        newest: newest,
        fanOldest: fanOldest,
      );
    }
  }

  /// When [anchorHeight] alone crosses a fan-out bound, force-build the
  /// first present neighbor past that edge (if any).
  void _ensureTallAnchorEdgeNeighbors({
    required BoxConstraints cc,
    required Set<int> built,
    required int anchorId,
    required double anchorTop,
    required double anchorHeight,
    required double lowerBound,
    required double topBound,
    required int? newest,
    required int? fanOldest,
  }) {
    final anchorBottom = anchorTop + anchorHeight;

    // Newer / below: downward loop never ran because y already >= lowerBound.
    if (anchorBottom >= lowerBound && (newest == null || anchorId < newest)) {
      final bound = newest ?? anchorId + 1;
      var id = anchorId + 1;
      if (_dataSource.statusOf(id).isAbsent && !isPresencePinned(id)) {
        id = _nextNonAbsentIdDown(id + 1, bound);
      }
      if (id <= bound &&
          !built.contains(id) &&
          !_isChunkErrored(ChatScrollChunk.chunkOf(id))) {
        final child = _buildMessage(id, cc);
        if (child != null) {
          _setOffset(child, anchorBottom);
          built.add(id);
        }
      }
    }

    // Older / above: upward loop never ran because y already <= topBound.
    if (anchorTop <= topBound && (fanOldest == null || anchorId > fanOldest)) {
      final bound = fanOldest ?? anchorId - 1;
      var id = anchorId - 1;
      if (_dataSource.statusOf(id).isAbsent && !isPresencePinned(id)) {
        id = _nextNonAbsentIdUp(id - 1, bound);
      }
      if (id >= bound &&
          !built.contains(id) &&
          !_isChunkErrored(ChatScrollChunk.chunkOf(id))) {
        final child = _buildMessage(id, cc);
        if (child != null) {
          _setOffset(child, anchorTop - child.size.height);
          built.add(id);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Blank-viewport snap helpers
  // ---------------------------------------------------------------------------

  /// Called once at the end of every `performLayout` pass (after all anchor
  /// renormalization and boundary clamping). When absent-marking has collapsed
  /// a large contiguous run of shimmer rows, the anchor can end up below the
  /// viewport bottom leaving a completely blank visible region.
  ///
  /// This method detects that state and snaps the anchor to the viewport
  /// bottom edge so real content is visible before the first paint.
  ///
  /// **Conditions that trigger the snap**:
  ///   1. Not currently mid-drag or bounceback (same guard as `_clampBoundaries`).
  ///   2. Anchor's top y-coordinate ≥ `size.height` (anchor is off-screen below).
  ///   3. No built message chunk is in a loading state — a loading chunk means
  ///      shimmers will appear once the fetch completes, so no snap is needed.
  ///
  /// When all three hold, the anchor is reassigned to
  // ---------------------------------------------------------------------------
  // Absent-slot skip helpers
  //
  // These helpers advance past runs of absent IDs in O(chunk) time rather
  // than O(ID) time. The fan-out loops call them when `statusOf(id).isAbsent`
  // is true — the returned ID is the next one worth attempting to build.
  //
  // Both helpers stop on the first non-absent slot, regardless of whether that
  // slot is actually loaded (present) or merely unloaded (pending/dirty). The
  // fan-out loop then calls `_buildMessage` on the returned ID as normal; if
  // the chunk is not yet fetched, `_buildMessage` returns a shimmer tile as
  // before.
  //
  // Absent and present are disjoint per the chunk invariant, so stopping at
  // the first non-absent slot is correct.
  // ---------------------------------------------------------------------------

  /// Advances [startId] downward (toward higher IDs) until a non-absent slot
  /// is found, skipping entire fully-absent chunks in O(1). Returns the first
  /// non-absent ID ≥ [startId], stopping at [bound] (inclusive).
  ///
  /// **Termination guarantee**: when [startId] > [bound] OR the entire range
  /// [startId, bound] is absent, returns `bound + 1`. The caller's outer
  /// loop guard (`id <= newest`) will then evaluate `bound + 1 <= newest` and
  /// exit cleanly. Returning [bound] itself would be wrong: if [bound] is also
  /// absent, `statusOf(bound).isAbsent` re-enters this helper with the same
  /// arguments, causing an infinite loop.
  int _nextNonAbsentIdDown(int startId, int bound) {
    var id = startId;
    while (id <= bound) {
      final chunkIndex = ChatScrollChunk.chunkOf(id);
      final chunk = _dataSource.chunks[chunkIndex];
      if (chunk == null) return id; // chunk not loaded; let normal path handle
      if (chunk.isFullyAbsent) {
        // Skip the entire chunk in O(1).
        id = ChatScrollChunk.firstIdOf(chunkIndex + 1);
        continue;
      }
      // Scan from current slot to the end of this chunk.
      var slot = id - chunk.firstId;
      while (slot < ChatScrollChunk.kSize) {
        if (!chunk.isAbsentSlot(slot)) return chunk.firstId + slot;
        slot++;
      }
      // All remaining slots in this chunk are absent; advance to next chunk.
      id = ChatScrollChunk.firstIdOf(chunkIndex + 1);
    }
    // Entire range was absent (or startId > bound). Return bound + 1 so the
    // outer loop's `id <= newest` guard exits on the very next evaluation.
    return bound + 1;
  }

  /// Advances [startId] upward (toward lower IDs) until a non-absent slot is
  /// found, skipping entire fully-absent chunks in O(1). Returns the first
  /// non-absent ID ≤ [startId], stopping at [bound] (inclusive, lower limit).
  ///
  /// **Termination guarantee**: when [startId] < [bound] OR the entire range
  /// [bound, startId] is absent, returns `bound - 1`. The caller's outer
  /// loop guard (`id >= oldest`) will then evaluate `bound - 1 >= oldest` and
  /// exit cleanly. Returning [bound] itself would be wrong: if [bound] is also
  /// absent, `statusOf(bound).isAbsent` re-enters this helper with the same
  /// arguments, causing an infinite loop.
  int _nextNonAbsentIdUp(int startId, int bound) {
    var id = startId;
    while (id >= bound) {
      final chunkIndex = ChatScrollChunk.chunkOf(id);
      final chunk = _dataSource.chunks[chunkIndex];
      if (chunk == null) return id; // chunk not loaded; let normal path handle
      if (chunk.isFullyAbsent) {
        // Skip the entire chunk in O(1).
        id = ChatScrollChunk.firstIdOf(chunkIndex) - 1;
        continue;
      }
      // Scan from current slot downward to the start of this chunk.
      var slot = id - chunk.firstId;
      while (slot >= 0) {
        if (!chunk.isAbsentSlot(slot)) return chunk.firstId + slot;
        slot--;
      }
      // All slots from the start of this chunk are absent; go to previous chunk.
      id = ChatScrollChunk.firstIdOf(chunkIndex) - 1;
    }
    // Entire range was absent (or startId < bound). Return bound - 1 so the
    // outer loop's `id >= oldest` guard exits on the very next evaluation.
    return bound - 1;
  }

  /// Build, lay out, and tag one message child. Stores its day-grouping info
  /// (`startsDay` / `dayBucket`) in parent data so the per-frame header walk is
  /// a pure field read. The caller sets [ChatMessageParentData.offset].
  RenderBox? _buildMessage(int id, BoxConstraints cc) {
    // Confirmed-absent slots must not inflate widgets or selection chrome —
    // defense in depth alongside fan-out skip and [_reassignAnchorIfAbsent].
    // Presence-pinned ids stay mounted for stitch / load-gate despite false
    // Absent (explicit delete cancels first via [RemoveBatchMutation]).
    if (_dataSource.statusOf(id).isAbsent && !isPresencePinned(id)) {
      return null;
    }
    final bucket = _bucketOf(id);
    final startsDay = _startsDay(id, bucket);
    final runLayout = _senderRunLayout.resolve(
      dataSource: _dataSource,
      groupBy: _groupBy,
      messageId: id,
    );
    final child = childManager!.buildChild(
      id,
      startsNewDay: startsDay,
      groupBucket: bucket,
      runLayout: runLayout,
    );
    if (child == null) return null;
    if (child case final RenderChatRowChrome row) {
      row.transition = _rowChromeTransitions?.frameOf(id);
    }
    child.layout(cc, parentUsesSize: true);
    _touchChunk(id);
    final loaded = _dataSource.getMessage(id) != null;
    if (LogCategory.anchor.enabled) {
      _fetchAnchorEvent('build.tile', {
        'id': id,
        'loaded': loaded,
        'h': LogFormat.f(child.size.height),
        'isAnchor': id == _controller.anchorMessageId,
        'chunk': ChatScrollChunk.chunkOf(id),
      });
    }
    _parentData(child)
      ..startsDay = startsDay
      ..dayBucket = bucket;
    return child;
  }

  /// Build and lay out a chunk-error tile — one widget standing in for the
  /// entire chunk. Stored in `_chunkErrors` keyed by chunk index. Returns
  /// `null` when the element declines to build it (e.g. host removed the
  /// errorBuilder mid-flight).
  RenderBox? _buildChunkError(int chunkIndex, BoxConstraints cc) {
    final firstId = ChatScrollChunk.firstIdOf(chunkIndex);
    final lastId = firstId + ChatScrollChunk.kSize - 1;
    final tile = childManager!.buildChunkError(chunkIndex, firstId, lastId);
    if (tile == null) return null;
    tile.layout(cc, parentUsesSize: true);
    _touchChunk(firstId);
    _parentData(tile)
      ..startsDay = false
      ..dayBucket = null;
    return tile;
  }

  /// Whether [chunkIndex] is in error state *and* an error builder is wired
  /// — i.e., the chunk should be represented by a single chunk-error tile
  /// instead of 64 per-message slots.
  bool _isChunkErrored(int chunkIndex) {
    if (!_hasErrorBuilder) return false;
    final chunk = _dataSource.chunks[chunkIndex];
    return chunk != null && chunk.status.isError;
  }

  /// Resolve the render box currently positioned at `anchorMessageId`: the
  /// message tile if its chunk is normal, the chunk-error tile if its chunk
  /// failed. Returns `null` when neither is built yet (first frame, between
  /// fetches, …).
  ({RenderBox box, bool isChunkError})? _resolveAnchorBox() {
    final anchorId = _controller.anchorMessageId;
    // Fast path for the dominant valid-data-only case: skip the
    // chunk-error map lookup entirely when no chunk has errored.
    if (_chunkErrors.isEmpty) {
      final msg = _children[anchorId];
      return msg == null ? null : (box: msg, isChunkError: false);
    }
    final anchorChunkIndex = ChatScrollChunk.chunkOf(anchorId);
    final errorTile = _chunkErrors[anchorChunkIndex];
    if (errorTile != null) {
      return (box: errorTile, isChunkError: true);
    }
    final msg = _children[anchorId];
    if (msg != null) return (box: msg, isChunkError: false);
    return null;
  }

  /// Group key for [id], or `null` when its message is not loaded (or
  /// grouping is disabled).
  Object? _bucketOf(int id) {
    final groupBy = _groupBy;
    if (groupBy == null) return null;
    final message = _dataSource.getMessage(id);
    return message == null ? null : groupBy(message);
  }

  /// Whether message [id] is the first of its group — and so carries an
  /// inline date separator. Uses [ChatDataSource.getPreviousPresentMessage]
  /// for the predecessor bucket; until the previous present message is loaded
  /// returns `false`, so the separator appears once the data arrives.
  bool _startsDay(int id, Object? bucket) {
    if (bucket == null) return false;
    final oldest = _dataSource.oldestKnownId;
    if (_dataSource.reachedOldest && oldest != null && id <= oldest) {
      return true; // the very first message of the conversation
    }
    final prev = _dataSource.getPreviousPresentMessage(id);
    if (prev == null) return false;
    final groupBy = _groupBy;
    if (groupBy == null) return false;
    final prevBucket = groupBy(prev);
    return prevBucket != bucket;
  }

  void _touchChunk(int id) {
    final chunk = _dataSource.chunks[ChatScrollChunk.chunkOf(id)];
    if (chunk != null) chunk.lastAccessTick = ++_accessTick;
  }

  /// Close-path `animateTo` keeps [ChatScrollController.anchorMessageId] on the
  /// target while interpolating [anchorPixelOffset] — including when the target
  /// row is temporarily off-screen. [_renormalizeAnchor] must not reassign away.
  /// Far-path stitch also suspends renormalize so the jumped target stays put
  /// while outgoing rows remain pinned for dual-translate paint.
  bool _skipRenormalizeDuringClosePath() => _animator.isAnimating;

  /// Whether [id] is presence-pinned for an in-flight animate (load-gate or
  /// stitch). Element build must not deactivate these on false Absent.
  bool isPresencePinned(int id) => _stitchPresencePinnedIds().contains(id);

  /// Ids presence-pinned for load-gate wait + stitch flight (target + outgoing).
  ///
  /// Immune to GC and false Absent handling until settle or explicit-delete
  /// cancel. See CONTEXT "Stitch presence pin".
  Set<int> _stitchPresencePinnedIds() {
    if (!_animator.isAnimating) return const {};
    final pinned = <int>{_animator.animateTargetId};
    if (_animator.farAnimateActive) {
      pinned.addAll(_stitchOutgoingIds);
    }
    if (_controller.navigationPlacement case AlignmentPlacement(
      :final messageId,
    )) {
      pinned.add(messageId);
    }
    return pinned;
  }

  /// Message ids that must survive GC while close-path or stitch animation
  /// keeps them on screen (close target / outgoing stitch strip).
  Set<int> _gcPinnedDuringClosePath() => _stitchPresencePinnedIds();

  /// If the anchor message drifted beyond the cache extent, silently re-base
  /// the anchor onto the first visible child (no visual change). The anchor
  /// may already be a chunk-error tile — picked up via [_resolveAnchorBox].
  void _renormalizeAnchor() {
    final resolved = _resolveAnchorBox();
    if (resolved == null) return;
    final anchor = resolved.box;
    final pd = _parentData(anchor);
    final top = pd.offset;
    final bottom = top + anchor.size.height;
    if (bottom >= -_cacheExtent && top <= size.height + _cacheExtent) return;

    // Find the topmost visible child — messages and chunk-error tiles share
    // viewport space, walk both and pick the smallest-offset candidate whose
    // bottom is still on screen.
    int? bestId;
    var bestOffset = double.infinity;
    for (final entry in _children.entries) {
      final cpd = _parentData(entry.value);
      if (cpd.offset + entry.value.size.height > 0 && cpd.offset < bestOffset) {
        bestId = entry.key;
        bestOffset = cpd.offset;
      }
    }
    for (final entry in _chunkErrors.entries) {
      final cpd = _parentData(entry.value);
      if (cpd.offset + entry.value.size.height > 0 && cpd.offset < bestOffset) {
        // Reassign to the chunk's first id — the next fan-out will detect
        // the chunk-error tile via `_isChunkErrored`.
        bestId = ChatScrollChunk.firstIdOf(entry.key);
        bestOffset = cpd.offset;
      }
    }
    if (bestId != null) {
      final fromId = _controller.anchorMessageId;
      final fromY = _controller.anchorPixelOffset;
      _controller.reassignAnchor(bestId, bestOffset);
      _fetchAnchorEvent('tick.renormalize', {
        ..._fetchAnchorSnapshot(),
        'fromId': fromId,
        'toId': bestId,
        'fromY': LogFormat.f(fromY),
        'toY': LogFormat.f(bestOffset),
      });
      if (LogCategory.scrollbar.enabled) {
        final before = _computeScrollbarProgress(
          anchorIdOverride: fromId,
          anchorYOverride: fromY,
        );
        final after = _computeScrollbarProgress();
        _scrollbarEvent('renormalize', {
          'fromId': fromId,
          'toId': bestId,
          'fromY': LogFormat.f(fromY),
          'toY': LogFormat.f(bestOffset),
        });
        if (before != null) {
          _scrollbarEvent(
            'renormalize.before',
            _scrollbarProgressFields(before, reason: 'before'),
          );
        }
        if (after != null) {
          _scrollbarEvent(
            'renormalize.after',
            _scrollbarProgressFields(after, reason: 'after'),
          );
        }
      }
    }
  }

  /// Pin content to the viewport edges at conversation boundaries.
  /// Returns `true` if a boundary was hit (fling should cancel).
  ///
  /// [repinBottom] also pulls the newest message *up* onto the bottom edge —
  /// used when the reserved bottom inset grew while the viewport was pinned
  /// there, so the message follows the inset instead of being covered.
  ///
  /// The two pins (newest-to-bottom, oldest-to-top) compete when the entire
  /// conversation fits in the viewport — whichever runs last "wins". In
  /// `reverse: false` (list-style) the oldest-pin runs last so short content
  /// stacks at the top; in `reverse: true` (chat-style) the newest-pin runs
  /// last so short content stacks at the bottom.
  /// Find the render box for a boundary id (oldest / newest). When the id's
  /// chunk is in error mode, the boundary visually lives at the chunk-error
  /// tile rather than at a (missing) message slot, so pinning anchors there.
  RenderBox? _boundaryBox(int id) {
    final tile = _chunkErrors[ChatScrollChunk.chunkOf(id)];
    if (tile != null) return tile;
    return _children[id];
  }

  /// Whether the full loaded conversation span fits inside the scroll band
  /// (`topPad` .. `height - bottomPad`) with both boundaries reached.
  ///
  /// When true there is no *travel* range: scrollbar, span auto-scroll, and
  /// inertial fling are suppressed. Pointer unconsumed dy still drives the
  /// edge effect of [physics].
  bool _contentFitsInViewport() {
    if (!hasSize || _overlayKind != ChatOverlayKind.none) return false;
    if (!_dataSource.reachedOldest || !_dataSource.reachedNewest) return false;
    final oldest = _dataSource.oldestKnownId;
    final newest = _dataSource.newestKnownId;
    if (oldest == null || newest == null) return false;
    final first = _boundaryBox(oldest);
    final last = _boundaryBox(newest);
    if (first == null || last == null) return false;
    final topY = _parentData(first).offset;
    final bottom = _parentData(last).offset + last.size.height;
    final bandHeight = size.height - _topPad - _bottomPad;
    if (bandHeight <= 0) return false;
    return bottom - topY <= bandHeight + 0.5;
  }

  /// Portion of [delta] that a reached conversation edge cannot consume.
  ///
  /// Remaining travel is `max(0, distance-to-pin)`. A sub-pixel remainder
  /// must still be consumed — never treat "almost at the edge" as "the
  /// whole gesture is overscroll". If the boundary box is not built, that
  /// edge is not in play (unconsumed = 0). Short content has zero travel
  /// on both pins, so the full delta is unconsumed.
  double _unconsumedOverscrollDelta(double delta) {
    if (delta == 0.0 || !hasSize) return 0;
    if (delta > 0) {
      if (!_dataSource.reachedOldest) return 0;
      final oldest = _dataSource.oldestKnownId;
      final box = oldest != null ? _boundaryBox(oldest) : null;
      if (box == null) return 0;
      final travel = math.max<double>(0, -_parentData(box).offset);
      if (delta <= travel) return 0;
      return delta - travel;
    }
    if (!_dataSource.reachedNewest) return 0;
    final newest = _dataSource.newestKnownId;
    final box = newest != null ? _boundaryBox(newest) : null;
    if (box == null) return 0;
    final bottom = _parentData(box).offset + box.size.height;
    final travel = math.max<double>(0, bottom - (size.height - _bottomPad));
    if (-delta <= travel) return 0;
    return delta + travel;
  }

  bool _clampBoundaries({bool repinBottom = false}) {
    // Layout never rubber-bands. Unconsumed dy feeds the paint-only edge
    // effect, not a pin skip. Stitch freeze still owns the anchor until
    // dual-translate settles.
    if (_shouldFreezeStitchLayout()) return false;
    var cancelFling = false;

    bool pinNewest() {
      final newest = _dataSource.newestKnownId;
      if (!_dataSource.reachedNewest || newest == null) return false;
      // Pad transitions are owned by [_compensateBottomPaddingChange] in
      // layout. Tick-path pin against the live pad before compensate double-
      // shifts (especially while stretch keeps the ticker running).
      if (_bottomPaddingDirty) return false;
      if (_deleteCollapseRecoveryActive) {
        if (!_deleteCollapseWasAtTailBefore) return false;
        if (_deleteCollapseUserPreemptedTailBefore && _computeIsAtTail()) {
          return false;
        }
      }
      if (_userPreemptedTailSettle && !_computeIsAtTail()) return false;
      final last = _boundaryBox(newest);
      if (last == null) return false;
      final bottom = _parentData(last).offset + last.size.height;
      // Pin the newest message above the reserved bottom inset (composer,
      // attachment previews, …) instead of against the viewport edge.
      final bottomEdge = size.height - _bottomPad;
      if (bottom < bottomEdge || (repinBottom && bottom > bottomEdge)) {
        final delta = bottomEdge - bottom;
        _fetchAnchorEvent('layout.pinNewest', {
          ..._fetchAnchorSnapshot(),
          'delta': LogFormat.f(delta),
          'repinBottom': repinBottom,
          'newestId': newest,
          'newestBottom': LogFormat.f(bottom),
          'newestTop': LogFormat.f(_parentData(last).offset),
          'newestH': LogFormat.f(last.size.height),
          'newestLoaded': _dataSource.getMessage(newest) != null,
        });
        _controller.applyScrollDelta(delta);
        _repositionFromAnchor();
        if (_animator.farAnimateActive && _animator.farAnimateJumped) {
          _refreezeStitchOutgoing();
        }
        return true;
      }
      return false;
    }

    bool pinOldest() {
      if (_deleteCollapseRecoveryActive && _bottomBandMessage() != null) {
        return false;
      }
      final oldest = _dataSource.oldestKnownId;
      if (!_dataSource.reachedOldest || oldest == null) return false;
      final first = _boundaryBox(oldest);
      if (first == null) return false;
      final topY = _parentData(first).offset;
      if (topY > 0) {
        final delta = -topY;
        _fetchAnchorEvent('layout.pinOldest', {
          ..._fetchAnchorSnapshot(),
          'delta': LogFormat.f(delta),
          'oldestId': oldest,
          'oldestTop': LogFormat.f(topY),
        });
        _controller.applyScrollDelta(delta);
        _repositionFromAnchor();
        return true;
      }
      return false;
    }

    // Short content: one pin only — dual pins fight during fling/bounceback
    // (pinOldest then pinNewest with equal and opposite deltas).
    if (_contentFitsInViewport() && !_deleteCollapseRecoveryActive) {
      final keepTopHandoff =
          _controller.anchorPixelOffset >= -0.5 && !repinBottom;
      if (_reverse) {
        if (!keepTopHandoff) {
          cancelFling = pinNewest() || cancelFling;
        }
      } else if (!keepTopHandoff) {
        final oldest = _dataSource.oldestKnownId;
        final first = oldest != null ? _boundaryBox(oldest) : null;
        if (first != null) {
          final topY = _parentData(first).offset;
          if (topY.abs() > 0.5) {
            _controller.applyScrollDelta(-topY);
            _repositionFromAnchor();
            cancelFling = true;
          }
        }
      }
      return cancelFling;
    }

    if (_reverse) {
      cancelFling = pinOldest() || cancelFling;
      cancelFling = pinNewest() || cancelFling;
    } else {
      cancelFling = pinNewest() || cancelFling;
      cancelFling = pinOldest() || cancelFling;
    }
    return cancelFling;
  }

  /// Recompute every child's [ChatMessageParentData.offset] from the anchor
  /// without rebuilding or re-laying-out. O(visible children).
  ///
  /// Walks message tiles id by id and jumps over a whole chunk whenever a
  /// chunk-error tile is encountered — chunk-error tiles live at
  /// `firstIdOf(chunkIndex)` with their entire chunk's ids unrepresented.
  void _repositionFromAnchor() {
    final resolved = _resolveAnchorBox();
    if (resolved == null) return;
    final anchor = resolved.box;
    // Tier-1 hot path: when no chunk errored, drop every per-id chunk-error
    // probe and walk the message map alone (the original O(visible) loop).
    if (_chunkErrors.isEmpty) {
      _repositionMessagesOnly(anchor);
      return;
    }

    final anchorIsError = resolved.isChunkError;
    final anchorChunkIndex = ChatScrollChunk.chunkOf(
      _controller.anchorMessageId,
    );

    // Find the range of built message IDs to bound the absent-skip loops.
    // See _repositionMessagesOnly for why `break` on null is wrong.
    var maxBuiltId = _controller.anchorMessageId;
    var minBuiltId = _controller.anchorMessageId;
    for (final id in _children.keys) {
      if (id > maxBuiltId) maxBuiltId = id;
      if (id < minBuiltId) minBuiltId = id;
    }

    var y = _controller.anchorPixelOffset;
    _setOffset(anchor, y);

    // Walk downward (toward newer ids).
    y += anchor.size.height;
    var id = anchorIsError
        ? ChatScrollChunk.firstIdOf(anchorChunkIndex + 1)
        : _controller.anchorMessageId + 1;
    while (id <= maxBuiltId ||
        _chunkErrors.containsKey(ChatScrollChunk.chunkOf(id))) {
      final ci = ChatScrollChunk.chunkOf(id);
      // At a chunk boundary, a chunk-error tile pre-empts message slots.
      if (id == ChatScrollChunk.firstIdOf(ci)) {
        final tile = _chunkErrors[ci];
        if (tile != null) {
          _setOffset(tile, y);
          y += tile.size.height;
          id = ChatScrollChunk.firstIdOf(ci + 1);
          continue;
        }
      }
      if (id > maxBuiltId) break;
      final child = _children[id];
      if (child == null) {
        id++;
        continue;
      } // skip absent / unbuilt IDs
      if (_skipStitchOutgoingReposition(id)) {
        id++;
        continue;
      }
      _setOffset(child, y);
      y += child.size.height;
      id++;
    }

    // Walk upward (toward older ids).
    y = _controller.anchorPixelOffset;
    id = anchorIsError
        ? ChatScrollChunk.firstIdOf(anchorChunkIndex) - 1
        : _controller.anchorMessageId - 1;
    while (id >= minBuiltId ||
        _chunkErrors.containsKey(ChatScrollChunk.chunkOf(id))) {
      final ci = ChatScrollChunk.chunkOf(id);
      final lastIdOfChunk = ChatScrollChunk.firstIdOf(ci + 1) - 1;
      if (id == lastIdOfChunk) {
        final tile = _chunkErrors[ci];
        if (tile != null) {
          y -= tile.size.height;
          _setOffset(tile, y);
          id = ChatScrollChunk.firstIdOf(ci) - 1;
          continue;
        }
      }
      if (id < minBuiltId) break;
      final child = _children[id];
      if (child == null) {
        id--;
        continue;
      } // skip absent / unbuilt IDs
      if (_skipStitchOutgoingReposition(id)) {
        id--;
        continue;
      }
      y -= child.size.height;
      _setOffset(child, y);
      id--;
    }
  }

  /// Tier-1 fast path: only message tiles. Avoids the per-id chunk-error
  /// boundary probe and tree lookup that the general path performs.
  void _repositionMessagesOnly(RenderBox anchor) {
    final anchorId = _controller.anchorMessageId;
    if (_children.isEmpty) return;

    // Find the actual range of built message IDs so we can skip absent-slot
    // gaps without stopping prematurely. Absent IDs are never inserted into
    // `_children`, so iterating by sequential ID would stop at the first
    // absent slot and leave real messages on the far side of the gap with
    // stale offsets — producing visual "shifting" on every animation tick.
    var maxBuiltId = anchorId;
    var minBuiltId = anchorId;
    for (final id in _children.keys) {
      if (id > maxBuiltId) maxBuiltId = id;
      if (id < minBuiltId) minBuiltId = id;
    }

    var y = _controller.anchorPixelOffset;
    _setOffset(anchor, y);
    y += anchor.size.height;
    for (var id = anchorId + 1; id <= maxBuiltId; id++) {
      final child = _children[id];
      if (child == null) continue; // skip absent / unbuilt IDs in the range
      if (_skipStitchOutgoingReposition(id)) continue;
      _setOffset(child, y);
      y += child.size.height;
    }
    y = _controller.anchorPixelOffset;
    for (var id = anchorId - 1; id >= minBuiltId; id--) {
      final child = _children[id];
      if (child == null) continue; // skip absent / unbuilt IDs in the range
      if (_skipStitchOutgoingReposition(id)) continue;
      y -= child.size.height;
      _setOffset(child, y);
    }
  }

  // --- Day separators --------------------------------------------------------

  /// Set a child's viewport [offset].
  ///
  /// Marks [_childOffsetsMoved] when the Y actually changes so
  /// [_publishControllerState] can notify scroll-observer chrome.
  void _setOffset(RenderBox child, double offset) {
    final pd = _parentData(child);
    if (pd.offset != offset) {
      _childOffsetsMoved = true;
    }
    pd.offset = offset;
  }

  /// Paint translation while stitch is jumped; `0` otherwise.
  double _stitchPaintDyIfActive(int id) =>
      (_animator.farAnimateActive && _animator.farAnimateJumped)
      ? _stitchPaintDy(id)
      : 0.0;

  /// Floating header effect resolved by [_resolveRowChromeFrame].
  ChatFloatingHeaderEffect _headerEffect = const ChatFloatingHeaderEffect(
    opacity: 0,
  );

  final LayerHandle<OpacityLayer> _headerOpacityLayer =
      LayerHandle<OpacityLayer>();

  /// Resolves the floating header through [_dayHeaderDelegate], places it,
  /// and publishes the row chrome inputs (paint top, header zone, activity)
  /// into every child's parent data. Runs at the end of every layout, every
  /// scroll tick, and every activity change. Tier-1-safe: parent-data reads
  /// and writes only, plus the stitch paint translation and the edge
  /// transform, both folded into the paint top.
  void _resolveRowChromeFrame() {
    final extent = _effectiveFloatingHeaderHeight();
    final stitching = _animator.farAnimateActive && _animator.farAnimateJumped;
    final edge = _edgeTransform;
    for (final child in _children.values) {
      final pd = _parentData(child);
      final top = pd.offset + (stitching ? _stitchPaintDy(pd.id) : 0.0);
      pd.paintTop = switch (edge) {
        null => top,
        final edge => MatrixUtils.transformPoint(edge, Offset(0, top)).dy,
      };
    }
    final restTop = _floatingHeaderController.placeHeaderOffset(
      topPad: _topPad,
      oldestPaintTop: _oldestBoundaryPaintTop(),
    );

    final ChatFloatingHeaderZone zone;
    if (extent > 0) {
      double? leading;
      final above = restTop - extent;
      for (final child in _children.values) {
        final pd = _parentData(child);
        if (!pd.startsDay) continue;
        final top = pd.paintTop;
        if (top > above && (leading == null || top < leading)) leading = top;
      }
      _headerEffect = _dayHeaderDelegate.resolveFloatingHeader(
        ChatDayHeaderMetrics(
          restTop: restTop,
          extent: extent,
          leadingSeparatorTop: leading,
          activity: _activity?.value ?? 1.0,
        ),
      );
      zone = ChatFloatingHeaderZone(
        restTop: restTop,
        extent: extent,
        offset: _headerEffect.offset,
        opacity: _headerEffect.opacity,
      );
    } else {
      _headerEffect = const ChatFloatingHeaderEffect(opacity: 0);
      zone = ChatFloatingHeaderZone.none;
    }
    _activity?.pinned = _headerEffect.holdsActivity;
    final activity = _activity?.value ?? 1.0;
    if (_floatingHeader case final header?) {
      _parentData(header).offset = restTop + _headerEffect.offset;
    }
    for (final child in _children.values) {
      _parentData(child)
        ..headerZone = zone
        ..scrollActivity = activity;
    }
  }

  /// Floating header height for the header zone — zero when the floating
  /// header is suppressed (short content / top overscroll above oldest).
  double _effectiveFloatingHeaderHeight() {
    if (!_shouldShowFloatingHeader()) return 0;
    return _floatingHeaderController.floatingHeaderHeight(_floatingHeader);
  }

  /// Top viewport-Y of [oldestKnownId], or `null` when not built.
  double? _oldestBoundaryTop() {
    final oldest = _dataSource.oldestKnownId;
    if (oldest == null) return null;
    final first = _boundaryBox(oldest);
    if (first == null) return null;
    return _parentData(first).offset;
  }

  /// Painted top of the oldest message row once the oldest message is
  /// reached, or `null` when it is not reached or the row is not built.
  double? _oldestBoundaryPaintTop() {
    if (!_dataSource.reachedOldest) return null;
    final oldest = _dataSource.oldestKnownId;
    if (oldest == null) return null;
    final row = _children[oldest];
    if (row == null) return null;
    return _parentData(row).paintTop;
  }

  bool _shouldShowFloatingHeader() {
    if (_groupBy == null || _overlayKind != ChatOverlayKind.none) {
      return false;
    }
    return _floatingHeaderController.shouldShowFloatingHeader(
      reachedOldest: _dataSource.reachedOldest,
      oldestTop: _oldestBoundaryTop(),
      topPad: _topPad,
      floatingHeaderHeight: _floatingHeaderController.floatingHeaderHeight(
        _floatingHeader,
      ),
    );
  }

  void _clearFloatingHeaderWhenHidden() {
    if (_shouldShowFloatingHeader()) return;
    if (_floatingHeader == null &&
        _floatingHeaderController.headerBucket == null) {
      return;
    }
    _invokeChildManagerLayout(() {
      childManager!.buildFloatingHeader(null, null);
    });
    _floatingHeaderController
      ..headerBucket = null
      ..headerDate = null
      ..headerDirty = true;
  }

  TopDayScan _scanTopDay() => _floatingHeaderController.scanTopDay(
    children: _children.entries,
    topPad: _topPad,
    viewportHeight: size.height,
    // During stitch, paint translation (not layout offset) is what crosses the
    // viewport top — floating date / day scan must follow paint Y.
    offsetOf: (child) {
      final pd = _parentData(child);
      return pd.offset + _stitchPaintDyIfActive(pd.id);
    },
    dayBucketOf: (child) => _parentData(child).dayBucket,
    heightOf: (child) => child.size.height,
  );

  /// Rebuild (only on a group change) and lay out the floating header.
  /// Called from [performLayout]; [_resolveRowChromeFrame] places it. Widget
  /// inflation stays in the render object via [invokeLayoutCallback];
  /// bucket/date logic is on the controller.
  void _updateFloatingHeader() {
    if (!_shouldShowFloatingHeader()) {
      _clearFloatingHeaderWhenHidden();
      return;
    }
    final scan = _scanTopDay();
    final result = _floatingHeaderController.evaluateLayoutRebuild(
      scan: scan,
      groupBy: _groupBy,
      createdAtOf: (id) => _dataSource.getMessage(id)?.createdAt,
    );

    if (result.needsRebuild) {
      _invokeChildManagerLayout(() {
        childManager!.buildFloatingHeader(
          result.bucket,
          result.firstMessageDate,
        );
      });
    }

    final header = _floatingHeader;
    if (header == null) return;
    header.layout(
      BoxConstraints.tightFor(width: size.width),
      parentUsesSize: true,
    );
  }

  /// During a Tier-1 scroll: report whether the topmost day changed — the
  /// caller then relayouts to rebuild the header text.
  bool _tickFloatingHeader() {
    if (_groupBy == null) return false;
    if (!_shouldShowFloatingHeader()) {
      return _floatingHeader != null;
    }
    if (_floatingHeader == null) return true;
    return _floatingHeaderController.tickForDayChange(
      scan: _scanTopDay(),
      groupBy: _groupBy,
      hasFloatingHeader: _floatingHeader != null,
    );
  }

  // --- Scroll ----------------------------------------------------------------

  void _markScrollActive() =>
      _chunkFetchScheduler.markScrollActive(velocity: _scrollVelocity);

  void _ensureTicker() {
    final ticker = _ticker;
    if (ticker != null && !ticker.isActive) ticker.start();
  }

  void _stopTickerIfIdle() {
    _releaseActivityIfSettled();
    if (!_motion.fling.isFlinging &&
        _pendingScrollDelta == 0.0 &&
        _animator.highlightTargetId == null &&
        !_animator.isAnimating &&
        !_motion.edge.isActive &&
        !_dragInProgress &&
        !_spanAutoScrollOccupying) {
      _ticker?.stop();
      // Scroll ended — drop the directional lead so the next layout re-fans
      // a symmetric range and collects the now-unneeded lead children.
      if (_scrollVelocity != 0.0) {
        _scrollVelocity = 0.0;
        markNeedsLayout();
      }
    }
  }

  void _startFling(double velocity) {
    // Cancel first so a re-armed fling emits ChatFlingEnd before ChatFlingStart.
    _cancelFling();
    _motion.fling.startFling(velocity);
    _ensureTicker();
    _controller.notifyScrollEvent(ChatFlingStart(velocity));
  }

  /// Clears fling simulation and emits [ChatFlingEnd] when a fling was active.
  void _cancelFling() {
    final wasFlinging = _motion.fling.isFlinging;
    _motion.fling.cancelFling();
    if (wasFlinging) _controller.notifyScrollEvent(const ChatFlingEnd());
  }

  void _clearHighlight({bool animated = false}) =>
      _animator.clearHighlight(animated: animated);

  /// Drag and [ChatScrollController.scrollBy] cancel attention the same way:
  /// drop the controller slot so a later-built row cannot late-arm, fade an
  /// armed wash, hard-clear pending. Does not run on render detach — that
  /// path keeps the slot so a same-controller remount can replay the request.
  void _cancelHighlightForPan() {
    _controller.dropHighlightRequest();
    if (_animator.highlightTargetId != null) {
      _clearHighlight(animated: true);
    } else {
      _clearHighlight();
    }
  }

  void _cancelAnimate({bool fadeHighlight = true}) {
    _animator.cancelAnimate(fadeHighlight: fadeHighlight);
  }

  /// Anchor-relative Y offset of message [id] in the currently-laid-out
  /// children, or `null` if [id] is not in `_children`.
  double? _offsetToBuiltMessage(int id) {
    final child = _children[id];
    if (child == null) return null;
    return _parentData(child).offset;
  }

  /// Whether built [id] intersects the paint viewport (band-hit diagnostic).
  bool _messageIntersectsPaintBand(int id) {
    final child = _children[id];
    if (child == null || !hasSize) return false;
    final top = _parentData(child).offset;
    final bottom = top + child.size.height;
    return bottom > 0 && top < size.height;
  }

  /// Ticker callback — the entire scroll path. Bypasses layout: repositions
  /// children and calls [markNeedsPaint] (Tier 1). Falls back to
  /// [markNeedsLayout] only when the built range no longer covers the viewport.
  void _onTick(Duration elapsed) {
    final lastElapsed = _lastTickElapsed;
    _lastTickElapsed = elapsed;
    // Overlay mode owns the viewport — no scroll, no fling, no animate. A
    // ticker that survives the transition (or a stray re-arm) must not
    // mutate the anchor while no children are positioned.
    if (_overlayKind != ChatOverlayKind.none) {
      _pendingScrollDelta = 0.0;
      _cancelFling();
      _cancelAnimate(fadeHighlight: false);
      _controller.dropHighlightRequest();
      _clearHighlight();
      _cancelOverscroll();
      _dragInProgress = false;
      _ticker?.stop();
      return;
    }

    // Skip the scroll path entirely on highlight-only frames so the fetch
    // poll's debounce isn't constantly reset by `_markScrollActive`.
    final occupyingSpanAutoScroll = _spanAutoScrollOccupying;
    final fling = _motion.fling;
    final edge = _motion.edge;
    final hasScrollWork =
        _pendingScrollDelta != 0.0 ||
        fling.isFlinging ||
        (!occupyingSpanAutoScroll && _animator.isAnimating) ||
        edge.isActive ||
        occupyingSpanAutoScroll;
    if (!hasScrollWork) {
      // Highlight-only frame: advance the fade and bail.
      if (_animator.tickHighlight(elapsed)) markNeedsPaint();
      _releaseActivityIfSettled();
      if (_animator.highlightTargetId == null) _stopTickerIfIdle();
      return;
    }

    _markScrollActive();
    // Drag / wheel accumulate into `_pendingScrollDelta`. Only that plus fling
    // ticks are user-driven for [ChatViewportScrolled] — animate and span
    // auto-scroll are excluded.
    var userDelta = _pendingScrollDelta;
    _pendingScrollDelta = 0.0;

    if (_contentFitsInViewport()) {
      _cancelFling();
    }

    final wasFlinging = fling.isFlinging;
    final flingDelta = fling.tickFling(elapsed);
    final flingVelocity = wasFlinging ? fling.flingVelocity(elapsed) : 0.0;
    userDelta += flingDelta;
    if (wasFlinging && !fling.isFlinging) {
      _controller.notifyScrollEvent(const ChatFlingEnd());
    }
    var delta = userDelta;
    var animateDelta = 0.0;
    if (occupyingSpanAutoScroll) {
      _cancelAnimate();
    } else {
      animateDelta = _animator.tickAnimate(elapsed);
      delta += animateDelta;
    }
    delta += _spanAutoScrollDelta(elapsed, lastElapsed);

    if (userDelta != 0.0) {
      _controller.notifyScrollEvent(ChatViewportScrolled(userDelta));
    }
    // A fling released toward content unwinds the edge effect before it
    // moves content, the same as a reverse drag.
    if ((_dragInProgress || wasFlinging) && delta != 0.0 && hasSize) {
      delta = edge.claim(
        delta,
        size.height,
        travel: delta.abs() - _unconsumedOverscrollDelta(delta).abs(),
      );
    }
    final unconsumed = _unconsumedOverscrollDelta(delta);
    final consumed = delta - unconsumed;
    if (consumed != 0.0) {
      _controller.applyScrollDelta(consumed);
      _activity?.hold(navigation: userDelta == 0.0 && animateDelta != 0.0);
    }
    _scrollVelocity = _scrollVelocity * 0.7 + consumed * 0.3;
    _repositionFromAnchor();
    if (occupyingSpanAutoScroll) _applyLiveSpanHit();
    if (!_skipRenormalizeDuringClosePath()) {
      _renormalizeAnchor();
    }
    final hitBoundary = _clampBoundaries();
    // Sub-pixel remainders at a pin are rounding, not a press past the edge.
    const edgePx = 1.0;
    if (unconsumed.abs() > edgePx) {
      if (_dragInProgress) {
        if (hasSize) {
          edge.pull(
            unconsumed,
            size.height,
            travel: delta.abs() - unconsumed.abs(),
            fits: _contentFitsInViewport(),
          );
        }
      } else if (wasFlinging) {
        // Fling hit a reached edge — including the frame that consumed the
        // last travel pixels. Leftover velocity goes to the edge effect.
        edge.absorbImpact(unconsumed.sign * flingVelocity.abs());
      }
    }
    if (hitBoundary || unconsumed.abs() > 0.5) {
      _cancelFling();
      if (!_animator.farAnimateActive) {
        _cancelAnimate();
      }
    }
    // An edge effect left displaced with no drag, no fling carrying it, and
    // no catching press holding it — a released fling that never started,
    // was cancelled, or died mid-unwind — releases where it is.
    if (!_dragInProgress &&
        !fling.isFlinging &&
        _flingCancelPointer == null &&
        edge.isActive &&
        !edge.isSpringing) {
      edge.onDragEnd(0);
    }
    if (edge.tick(elapsed) || edge.isActive) {
      markNeedsPaint();
    }
    _updateScrollSemantics();
    _publishControllerState();
    // A day crossing needs a relayout to rebuild the header text. Header
    // placement and row chrome inputs follow paint Y (Tier-1), including
    // stitch dual-translate progress.
    final headerDayChanged = _tickFloatingHeader();
    _resolveRowChromeFrame();

    // The highlight runs alongside scroll/animate frames — advance it on
    // every tick where the scroll path also ran.
    _animator.tickHighlight(elapsed);

    // Arm a deferred highlight as soon as the target row is built — do not
    // wait for another layout pass when data was already ready at settle.
    if (_animator.pendingHighlightTargetId != null) {
      _animator.tryArmPendingHighlight();
    }

    if (_animator.takePendingSettleTargetId() case final targetId?) {
      _onAnimateSettled(targetId);
    }

    // Far-path stitch intentionally keeps a short dual-translate strip
    // (target + outgoing pins). [_rangeNoLongerCovers] would see that as a
    // hole toward oldest/newest and request layout every ticker frame —
    // layout.jump spam / jank until settle. Paint-only until stitch ends.
    final stitchMeasuredFlight =
        _animator.farAnimateActive && _animator.stitchMeasured;
    final coverageNeedsLayout =
        !_animator.farAnimateActive && _rangeNoLongerCovers();
    if (stitchMeasuredFlight) {
      if (headerDayChanged) {
        markNeedsLayout();
      } else {
        markNeedsPaint();
      }
    } else if (coverageNeedsLayout || headerDayChanged) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }

    _releaseActivityIfSettled();
    if (!fling.isFlinging &&
        !_animator.isAnimating &&
        _animator.highlightTargetId == null &&
        !edge.isActive &&
        !_dragInProgress) {
      _stopTickerIfIdle();
    }
  }

  /// Whether the built child range no longer covers viewport + cache extent.
  /// Considers both message tiles and chunk-error tiles — the latter may be
  /// the outermost build at a boundary (e.g. the anchor's chunk errored).
  bool _rangeNoLongerCovers() {
    // Tier-1 hot path: the inline walk below allocates no closures and uses
    // the same min/max accumulation that the original (messages-only)
    // implementation did.
    final hasMessages = _children.isNotEmpty;
    final hasErrors = _chunkErrors.isNotEmpty;
    if (!hasMessages && !hasErrors) return true;

    var topY = double.infinity;
    var bottomY = double.negativeInfinity;
    var firstId = 1 << 62;
    var lastId = -(1 << 62);

    if (hasMessages) {
      // Sorted by id — the outermost id bounds are the first and last keys.
      // Offsets must still be scanned in full because mid-range entries can
      // dictate top/bottom when the directional lead biased the fan-out.
      final fk = _children.firstKey()!;
      final lk = _children.lastKey()!;
      if (fk < firstId) firstId = fk;
      if (lk > lastId) lastId = lk;
      for (final box in _children.values) {
        final pd = _parentData(box);
        if (pd.offset < topY) topY = pd.offset;
        final b = pd.offset + box.size.height;
        if (b > bottomY) bottomY = b;
      }
    }
    if (hasErrors) {
      final fc = _chunkErrors.firstKey()!;
      final lc = _chunkErrors.lastKey()!;
      final eFirst = ChatScrollChunk.firstIdOf(fc);
      final eLast = ChatScrollChunk.firstIdOf(lc + 1) - 1;
      if (eFirst < firstId) firstId = eFirst;
      if (eLast > lastId) lastId = eLast;
      for (final box in _chunkErrors.values) {
        final pd = _parentData(box);
        if (pd.offset < topY) topY = pd.offset;
        final b = pd.offset + box.size.height;
        if (b > bottomY) bottomY = b;
      }
    }

    if (topY > size.height || bottomY < 0) return true;

    if (bottomY < size.height + _cacheExtent) {
      final newest = _dataSource.newestKnownId;
      if (newest == null || lastId < newest) return true;
    }
    if (topY > -_cacheExtent) {
      if (!_dataSource.reachedOldest) {
        if (firstId > 0) return true;
      } else {
        final oldest = _dataSource.oldestKnownId;
        if (oldest == null || firstId > oldest) return true;
      }
    }
    return false;
  }

  // --- Gestures --------------------------------------------------------------

  void _onDragStart(DragStartDetails details) {
    // User takes control — attach/jump pending settle and a held placement
    // must not compete.
    _cancelPendingTailPin();
    _controller.releaseNavigationPlacement();
    _cancelFling();
    // Drag takes over: cancel flight without a second highlight policy,
    // then pan-clear (armed fades; pending hard-clears with the slot).
    _cancelAnimate(fadeHighlight: false);
    _cancelHighlightForPan();
    _motion.edge.onDragStart();
    _dragInProgress = true;
    _ensureTicker();
    _controller.notifyScrollEvent(const ChatUserDragStart());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _markScrollActive();
    _pendingScrollDelta += details.delta.dy;
    _ensureTicker();
  }

  void _onDragEnd(DragEndDetails details) {
    _dragInProgress = false;
    final velocity = details.primaryVelocity ?? 0.0;
    _controller.notifyScrollEvent(ChatUserDragEnd(velocity));
    final edge = _motion.edge;
    final flingAllowed = edge.onDragEnd(velocity);
    if (edge.isActive) _ensureTicker();
    if (flingAllowed &&
        !_contentFitsInViewport() &&
        velocity.abs() >= _minFlingVelocity) {
      _startFling(velocity);
    } else if (!edge.isActive) {
      _stopTickerIfIdle();
    }
  }

  /// Release velocity (px/s) below which no content fling starts.
  static const double _minFlingVelocity = 50;

  /// Drop the edge effect to rest immediately (jump, scroll-by, animate,
  /// overlay, controller or physics swap, bottom-inset change).
  void _cancelOverscroll() {
    _motion.edge.reset();
  }

  /// Span hit: [local] clamped into the scroll band, then
  /// [_selectionMessageIdAt]. Null over non-message slots (far end freezes).
  /// The pinned floating date header is not a freeze slot — auto-scroll holds
  /// in the top edge band, which is exactly where that header sits.
  ///
  /// When [_spanHitFullRow] is true (auto-scroll apply), any Y on the
  /// message row counts — hit-test the full child rect, not only the bubble
  /// body — so a row is selected as soon as it reaches the inset.
  int? _spanHitAt(Offset local) {
    if (!hasSize) return null;
    if (_overlayKind != ChatOverlayKind.none) return null;
    final minY = _topPad;
    final maxY = math.max(minY, size.height - _bottomPad - 0.001);
    return _selectionMessageIdAt(
      Offset(local.dx, local.dy.clamp(minY, maxY)),
      hitThroughPinnedHeader: true,
      hitFullRow: _spanHitFullRow,
    );
  }

  static const double _spanEdgeBand = ChatSelectionMetrics.autoScrollEdgeBand;

  static const double _spanAutoScrollPixelsPerFrame =
      ChatSelectionMetrics.autoScrollPixelsPerFrame;

  /// Display refresh Hz cached on [attach]; used to scale span auto-scroll.
  double _displayRefreshHz = 60;

  bool get _spanAutoScrollOccupying {
    final pointer = _selectionPointer;
    if (pointer == null || !pointer.isSpanLive) return false;
    final local = pointer.spanPointerLocal;
    if (local == null || !hasSize) return false;
    return _spanEdgeDirection(local) != 0;
  }

  /// `+1` toward older (top band), `-1` toward newer (bottom band), `0` none.
  int _spanEdgeDirection(Offset local) {
    if (local.dy < _topPad + _spanEdgeBand) return 1;
    if (local.dy > size.height - _bottomPad - _spanEdgeBand) return -1;
    return 0;
  }

  void _onSpanSessionChanged() {
    if (_spanAutoScrollOccupying) {
      _cancelFling();
      _cancelAnimate();
      _cancelOverscroll();
      _ensureTicker();
    } else {
      _stopTickerIfIdle();
    }
  }

  double _spanAutoScrollDelta(Duration elapsed, Duration? lastElapsed) {
    if (!_spanAutoScrollOccupying) return 0;
    if (_contentFitsInViewport()) return 0;
    final local = _selectionPointer!.spanPointerLocal!;
    final direction = _spanEdgeDirection(local);
    if (direction == 0) return 0;
    if (_spanAutoScrollBlockedByPin(direction)) return 0;
    if (_selectionPointer!.selectSpanGrowthBlocked(direction)) {
      _selectionPointer!.notifyGrowBlocked();
      return 0;
    }
    if (lastElapsed == null) return 0;
    final dt = ((elapsed - lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.05);
    if (dt <= 0.0) return 0;
    return direction * _spanAutoScrollPixelsPerFrame * _displayRefreshHz * dt;
  }

  /// Hz of the first attached display, or 60 when none is reported.
  static double _readDisplayRefreshHz() {
    for (final view in SchedulerBinding.instance.platformDispatcher.views) {
      final hz = view.display.refreshRate;
      if (hz > 1) return hz;
    }
    return 60;
  }

  bool _spanAutoScrollBlockedByPin(int direction) {
    if (direction > 0) {
      if (!_dataSource.reachedOldest) return false;
      final oldest = _dataSource.oldestKnownId;
      final box = oldest != null ? _boundaryBox(oldest) : null;
      if (box == null) return false;
      return _parentData(box).offset >= -0.5;
    }
    if (direction < 0) {
      if (!_dataSource.reachedNewest) return false;
      final newest = _dataSource.newestKnownId;
      final box = newest != null ? _boundaryBox(newest) : null;
      if (box == null) return false;
      final bottom = _parentData(box).offset + box.size.height;
      return bottom <= size.height - _bottomPad + 0.5;
    }
    return false;
  }

  /// Global bounds of this viewport, or `null` when not laid out / attached.
  @internal
  Rect? get markdownAutoscrollGlobalBounds {
    if (!hasSize || !attached) return null;
    return localToGlobal(Offset.zero) & size;
  }

  /// Content insets where edge bands should start (composer / top chrome).
  @internal
  EdgeInsets get markdownAutoscrollPadding =>
      EdgeInsets.only(top: _topPad, bottom: _bottomPad);

  /// Whether edge motion may still move content for markdown text selection.
  ///
  /// [direction] matches span auto-scroll: `+1` toward older (top band),
  /// `-1` toward newer (bottom band).
  ///
  /// Scroll only while the **text selection subject** cell still sticks past
  /// the pad and the conversation pin still has travel. Promoting text →
  /// message selection past flush is a separate follow-on.
  @internal
  bool canMarkdownEdgeAutoscroll(int direction) {
    if (direction == 0) return false;
    if (_contentFitsInViewport()) return false;
    if (_spanAutoScrollBlockedByPin(direction)) return false;
    return !_markdownSubjectFlushWithPad(direction);
  }

  /// Applies a **screen-space** selection autoscroll delta.
  ///
  /// Positive [delta] moves content up (reveal newer). Returns the screen-
  /// space amount applied, or `0` when the subject / pin gate blocks motion
  /// (caller should disarm that direction). Clamps so a frame cannot carry
  /// the subject past flush with the pad.
  @internal
  double applyMarkdownAutoscrollDelta(double delta) {
    if (delta.abs() < 0.5) return 0;
    final direction = delta > 0 ? -1 : 1;
    if (!canMarkdownEdgeAutoscroll(direction)) return 0;

    final room = _markdownSubjectScrollRoom(direction);
    if (room != null && room <= 0.5) return 0;
    final want = delta.abs();
    final appliedMag = room == null ? want : math.min(want, room);
    if (appliedMag < 0.5) return 0;

    // Screen + = reveal newer = anchor-relative scrollBy negative.
    final screenApplied = delta > 0 ? appliedMag : -appliedMag;
    _controller.scrollBy(-screenApplied);
    return screenApplied;
  }

  /// True when the text-selection subject row is already flush with the pad
  /// in [direction] (nothing left to reveal of that message).
  bool _markdownSubjectFlushWithPad(int direction) {
    final room = _markdownSubjectScrollRoom(direction);
    return room != null && room <= 0.5;
  }

  /// Remaining viewport travel that still exposes more of the subject cell
  /// past the pad in [direction], or null when there is no subject / box.
  double? _markdownSubjectScrollRoom(int direction) {
    final subjectId = _selectionController?.textSelectionSubject;
    if (subjectId == null) return null;
    final box = _boundaryBox(subjectId);
    if (box == null) return null;
    final top = _parentData(box).offset;
    final bottom = top + box.size.height;
    if (direction > 0) {
      // Toward older: subject must still sit above the top pad.
      return _topPad - top;
    }
    // Toward newer: subject must still sit below the bottom pad.
    return bottom - (size.height - _bottomPad);
  }

  void _applyLiveSpanHit() {
    final pointer = _selectionPointer;
    final local = pointer?.spanPointerLocal;
    if (pointer == null || !pointer.isSpanLive || local == null) return;
    if (!hasSize) return;
    final direction = _spanEdgeDirection(local);
    // During edge auto-scroll, hit-test at the content inset (not the finger):
    // select a row as soon as it reaches the pad, even if the pointer sits in
    // overlay chrome — faster than waiting for the bubble to clear the bars.
    final y = direction > 0
        ? _topPad
        : math.max(_topPad, size.height - _bottomPad - 0.001);
    _spanHitFullRow = true;
    try {
      pointer.applySpanAt(Offset(local.dx, y));
    } finally {
      _spanHitFullRow = false;
    }
  }

  /// When true, [_spanHitAt] treats the whole message row as a hit.
  bool _spanHitFullRow = false;

  /// Loaded present ids from [origin] to [hit] inclusive. Walks present
  /// neighbors, skipping absent, shimmer, chunk-error, and selection-
  /// disallowed slots.
  List<int> _selectSpanChain(int origin, int hit) {
    if (origin == hit) return <int>[origin];
    final goingUp = hit > origin;
    final ids = <int>[origin];
    var id = origin;
    for (var n = 0; n < 1 << 16; n++) {
      final next = goingUp
          ? _nextNonAbsentIdDown(id + 1, hit)
          : _nextNonAbsentIdUp(id - 1, hit);
      if (goingUp && next > hit) break;
      if (!goingUp && next < hit) break;
      if (next == id) break;
      id = next;
      if (_dataSource.getMessage(id) != null && _isSelectable(id)) {
        ids.add(id);
      }
      if (id == hit) break;
    }
    return ids;
  }

  bool _isSelectable(int id) => _selectionController?.isSelectable(id) ?? true;

  /// Present loaded message under [local], ignoring selection-allowed.
  int? _presentMessageIdAt(Offset local) =>
      _selectionMessageIdAt(local, requireSelectionAllowed: false);

  /// Builds a [ChatMessageMenuRequest] for [id] at viewport-local [local] and
  /// dispatches it to the host idle-tap callback. Silent when the slot is
  /// missing or has no size.
  void _dispatchIdleMessageTap(int id, Offset local) {
    final callback = _onIdleMessageTap;
    if (callback == null) return;
    final request = _messageMenuRequestAt(id, local);
    if (request == null) return;
    callback(request);
  }

  /// Builds a [ChatMessageMenuRequest] for [id] at viewport-local [local] and
  /// dispatches it to the host secondary-tap callback. Silent when the slot
  /// is missing or has no size.
  void _dispatchSecondaryMessageTap(int id, Offset local) {
    final callback = _onSecondaryMessageTap;
    if (callback == null) return;
    final request = _messageMenuRequestAt(id, local);
    if (request == null) return;
    callback(request);
  }

  /// Slot, surface, and band geometry + viewport-known menu context for [id]
  /// at [local].
  ///
  /// The surface rect and outline come from the host-registered message
  /// surface (null without one); the band is the viewport rect inset by the
  /// top / bottom padding, clamped to zero height when the pads overlap.
  /// Does not clear membership or text selection. Returns null when the
  /// present child is missing or unsized.
  ChatMessageMenuRequest? _messageMenuRequestAt(int id, Offset local) {
    final child = _children[id];
    if (child == null || !child.hasSize) return null;
    final pd = _parentData(child);
    final origin = localToGlobal(Offset(0, pd.offset));
    final slotGlobal = origin & Size(size.width, child.size.height);
    final tapGlobal = localToGlobal(local);
    final bandTop = math.min(_topPad, size.height);
    final bandBottom = math.max(bandTop, size.height - _bottomPad);
    final bandGlobal = Rect.fromPoints(
      localToGlobal(Offset(0, bandTop)),
      localToGlobal(Offset(size.width, bandBottom)),
    );
    final selection = _selectionController;
    final surface = selection?.messageSurfaceGlobal(id);
    final inside = selection?.containsMessageSurface(id, tapGlobal) ?? false;
    final pointState = inside
        ? ChatMessageMenuPointState.inside
        : ChatMessageMenuPointState.outside;
    final ChatMessageMenuMembership membership;
    if (selection == null || !selection.isSelectionMode) {
      membership = ChatMessageMenuMembership.idle;
    } else if (selection.isSelected(id)) {
      membership = ChatMessageMenuMembership.uponSelected;
    } else {
      membership = ChatMessageMenuMembership.elsewhere;
    }
    final hasTextSelection = selection?.hasTextSelectionOnMessage(id) ?? false;
    final overlapsText =
        selection?.textSelectionOverlapsMessage(id, tapGlobal) ?? false;
    final String? selectedTextSnapshot;
    if (!overlapsText) {
      selectedTextSnapshot = null;
    } else {
      // Empty string is a valid snapshot when the live range formats to
      // nothing — still non-null so the request invariant holds.
      selectedTextSnapshot = selection?.textSelectionPlainText() ?? '';
    }
    final inlineHit = inside
        ? selection?.resolveInlineHit(id, tapGlobal)
        : null;
    final selectUpToIds = membership == ChatMessageMenuMembership.elsewhere
        ? _selectUpToIds(id)
        : null;
    return ChatMessageMenuRequest(
      messageId: id,
      slotGlobal: slotGlobal,
      tapGlobal: tapGlobal,
      surfaceGlobal: surface?.rect,
      surfaceShape: surface?.shape,
      bandGlobal: bandGlobal,
      pointState: pointState,
      membership: membership,
      hasTextSelection: hasTextSelection,
      overlapsTextSelection: overlapsText,
      selectedTextSnapshot: selectedTextSnapshot,
      selectUpToIds: selectUpToIds,
      inlineHit: inlineHit,
    );
  }

  /// Inclusive selectable chain from the nearest selected id to [targetId]
  /// when the span fits under [ChatSelectionController.selectionCap].
  List<int>? _selectUpToIds(int targetId) {
    final selection = _selectionController;
    if (selection == null || !selection.isSelectionMode) return null;
    if (selection.isSelected(targetId)) return null;
    final selected = selection.selectedIds;
    if (selected.isEmpty) return null;

    int? nearest;
    var minDiff = 1 << 30;
    for (final id in selected) {
      final diff = (id - targetId).abs();
      if (diff < minDiff) {
        minDiff = diff;
        nearest = id;
      }
    }
    if (nearest == null) return null;

    final chain = _selectSpanChain(nearest, targetId);
    if (chain.isEmpty) return null;
    final cap = selection.selectionCap;
    if (cap != null) {
      final combined = {...selected, ...chain};
      if (combined.length > cap) return null;
    }
    return List<int>.unmodifiable(chain);
  }

  /// Loaded message whose selectable body contains [local], or `null` when
  /// the point is over overlay, chunk-error, shimmer, row chrome, or empty
  /// space. The pinned floating header is ignored by default so tap,
  /// long-press, and a span held in the top edge band hit the message
  /// underneath. Pass [hitThroughPinnedHeader] false only if a caller
  /// must treat the header as a non-hit. Idle tap uses
  /// [requireSelectionAllowed] false so selection-allowed stays a
  /// membership gate only.
  int? _selectionMessageIdAt(
    Offset local, {
    bool hitThroughPinnedHeader = true,
    bool hitFullRow = false,
    bool requireSelectionAllowed = true,
  }) {
    if (!hasSize) return null;
    if (_overlayKind != ChatOverlayKind.none) return null;
    final h = size.height;
    final w = size.width;
    if (local.dx < 0 || local.dx >= w || local.dy < 0 || local.dy >= h) {
      return null;
    }

    final header = _floatingHeader;
    var pinnedHeaderCovers = false;
    if (header != null &&
        _headerEffect.hitTestable &&
        _shouldShowFloatingHeader()) {
      final top = _parentData(header).offset;
      pinnedHeaderCovers =
          local.dy >= top && local.dy < top + header.size.height;
      if (pinnedHeaderCovers && !hitThroughPinnedHeader) {
        return null;
      }
    }

    // Rows are matched in layout space: undo the edge transform the rows
    // are painted under (the header above is outside it).
    final y = switch (_edgeTransform) {
      null => local.dy,
      final edge => MatrixUtils.transformPoint(
        Matrix4.inverted(edge),
        local,
      ).dy,
    };

    for (final child in _chunkErrors.values) {
      final pd = _parentData(child);
      if (pd.offset >= h || pd.offset + child.size.height <= 0) continue;
      if (y >= pd.offset && y < pd.offset + child.size.height) {
        return null;
      }
    }

    for (final entry in _children.entries) {
      final child = entry.value;
      final pd = _parentData(child);
      if (pd.offset >= h || pd.offset + child.size.height <= 0) continue;
      if (y < pd.offset || y >= pd.offset + child.size.height) {
        continue;
      }
      if (_dataSource.getMessage(entry.key) == null) return null;
      if (requireSelectionAllowed && !_isSelectable(entry.key)) {
        return null;
      }
      final inRowChrome = y < pd.offset + pd.messageBodyTop;
      if (inRowChrome && !hitFullRow && !pinnedHeaderCovers) return null;
      return entry.key;
    }
    return null;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    assert(debugHandleEvent(event, entry));

    // Overlay mode: no messages to scroll over. The overlay child handles
    // its own pointers via the normal hit-test path; the viewport itself
    // contributes nothing.
    if (_overlayKind != ChatOverlayKind.none) return;

    // Scrollbar drag in progress — consume move/up/cancel.
    if (_scrollbar.isDragging) {
      if (event is PointerMoveEvent && _scrollbar.ownsPointer(event)) {
        final thumbFraction = _currentScrollbarThumbFraction();
        _jumpToScrollbar(
          _scrollbar.progressFromY(
            event.localPosition.dy,
            size,
            topInset: _topPad,
            bottomInset: _bottomPad,
            thumbFraction: thumbFraction,
          ),
        );
        return;
      }
      if ((event is PointerUpEvent || event is PointerCancelEvent) &&
          _scrollbar.ownsPointer(event)) {
        _scrollbar.endDrag();
        // The thumb's own jumps armed placements; a user scroll leaves none.
        _controller.releaseNavigationPlacement();
        markNeedsPaint();
        return;
      }
    }

    if (event is PointerDownEvent) {
      if (_dataSource.newestKnownId != null &&
          !_contentFitsInViewport() &&
          _scrollbar.tryStartDrag(
            event,
            size,
            _textDirection,
            topInset: _topPad,
            bottomInset: _bottomPad,
          )) {
        _cancelFling();
        _controller.releaseNavigationPlacement();
        markNeedsPaint();
        final thumbFraction = _currentScrollbarThumbFraction();
        _jumpToScrollbar(
          _scrollbar.progressFromY(
            event.localPosition.dy,
            size,
            topInset: _topPad,
            bottomInset: _bottomPad,
            thumbFraction: thumbFraction,
          ),
        );
        return;
      }
      final catchesFling = _motion.fling.isFlinging;
      final catchesSpring = !_dragInProgress && _motion.edge.isSpringing;
      if (catchesFling || catchesSpring) {
        if (catchesFling) {
          _cancelFling();
          _pendingScrollDelta = 0.0;
          _scrollVelocity = 0.0;
        }
        // Freeze the spring where the finger caught it; the matching pointer
        // up (or the drag this press becomes) releases it.
        if (catchesSpring) _motion.edge.onDragStart();
        _controller.flingCancelSuppressesLongPress = true;
        _flingCancelPointer = event.pointer;
      } else if (_flingCancelPointer == null &&
          _controller.flingCancelSuppressesLongPress) {
        // A new pointer without catching motion — drop stale suppression left
        // over from a prior catching tap whose post-frame clear has not run
        // yet.
        _controller.flingCancelSuppressesLongPress = false;
      }
      _selectionPointer?.addPointer(event);
      if (event.kind != PointerDeviceKind.mouse) {
        _drag?.addPointer(event);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_flingCancelPointer == event.pointer) {
        _flingCancelPointer = null;
        // Runs before the drag recognizer sees this pointer up: a press that
        // became a drag is released by `_onDragEnd` instead.
        final edge = _motion.edge;
        if (!_dragInProgress && edge.isActive && !edge.isSpringing) {
          edge.onDragEnd(0);
          _ensureTicker();
        }
        // Tap onTap fires after pointer up; defer clearing so SelectableMessage
        // still sees suppression when the gesture arena resolves the tap.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (attached) {
            _controller.flingCancelSuppressesLongPress = false;
          }
        });
      }
    } else if (event is PointerPanZoomStartEvent) {
      _cancelFling();
      _drag?.addPointerPanZoom(event);
    } else if (event is PointerScrollEvent) {
      // Same user-preemption as drag: pending tail pin and a pending or held
      // jumpTo / jumpToCenterBand placement must not yank wheel deltas back.
      _cancelPendingTailPin();
      _controller.releaseNavigationPlacement();
      _cancelFling();
      _cancelAnimate();
      _markScrollActive();
      _pendingScrollDelta -= event.scrollDelta.dy;
      _ensureTicker();
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Overlay mode: only the overlay child is hit-testable; messages and the
    // floating header are not built.
    final overlay = _overlay;
    if (_overlayKind != ChatOverlayKind.none && overlay != null) {
      return result.addWithPaintOffset(
        offset: Offset(0, _parentData(overlay).offset),
        position: position,
        hitTest: (innerResult, transformed) =>
            overlay.hitTest(innerResult, position: transformed),
      );
    }

    final viewportHeight = size.height;
    // Floating day header: paints on top of every message and chunk-error
    // tile (see `_paintContents`). Hit-test first in the inverse-paint order
    // so a tap target inside the header builder — jump-to-date pill, dismiss
    // affordance, etc. — actually fires instead of falling through to the
    // message under it.
    final header = _floatingHeader;
    if (header != null &&
        _headerEffect.hitTestable &&
        _shouldShowFloatingHeader()) {
      final headerOffset = _parentData(header).offset;
      final headerBottom = headerOffset + header.size.height;
      if (headerOffset < viewportHeight && headerBottom > 0) {
        final hit = result.addWithPaintOffset(
          offset: Offset(0, headerOffset),
          position: position,
          hitTest: (innerResult, transformed) =>
              header.hitTest(innerResult, position: transformed),
        );
        if (hit) return true;
      }
    }
    return switch (_edgeTransform) {
      null => _hitTestMessageLayer(result, position),
      final edge => result.addWithPaintTransform(
        transform: edge,
        position: position,
        hitTest: _hitTestMessageLayer,
      ),
    };
  }

  /// Hit-tests chunk-error tiles and messages at [position] in message-layer
  /// space — viewport-local with the edge transform already undone.
  bool _hitTestMessageLayer(BoxHitTestResult result, Offset position) {
    final viewportHeight = size.height;
    // Mirror paint order: chunk-error tiles paint on top of message tiles
    // (the second paint loop). Hit-test them first so a tap on the Retry
    // button is not absorbed by a co-existing message tile during a
    // chunk's error → valid transition frame.
    for (final child in _chunkErrors.values) {
      final pd = _parentData(child);
      if (pd.offset >= viewportHeight || pd.offset + child.size.height <= 0) {
        continue;
      }
      final hit = result.addWithPaintOffset(
        offset: Offset(0, pd.offset),
        position: position,
        hitTest: (innerResult, transformed) =>
            child.hitTest(innerResult, position: transformed),
      );
      if (hit) return true;
    }
    for (final child in _children.values) {
      final pd = _parentData(child);
      // Only on-screen children are hit-testable — off-screen build-extent
      // children may hold a stale offset.
      if (pd.offset >= viewportHeight || pd.offset + child.size.height <= 0) {
        continue;
      }
      final hit = result.addWithPaintOffset(
        offset: Offset(0, pd.offset),
        position: position,
        hitTest: (innerResult, transformed) =>
            child.hitTest(innerResult, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  // --- Scroll semantics ------------------------------------------------------

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..explicitChildNodes = true
      ..hasImplicitScrolling = true;
    // `scrollUp` semantically means "scroll the container up" — i.e. expose
    // content currently below the viewport. In a chat (`reverse: true`)
    // assistive-tech users typically think of "scroll up" as "look at older
    // history" — older is *above*, so we flip the mapping there.
    if (_reverse) {
      if (_canRevealOlder) config.onScrollUp = _semanticRevealOlder;
      if (_canRevealNewer) config.onScrollDown = _semanticRevealNewer;
    } else {
      if (_canRevealNewer) config.onScrollUp = _semanticRevealNewer;
      if (_canRevealOlder) config.onScrollDown = _semanticRevealOlder;
    }
  }

  // --- Visible range / Center Band publishing ------------------------------

  /// Push the current first/last on-screen ids + anchor id to the controller's
  /// `visibleRange` listenable, the Center Band under the mid-band ray, and
  /// update its `isAtTail` flag. Called after every layout and Tier-1 tick —
  /// O(visible children) of pure parent-data reads.
  ///
  /// When any child offset changed this pass, also asks [ChatScrollElement] to
  /// dispatch a [ScrollUpdateNotification] so ancestor
  /// [ScrollNotificationObserver] listeners (e.g. markdown **text selection
  /// chrome**) can re-anchor without requiring a conventional [Scrollable].
  void _publishControllerState() {
    _publishBoundaries();
    _publishVisibleRange();
    _publishCenterBand();
    _publishNewestHeightSample();
    _publishIsAtTail();
    _dispatchViewportGeometryScrollIfNeeded();
  }

  /// Set when [_setOffset] moves a child; consumed by
  /// [_dispatchViewportGeometryScrollIfNeeded].
  bool _childOffsetsMoved = false;

  void _dispatchViewportGeometryScrollIfNeeded() {
    if (!_childOffsetsMoved) return;
    _childOffsetsMoved = false;
    childManager?.dispatchViewportGeometryScrollNotification();
  }

  /// Record newest row height for next layout's same-id growth detection.
  void _publishNewestHeightSample() {
    final newest = _dataSource.newestKnownId;
    if (newest == null) {
      _lastNewestLaidOutId = null;
      _lastNewestLaidOutHeight = null;
      return;
    }
    final box = _boundaryBox(newest);
    if (box == null) return;
    _lastNewestLaidOutId = newest;
    _lastNewestLaidOutHeight = box.size.height;
  }

  void _publishBoundaries() {
    _controller.oldestKnownId = _dataSource.oldestKnownId;
    _controller.newestKnownId = _dataSource.newestKnownId;
  }

  /// Whether the newest known message is currently pinned to the bottom of
  /// the viewport — the "follow tail" signal. False in overlay mode, when no
  /// newestKnownId / reachedNewest is set, when the newest is not built, or
  /// when the user has scrolled it away from the bottom.
  bool _computeIsAtTail() {
    if (_overlayKind != ChatOverlayKind.none) return false;
    final newest = _dataSource.newestKnownId;
    if (newest == null || !_dataSource.reachedNewest) return false;
    final last = _boundaryBox(newest);
    if (last == null) return false;
    final pd = _parentData(last);
    final bottomEdge = size.height - _bottomPad;
    final bottom = pd.offset + last.size.height;
    // Allow [_tailEdgeSlop] past the band (manual fling residue into the
    // composer pad) so follow-tail still fires — without pin-snapping the
    // user back when they scroll away by a small delta.
    // Overscroll the other way (`bottom < bottomEdge`) still counts —
    // bounceback owns that spring. Matches [_computeCanRevealNewer].
    return bottom <= bottomEdge + _tailEdgeSlop && pd.offset < bottomEdge;
  }

  void _publishIsAtTail() {
    final value = _computeIsAtTail();
    // Snapshot for the *next* performLayout: follow-tail compares
    // "was at tail before" + "newest id advanced since" against the live
    // data-source state. Snapshot fires from both layout and Tier-1 tick
    // paths so the value is always fresh at the start of the next layout.
    //
    // Overlay mode is excluded: `_computeIsAtTail` returns false there
    // even when the user conceptually *was* at the tail, and updating the
    // snapshot to false would lose the follow-tail signal across an
    // overlay → normal transition. Same logic for `_lastSeenNewestId` —
    // if `newestKnownId` is null during initial-loading overlay we
    // shouldn't anchor against that.
    if (_overlayKind == ChatOverlayKind.none) {
      _wasAtTailLastLayout = value;
      _lastSeenNewestId = _dataSource.newestKnownId;
      // Geometry says we are at the tail again (e.g. fling residue within
      // slop) — drop drag preempt so follow-tail / height growth can pin.
      if (value) _userPreemptedTailSettle = false;
    }
    if (_controller.isAtTail.value == value) return;
    _controller.isAtTail = value;
  }

  /// Fraction of exposable height visible inside `[topEdge, bottomEdge)`.
  ///
  /// Denominator is [childHeight] when the message fits in the band, otherwise
  /// the band height — so a tall message that fills the band reports `1.0`.
  static double _visibleFraction(
    double childTop,
    double childBottom,
    double childHeight,
    double topEdge,
    double bottomEdge,
  ) {
    if (childHeight <= 0 || !childHeight.isFinite) return 0;
    final bandHeight = bottomEdge - topEdge;
    if (bandHeight <= 0 || !bandHeight.isFinite) return 0;
    final visibleTop = childTop < topEdge ? topEdge : childTop;
    final visibleBottom = childBottom > bottomEdge ? bottomEdge : childBottom;
    final visibleHeight = visibleBottom > visibleTop
        ? visibleBottom - visibleTop
        : 0.0;
    final denominator = childHeight < bandHeight ? childHeight : bandHeight;
    return (visibleHeight / denominator).clamp(0.0, 1.0);
  }

  static bool _fractionsNearEqual(double a, double b) => (a - b).abs() < 1e-4;

  void _publishVisibleRange() {
    if (_children.isEmpty && _chunkErrors.isEmpty) {
      _controller.visibleRange = null;
      return;
    }
    final topEdge = _topPad;
    final bottomEdge = size.height - _bottomPad;
    final bandHeight = bottomEdge - topEdge;
    int? firstId;
    int? lastId;
    RenderBox? firstIntersectingChild;
    RenderBox? lastIntersectingChild;
    double? firstChildTop;
    double? lastChildTop;
    int? firstBuiltId;
    int? lastBuiltId;
    var anyRowFillsBand = false;
    for (final entry in _children.entries) {
      final child = entry.value;
      final pd = _parentData(child);
      final childTop = pd.offset;
      final childBottom = childTop + child.size.height;
      if (childBottom <= topEdge) continue;
      if (childTop >= bottomEdge) break;
      if (bandHeight > 0 && child.size.height >= bandHeight) {
        anyRowFillsBand = true;
      }
      firstId ??= entry.key;
      firstBuiltId ??= entry.key;
      firstIntersectingChild ??= child;
      firstChildTop ??= childTop;
      lastId = entry.key;
      lastBuiltId = entry.key;
      lastIntersectingChild = child;
      lastChildTop = childTop;
    }
    // Chunk-error tiles count as visible id coverage — their chunks' id range
    // is what the listener (mark-as-read, lazy media) cares about, even when
    // the actual messages are not built. Fractions stay tied to the built
    // intersecting render box above; chunk expansion does not fabricate a
    // per-message fraction for ids that are not laid out.
    RenderBox? chunkIntersectingChild;
    double? chunkChildTop;
    for (final entry in _chunkErrors.entries) {
      final child = entry.value;
      final pd = _parentData(child);
      final childTop = pd.offset;
      final childBottom = childTop + child.size.height;
      if (childBottom <= topEdge || childTop >= bottomEdge) continue;
      chunkIntersectingChild ??= child;
      chunkChildTop ??= childTop;
      final chunkFirst = ChatScrollChunk.firstIdOf(entry.key);
      final chunkLast = chunkFirst + ChatScrollChunk.kSize - 1;
      final priorFirst = firstId;
      final priorLast = lastId;
      firstId = priorFirst == null || chunkFirst < priorFirst
          ? chunkFirst
          : priorFirst;
      lastId = priorLast == null || chunkLast > priorLast
          ? chunkLast
          : priorLast;
    }
    if (firstId == null || lastId == null) {
      _controller.visibleRange = null;
      return;
    }

    var firstVisibleFraction = 0.0;
    var firstRowHeight = 0.0;
    if (firstIntersectingChild != null && firstChildTop != null) {
      final child = firstIntersectingChild;
      firstRowHeight = child.size.height;
      firstVisibleFraction = _visibleFraction(
        firstChildTop,
        firstChildTop + child.size.height,
        child.size.height,
        topEdge,
        bottomEdge,
      );
    } else if (chunkIntersectingChild != null && chunkChildTop != null) {
      final child = chunkIntersectingChild;
      firstRowHeight = child.size.height;
      firstVisibleFraction = _visibleFraction(
        chunkChildTop,
        chunkChildTop + child.size.height,
        child.size.height,
        topEdge,
        bottomEdge,
      );
    }

    var lastVisibleFraction = 0.0;
    var lastFractionHeight = 0.0;
    if (lastIntersectingChild != null && lastChildTop != null) {
      final child = lastIntersectingChild;
      lastFractionHeight = child.size.height;
      lastVisibleFraction = _visibleFraction(
        lastChildTop,
        lastChildTop + child.size.height,
        child.size.height,
        topEdge,
        bottomEdge,
      );
    } else if (chunkIntersectingChild != null && chunkChildTop != null) {
      final child = chunkIntersectingChild;
      lastFractionHeight = child.size.height;
      lastVisibleFraction = _visibleFraction(
        chunkChildTop,
        chunkChildTop + child.size.height,
        child.size.height,
        topEdge,
        bottomEdge,
      );
    }

    final anchorId = _controller.anchorMessageId;
    ChatVisibleRow? anchorNextRow;
    final anchorNextChild = _children[anchorId + 1];
    if (anchorNextChild != null) {
      final pd = _parentData(anchorNextChild);
      final childTop = pd.offset;
      final childBottom = childTop + anchorNextChild.size.height;
      // Populated only when anchor+1 is built and intersects the paint band;
      // anchor id itself comes from [ChatScrollController.anchorMessageId].
      if (childBottom > topEdge && childTop < bottomEdge) {
        final anchorNextHeight = anchorNextChild.size.height;
        anchorNextRow = (
          id: anchorId + 1,
          visibleFraction: _visibleFraction(
            childTop,
            childBottom,
            anchorNextChild.size.height,
            topEdge,
            bottomEdge,
          ),
          height: anchorNextHeight,
        );
      }
    }

    final firstRow = (
      id: firstBuiltId ?? firstId,
      visibleFraction: firstVisibleFraction,
      height: firstRowHeight,
    );
    final lastRow = (
      id: lastBuiltId ?? lastId,
      visibleFraction: lastVisibleFraction,
      height: lastFractionHeight,
    );

    final current = _controller.visibleRange.value;
    if (current != null &&
        current.firstId == firstId &&
        current.lastId == lastId &&
        current.anyRowFillsBand == anyRowFillsBand &&
        current.firstRow.id == firstRow.id &&
        current.lastRow.id == lastRow.id &&
        current.anchorNextRow?.id == anchorNextRow?.id &&
        _fractionsNearEqual(current.paintBandHeight, bandHeight) &&
        _fractionsNearEqual(current.firstRow.height, firstRow.height) &&
        _fractionsNearEqual(current.lastRow.height, lastRow.height) &&
        _fractionsNearEqual(
          current.anchorNextRow?.height ?? 0,
          anchorNextRow?.height ?? 0,
        ) &&
        _fractionsNearEqual(
          current.firstRow.visibleFraction,
          firstRow.visibleFraction,
        ) &&
        _fractionsNearEqual(
          current.lastRow.visibleFraction,
          lastRow.visibleFraction,
        ) &&
        _fractionsNearEqual(
          current.anchorNextRow?.visibleFraction ?? 0,
          anchorNextRow?.visibleFraction ?? 0,
        )) {
      return;
    }
    _controller.visibleRange = (
      firstId: firstId,
      lastId: lastId,
      paintBandHeight: bandHeight,
      anyRowFillsBand: anyRowFillsBand,
      firstRow: firstRow,
      lastRow: lastRow,
      anchorNextRow: anchorNextRow,
    );
  }

  /// Push the Message under the fixed 50% paint-band ray to
  /// [ChatScrollController.centerBand].
  ///
  /// Walks built message rows only (not floating header / chunk-error /
  /// overlay). Hit test is `top <= rayY < bottom`;
  /// [ChatCenterBand.offsetFromMessageTop] is `rayY - top`. Silent no-op when
  /// the snapshot is unchanged within float tolerance.
  void _publishCenterBand() {
    if (_children.isEmpty) {
      _controller.centerBand = null;
      return;
    }
    final topEdge = _topPad;
    final bottomEdge = size.height - _bottomPad;
    final bandHeight = bottomEdge - topEdge;
    if (bandHeight <= 0 || !bandHeight.isFinite) {
      _controller.centerBand = null;
      return;
    }
    final rayY = topEdge + bandHeight * 0.5;
    for (final entry in _children.entries) {
      final child = entry.value;
      final childTop = _parentData(child).offset;
      final childBottom = childTop + child.size.height;
      if (childBottom <= topEdge) continue;
      if (childTop >= bottomEdge) break;
      if (childTop <= rayY && rayY < childBottom) {
        final offset = rayY - childTop;
        final current = _controller.centerBand.value;
        if (current case final c?
            when c.messageId == entry.key &&
                _fractionsNearEqual(c.offsetFromMessageTop, offset)) {
          return;
        }
        _controller.centerBand = ChatCenterBand(
          messageId: entry.key,
          offsetFromMessageTop: offset,
        );
        return;
      }
    }
    _controller.centerBand = null;
  }

  // Note: `visitChildrenForSemantics` is intentionally NOT overridden to filter
  // by on-screen position. The semantic-child set must only change when
  // children are created/collected (both mark semantics dirty); filtering by
  // scroll position would let a child cross the viewport edge during a Tier-1
  // paint-only frame and become a visible semantic node with stale (null)
  // parent data. Off-screen cache-extent children therefore contribute
  // semantics — the same trade-off `ListView`'s cache extent makes.

  void _semanticRevealNewer() => _semanticScroll(-size.height * 0.8);
  void _semanticRevealOlder() => _semanticScroll(size.height * 0.8);

  void _semanticScroll(double delta) {
    _cancelFling();
    _controller.applyScrollDelta(delta);
    markNeedsLayout();
  }

  /// Recompute the scroll-action availability and request a semantics update
  /// only when it actually changed.
  void _updateScrollSemantics() {
    final canOlder = _computeCanRevealOlder();
    final canNewer = _computeCanRevealNewer();
    if (canOlder != _canRevealOlder || canNewer != _canRevealNewer) {
      _canRevealOlder = canOlder;
      _canRevealNewer = canNewer;
      markNeedsSemanticsUpdate();
    }
  }

  bool _computeCanRevealOlder() {
    if (_children.isEmpty && _chunkErrors.isEmpty) return false;
    final oldest = _dataSource.oldestKnownId;
    if (oldest != null && _dataSource.reachedOldest) {
      // `_boundaryBox` mirrors what `_clampBoundaries` pins to, so semantics
      // agree with the clamp — assistive tech does not announce scrollable
      // history that the next layout will bounce back into place.
      final first = _boundaryBox(oldest);
      if (first != null && _parentData(first).offset >= -0.5) return false;
    }
    return true;
  }

  bool _computeCanRevealNewer() {
    if (_children.isEmpty && _chunkErrors.isEmpty) return false;
    final newest = _dataSource.newestKnownId;
    if (newest != null && _dataSource.reachedNewest) {
      final last = _boundaryBox(newest);
      if (last != null &&
          _parentData(last).offset + last.size.height <=
              size.height - _bottomPad + _tailEdgeSlop) {
        return false;
      }
    }
    return true;
  }

  // --- Scrollbar -------------------------------------------------------------

  /// Map a 0..1 scrollbar [progress] to a message id and teleport there.
  void _jumpToScrollbar(double progress) {
    final newest = _dataSource.newestKnownId;
    final oldest = _dataSource.oldestKnownId;
    if (newest == null || oldest == null || newest <= oldest) return;
    final targetId = (oldest + progress * (newest - oldest)).round();
    if (LogCategory.scrollbar.enabled) {
      final current = _computeScrollbarProgress();
      _scrollbarEvent('jump', {
        'dragProgress': LogFormat.f(progress),
        'targetId': targetId,
        'oldest': oldest,
        'newest': newest,
        if (current != null) 'thumbProgress': LogFormat.f(current.progress),
        'anchorId': _controller.anchorMessageId,
      });
    }
    if (targetId != _controller.anchorMessageId) {
      _controller.jumpTo(targetId);
    }
  }

  /// Maps a scroll-band Y coordinate through built rows into a fractional id.
  ///
  /// Stable across anchor renormalization because it uses layout tops, not
  /// [ChatScrollController.anchorPixelOffset].
  double? _fractionalIdAtScrollBandRef(double refY) {
    if (!hasSize || _children.isEmpty) return null;

    for (final entry in _children.entries) {
      final box = entry.value;
      if (!box.hasSize) continue;
      final top = _parentData(box).offset;
      final bottom = top + box.size.height;
      if (top <= refY + 0.5 && bottom > refY - 0.5) {
        final intoRow = ((refY - top) / box.size.height).clamp(0.0, 1.0);
        return entry.key + intoRow;
      }
    }

    int? aboveId;
    double? aboveBottom;
    int? belowId;
    double? belowTop;
    for (final entry in _children.entries) {
      final box = entry.value;
      if (!box.hasSize) continue;
      final top = _parentData(box).offset;
      final bottom = top + box.size.height;
      if (bottom <= refY + 0.5) {
        if (aboveBottom == null || bottom > aboveBottom) {
          aboveBottom = bottom;
          aboveId = entry.key;
        }
      } else if (top >= refY - 0.5) {
        if (belowTop == null || top < belowTop) {
          belowTop = top;
          belowId = entry.key;
        }
      }
    }

    if (aboveId != null &&
        belowId != null &&
        aboveBottom != null &&
        belowTop != null) {
      final gap = belowTop - aboveBottom;
      final t = gap > 0 ? ((refY - aboveBottom) / gap).clamp(0.0, 1.0) : 0.5;
      return aboveId + t * (belowId - aboveId);
    }
    if (aboveId != null) return aboveId + 1.0;
    if (belowId != null) return belowId.toDouble();
    return null;
  }

  /// Built-row height stats for height-weighted scrollbar math.
  ({int minBuilt, int maxBuilt, int count, double totalH, double avgH})?
  _scrollbarBuiltHeightStats() {
    if (_children.isEmpty) return null;
    var minBuilt = _children.keys.first;
    var maxBuilt = minBuilt;
    var totalH = 0.0;
    var count = 0;
    for (final entry in _children.entries) {
      final box = entry.value;
      if (!box.hasSize) continue;
      final id = entry.key;
      if (id < minBuilt) minBuilt = id;
      if (id > maxBuilt) maxBuilt = id;
      totalH += box.size.height;
      count++;
    }
    if (count == 0) return null;
    final idSpan = maxBuilt - minBuilt;
    final avgH = idSpan > 0 ? totalH / (idSpan + 1) : totalH / count;
    return (
      minBuilt: minBuilt,
      maxBuilt: maxBuilt,
      count: count,
      totalH: totalH,
      avgH: avgH,
    );
  }

  /// Pixel distance from the top of the built stack to [refY] along layout.
  double _pixelOffsetIntoBuiltStack(double refY) {
    final sorted = _children.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    var intoBuilt = 0.0;
    for (final entry in sorted) {
      final box = entry.value;
      if (!box.hasSize) continue;
      final top = _parentData(box).offset;
      final bottom = top + box.size.height;
      if (bottom <= refY + 0.5) {
        intoBuilt += box.size.height;
      } else if (top <= refY + 0.5) {
        intoBuilt += refY - top;
        break;
      }
    }
    return intoBuilt;
  }

  /// Estimated document height at [refY] using built average row height.
  ({double heightAtRef, double estimatedExtent, double avgH})?
  _scrollbarHeightAtRef(double refY) {
    final stats = _scrollbarBuiltHeightStats();
    final oldest = _dataSource.oldestKnownId;
    final newest = _dataSource.newestKnownId;
    if (stats == null || oldest == null || newest == null) return null;
    final idCount = newest - oldest + 1;
    if (idCount <= 0) return null;
    final estimatedExtent = idCount * stats.avgH;
    final prefixH = (stats.minBuilt - oldest) * stats.avgH;
    final intoBuilt = _pixelOffsetIntoBuiltStack(refY);
    return (
      heightAtRef: prefixH + intoBuilt,
      estimatedExtent: estimatedExtent,
      avgH: stats.avgH,
    );
  }

  /// Band-edge scrollbar metrics from layout-interpolated fractional ids.
  ///
  /// Shares the same continuous signal as [fractionalId]: local viewport
  /// density (`bandHeight / visibleSpan`) drives extent, height-above, progress,
  /// and thumb fraction — without global [avgH] jumps at layout boundaries.
  ({
    double thumbFraction,
    double heightAtTop,
    double estimatedExtent,
    double progress,
  })?
  _scrollbarBandMetrics({
    required double bandHeight,
    required int oldest,
    required int newest,
    double? topFrac,
    double? bottomFrac,
  }) {
    final idCount = newest - oldest + 1;
    if (idCount <= 0 || bandHeight <= 0) return null;
    if (topFrac == null || bottomFrac == null || bottomFrac <= topFrac) {
      return null;
    }
    final visibleSpan = bottomFrac - topFrac;
    final thumbFraction = (visibleSpan / idCount).clamp(0.0, 1.0);
    if (thumbFraction >= 1.0) {
      return (
        thumbFraction: 1.0,
        heightAtTop: 0.0,
        estimatedExtent: bandHeight,
        progress: 0.0,
      );
    }
    final estimatedExtent = bandHeight / thumbFraction;
    final maxScroll = estimatedExtent - bandHeight;
    final heightAtTop = bandHeight * (topFrac - oldest) / visibleSpan;
    final progress = maxScroll > 0
        ? (heightAtTop / maxScroll).clamp(0.0, 1.0)
        : 0.0;
    return (
      thumbFraction: thumbFraction,
      heightAtTop: heightAtTop,
      estimatedExtent: estimatedExtent,
      progress: progress,
    );
  }

  double? _currentScrollbarThumbFraction() {
    if (!hasSize) return null;
    final bandHeight = size.height - _topPad - _bottomPad;
    if (bandHeight <= 0) return null;
    final oldest = _dataSource.oldestKnownId;
    final newest = _dataSource.newestKnownId;
    if (oldest == null || newest == null) return null;

    final fromBand = _scrollbarBandMetrics(
      bandHeight: bandHeight,
      oldest: oldest,
      newest: newest,
      topFrac: _fractionalIdAtScrollBandRef(_topPad),
      bottomFrac: _fractionalIdAtScrollBandRef(size.height - _bottomPad),
    )?.thumbFraction;
    if (fromBand != null) return fromBand;

    final model = _scrollbarHeightAtRef(_topPad);
    if (model == null || model.estimatedExtent <= 0) return null;
    if (model.estimatedExtent <= bandHeight) return 1;
    return (bandHeight / model.estimatedExtent).clamp(0.0, 1.0);
  }

  /// Intermediate values for scrollbar paint/diagnostics.
  ///
  /// [progress] and [thumbFraction] are derived from band-edge fractional ids
  /// and local viewport density — they track scroll every paint like
  /// [fractionalId]. Global built-span [avgH] extrapolation is retained only
  /// in logs (`heightAtBandTopExtrap`, `estimatedExtentExtrap`) for comparison.
  /// Hard clamps at tail (`1.0`) and oldest head (`0.0`).
  ({
    double progress,
    double thumbFraction,
    double fractionalId,
    double idLinearProgress,
    double legacyProgress,
    double legacyFractionalId,
    double bandRefY,
    double heightAtBandTop,
    double estimatedExtent,
    double avgRowH,
    double slotHeight,
    double anchorY,
    int anchorId,
    double anchorH,
    bool anchorBuilt,
    bool anchorLoaded,
    bool slotHeightIsFallback,
    int oldest,
    int newest,
    int idRange,
  })?
  _computeScrollbarProgress({int? anchorIdOverride, double? anchorYOverride}) {
    final newest = _dataSource.newestKnownId;
    final oldest = _dataSource.oldestKnownId;
    if (newest == null || oldest == null) return null;
    final range = newest - oldest;
    if (range <= 0) return null;

    final anchorId = anchorIdOverride ?? _controller.anchorMessageId;
    final anchor = _children[anchorId];
    final resolved = anchorIdOverride == null ? _resolveAnchorBox() : null;
    final anchorH =
        resolved?.box.size.height ??
        (anchor != null && anchor.hasSize ? anchor.size.height : 0.0);
    final slotHeightIsFallback =
        anchor == null || !anchor.hasSize || anchorH <= 0;
    final slotHeight = slotHeightIsFallback ? 60.0 : anchorH;
    final anchorY = anchorYOverride ?? _controller.anchorPixelOffset;
    final legacyFractionalId = anchorId - anchorY / slotHeight;
    final legacyProgress = ((legacyFractionalId - oldest) / range).clamp(
      0.0,
      1.0,
    );

    final bandRefY = hasSize ? _topPad : 0.0;
    final bandHeight = hasSize ? size.height - _topPad - _bottomPad : 0.0;

    final topFrac = hasSize ? _fractionalIdAtScrollBandRef(_topPad) : null;
    final bottomFrac = hasSize
        ? _fractionalIdAtScrollBandRef(size.height - _bottomPad)
        : null;
    final bandFractionalId = topFrac ?? bottomFrac ?? legacyFractionalId;
    final idLinearProgress = ((bandFractionalId - oldest) / range).clamp(
      0.0,
      1.0,
    );

    final heightModel = hasSize ? _scrollbarHeightAtRef(_topPad) : null;
    final extrapHeightAtBandTop = heightModel?.heightAtRef ?? 0.0;
    final extrapEstimatedExtent = heightModel?.estimatedExtent ?? 0.0;
    final extrapAvgRowH = heightModel?.avgH ?? slotHeight;

    final bandMetrics = hasSize
        ? _scrollbarBandMetrics(
            bandHeight: bandHeight,
            oldest: oldest,
            newest: newest,
            topFrac: topFrac,
            bottomFrac: bottomFrac,
          )
        : null;

    double progress;
    double thumbFraction;
    double heightAtBandTop;
    double estimatedExtent;
    double avgRowH;
    if (_computeIsAtTail()) {
      progress = 1.0;
    } else if (_computeIsAtOldestHead()) {
      progress = 0.0;
    } else if (bandMetrics != null) {
      progress = bandMetrics.progress;
    } else if (heightModel != null && bandHeight > 0) {
      if (extrapEstimatedExtent <= bandHeight) {
        progress = 0.0;
      } else {
        final maxScroll = extrapEstimatedExtent - bandHeight;
        progress = (extrapHeightAtBandTop / maxScroll).clamp(0.0, 1.0);
      }
    } else {
      progress = idLinearProgress;
    }

    if (bandMetrics != null) {
      thumbFraction = bandMetrics.thumbFraction;
      heightAtBandTop = bandMetrics.heightAtTop;
      estimatedExtent = bandMetrics.estimatedExtent;
      avgRowH = extrapAvgRowH;
    } else if (extrapEstimatedExtent <= 0 || bandHeight <= 0) {
      thumbFraction = 1.0;
      heightAtBandTop = extrapHeightAtBandTop;
      estimatedExtent = extrapEstimatedExtent;
      avgRowH = extrapAvgRowH;
    } else if (extrapEstimatedExtent <= bandHeight) {
      thumbFraction = 1.0;
      heightAtBandTop = extrapHeightAtBandTop;
      estimatedExtent = extrapEstimatedExtent;
      avgRowH = extrapAvgRowH;
    } else {
      thumbFraction = (bandHeight / extrapEstimatedExtent).clamp(0.0, 1.0);
      heightAtBandTop = extrapHeightAtBandTop;
      estimatedExtent = extrapEstimatedExtent;
      avgRowH = extrapAvgRowH;
    }

    final fractionalId = _computeIsAtTail()
        ? newest.toDouble()
        : _computeIsAtOldestHead()
        ? oldest.toDouble()
        : bandFractionalId;

    return (
      progress: progress,
      thumbFraction: thumbFraction,
      fractionalId: fractionalId,
      idLinearProgress: idLinearProgress,
      legacyProgress: legacyProgress,
      legacyFractionalId: legacyFractionalId,
      bandRefY: bandRefY,
      heightAtBandTop: heightAtBandTop,
      estimatedExtent: estimatedExtent,
      avgRowH: avgRowH,
      slotHeight: slotHeight,
      anchorY: anchorY,
      anchorId: anchorId,
      anchorH: anchorH,
      anchorBuilt: anchor != null,
      anchorLoaded: _dataSource.getMessage(anchorId) != null,
      slotHeightIsFallback: slotHeightIsFallback,
      oldest: oldest,
      newest: newest,
      idRange: range,
    );
  }

  /// Whether the oldest known message is pinned to the top scroll band edge.
  bool _computeIsAtOldestHead() {
    if (_overlayKind != ChatOverlayKind.none) return false;
    final oldest = _dataSource.oldestKnownId;
    if (oldest == null || !_dataSource.reachedOldest) return false;
    final first = _boundaryBox(oldest);
    if (first == null) return false;
    return _parentData(first).offset >= _topPad - 0.5;
  }

  /// Tail/head layout snapshot for scrollbar diagnostics.
  Map<String, Object?> _scrollbarBoundarySnapshot(int anchorId) {
    if (!hasSize) return const {};
    final bottomEdge = size.height - _bottomPad;
    final newest = _dataSource.newestKnownId;
    final oldest = _dataSource.oldestKnownId;
    final isAtTail = _computeIsAtTail();
    final isAtOldestHead = _computeIsAtOldestHead();
    double? newestTop;
    double? newestBottom;
    double? oldestTop;
    if (newest != null) {
      final last = _boundaryBox(newest);
      if (last != null) {
        newestTop = _parentData(last).offset;
        newestBottom = newestTop + last.size.height;
      }
    }
    if (oldest != null) {
      final first = _boundaryBox(oldest);
      if (first != null) {
        oldestTop = _parentData(first).offset;
      }
    }
    final anchorBox = _children[anchorId];
    final anchorBottom = anchorBox == null
        ? null
        : _parentData(anchorBox).offset + anchorBox.size.height;
    return {
      'isAtTail': isAtTail,
      'isAtOldestHead': isAtOldestHead,
      'topEdge': LogFormat.f(_topPad),
      'bottomEdge': LogFormat.f(bottomEdge),
      'newestTop': newestTop == null ? null : LogFormat.f(newestTop),
      'newestBottom': newestBottom == null ? null : LogFormat.f(newestBottom),
      'oldestTop': oldestTop == null ? null : LogFormat.f(oldestTop),
      'anchorBottom': anchorBottom == null ? null : LogFormat.f(anchorBottom),
      'anchorIsNewest': newest != null && anchorId == newest,
      'anchorIsOldest': oldest != null && anchorId == oldest,
    };
  }

  /// Built-span metrics for comparing id-linear thumb math to layout reality.
  Map<String, Object?> _scrollbarBuiltSpanMetrics(int anchorId) {
    if (_children.isEmpty) {
      return const {'builtCount': 0};
    }
    var minBuilt = anchorId;
    var maxBuilt = anchorId;
    var sumAbove = 0.0;
    var sumBelow = 0.0;
    var totalH = 0.0;
    int? prevId;
    double? prevH;
    int? nextId;
    double? nextH;
    for (final entry in _children.entries) {
      final id = entry.key;
      final h = entry.value.size.height;
      if (id < minBuilt) minBuilt = id;
      if (id > maxBuilt) maxBuilt = id;
      totalH += h;
      if (id < anchorId) {
        sumAbove += h;
        if (prevId == null || id > prevId) {
          prevId = id;
          prevH = h;
        }
      } else if (id > anchorId) {
        sumBelow += h;
        if (nextId == null || id < nextId) {
          nextId = id;
          nextH = h;
        }
      }
    }
    final builtSpan = maxBuilt - minBuilt;
    final progressByBuiltIds = builtSpan > 0
        ? ((anchorId - minBuilt) / builtSpan).clamp(0.0, 1.0)
        : null;
    double? anchorTop;
    final anchorBox = _children[anchorId];
    if (anchorBox != null) {
      anchorTop = _parentData(anchorBox).offset;
    }
    return {
      'builtCount': _children.length,
      'minBuilt': minBuilt,
      'maxBuilt': maxBuilt,
      'builtIdSpan': builtSpan,
      'sumHAbove': LogFormat.f(sumAbove),
      'sumHBelow': LogFormat.f(sumBelow),
      'totalBuiltH': LogFormat.f(totalH),
      'progressByBuiltIds': progressByBuiltIds == null
          ? null
          : LogFormat.f(progressByBuiltIds),
      'prevId': prevId,
      'prevH': prevH == null ? null : LogFormat.f(prevH),
      'nextId': nextId,
      'nextH': nextH == null ? null : LogFormat.f(nextH),
      'anchorTop': anchorTop == null ? null : LogFormat.f(anchorTop),
    };
  }

  Map<String, Object?> _scrollbarProgressFields(
    ({
      double progress,
      double thumbFraction,
      double fractionalId,
      double idLinearProgress,
      double legacyProgress,
      double legacyFractionalId,
      double bandRefY,
      double heightAtBandTop,
      double estimatedExtent,
      double avgRowH,
      double slotHeight,
      double anchorY,
      int anchorId,
      double anchorH,
      bool anchorBuilt,
      bool anchorLoaded,
      bool slotHeightIsFallback,
      int oldest,
      int newest,
      int idRange,
    })
    computed, {
    required String reason,
  }) {
    final offsetAsIdAtSlot = computed.anchorY / computed.slotHeight;
    final offsetAsIdAtAnchorH = computed.anchorH > 0
        ? computed.anchorY / computed.anchorH
        : null;
    final progressAtSlotH =
        ((computed.anchorId -
                    computed.anchorY / computed.slotHeight -
                    computed.oldest) /
                computed.idRange)
            .clamp(0.0, 1.0);
    final progressAtAnchorH = offsetAsIdAtAnchorH == null
        ? null
        : ((computed.anchorId - offsetAsIdAtAnchorH - computed.oldest) /
                  computed.idRange)
              .clamp(0.0, 1.0);
    final boundary = _scrollbarBoundarySnapshot(computed.anchorId);
    final isAtTail = boundary['isAtTail'] == true;
    final tailDeficit = isAtTail ? 1.0 - computed.progress : null;
    final legacyTailDeficit = isAtTail ? 1.0 - computed.legacyProgress : null;
    final isAtOldestHead = boundary['isAtOldestHead'] == true;
    final headSurplus = isAtOldestHead ? computed.progress : null;
    final bandTopFrac = hasSize ? _fractionalIdAtScrollBandRef(_topPad) : null;
    final bandBottomFrac = hasSize
        ? _fractionalIdAtScrollBandRef(size.height - _bottomPad)
        : null;
    final bandHeight = hasSize ? size.height - _topPad - _bottomPad : null;
    final trackHeight = bandHeight != null && bandHeight > 8
        ? bandHeight - 8
        : null;
    final thumbHeightPx = trackHeight != null
        ? _scrollbar.resolveThumbHeight(
            trackHeight,
            thumbFraction: computed.thumbFraction,
          )
        : null;
    final maxScroll =
        bandHeight != null && computed.estimatedExtent > bandHeight
        ? computed.estimatedExtent - bandHeight
        : null;
    final extrapModel = hasSize ? _scrollbarHeightAtRef(_topPad) : null;
    return {
      'reason': reason,
      'progress': LogFormat.ratio(computed.progress),
      'thumbFraction': LogFormat.ratio(computed.thumbFraction),
      if (thumbHeightPx != null) 'thumbHeightPx': LogFormat.f(thumbHeightPx),
      'fractionalId': LogFormat.ratio(computed.fractionalId, decimals: 2),
      'bandRefY': LogFormat.f(computed.bandRefY),
      'heightAtBandTop': LogFormat.f(computed.heightAtBandTop),
      if (extrapModel != null)
        'heightAtBandTopExtrap': LogFormat.f(extrapModel.heightAtRef),
      'estimatedExtent': LogFormat.f(computed.estimatedExtent),
      if (extrapModel != null)
        'estimatedExtentExtrap': LogFormat.f(extrapModel.estimatedExtent),
      'avgRowH': LogFormat.f(computed.avgRowH),
      if (bandHeight != null) 'bandHeight': LogFormat.f(bandHeight),
      if (maxScroll != null) 'maxScroll': LogFormat.f(maxScroll),
      'progressIdLinear': LogFormat.ratio(computed.idLinearProgress),
      if (bandTopFrac != null)
        'fractionalIdTop': LogFormat.ratio(bandTopFrac, decimals: 2),
      if (bandBottomFrac != null)
        'fractionalIdBottom': LogFormat.ratio(bandBottomFrac, decimals: 2),
      if (bandTopFrac != null && bandBottomFrac != null)
        'visibleIdSpan': LogFormat.ratio(
          bandBottomFrac - bandTopFrac,
          decimals: 2,
        ),
      if (hasSize) 'bandBottomRefY': LogFormat.f(size.height - _bottomPad),
      'progressLegacy': LogFormat.ratio(computed.legacyProgress),
      'fractionalIdLegacy': LogFormat.ratio(
        computed.legacyFractionalId,
        decimals: 2,
      ),
      'anchorId': computed.anchorId,
      'anchorY': LogFormat.f(computed.anchorY),
      'anchorH': LogFormat.f(computed.anchorH),
      'slotHeight': LogFormat.f(computed.slotHeight),
      'slotHeightIsFallback': computed.slotHeightIsFallback,
      'anchorBuilt': computed.anchorBuilt,
      'anchorLoaded': computed.anchorLoaded,
      'offsetAsIdAtSlot': LogFormat.f(offsetAsIdAtSlot),
      if (offsetAsIdAtAnchorH != null)
        'offsetAsIdAtAnchorH': LogFormat.f(offsetAsIdAtAnchorH),
      if (progressAtAnchorH != null)
        'progressIfAnchorH': LogFormat.f(progressAtAnchorH),
      'progressAtSlotH': LogFormat.f(progressAtSlotH),
      'progressDeltaVsAnchorH': progressAtAnchorH == null
          ? null
          : LogFormat.f((computed.progress - progressAtAnchorH).abs()),
      'oldest': computed.oldest,
      'newest': computed.newest,
      'idRange': computed.idRange,
      'drag': _scrollbar.isDragging,
      'fling': _motion.fling.isFlinging,
      ...boundary,
      if (tailDeficit != null && tailDeficit > 0.01)
        'tailDeficit': LogFormat.f(tailDeficit),
      if (legacyTailDeficit != null && legacyTailDeficit > 0.01)
        'tailDeficitLegacy': LogFormat.f(legacyTailDeficit),
      if (headSurplus != null && headSurplus > 0.01)
        'headSurplus': LogFormat.f(headSurplus),
      if (isAtTail && computed.legacyProgress < 0.99)
        'hint': 'legacy_anchorY_formula_under_reports_at_tail',
      ..._scrollbarBuiltSpanMetrics(computed.anchorId),
    };
  }

  void _maybeLogScrollbarProgress(
    ({
      double progress,
      double thumbFraction,
      double fractionalId,
      double idLinearProgress,
      double legacyProgress,
      double legacyFractionalId,
      double bandRefY,
      double heightAtBandTop,
      double estimatedExtent,
      double avgRowH,
      double slotHeight,
      double anchorY,
      int anchorId,
      double anchorH,
      bool anchorBuilt,
      bool anchorLoaded,
      bool slotHeightIsFallback,
      int oldest,
      int newest,
      int idRange,
    })
    computed, {
    required String reason,
  }) {
    if (!LogCategory.scrollbar.enabled) return;

    final progressDelta = _scrollbarLogLastProgress == null
        ? double.infinity
        : (computed.progress - _scrollbarLogLastProgress!).abs();
    final anchorHDelta = _scrollbarLogLastAnchorH == null
        ? double.infinity
        : (computed.anchorH - _scrollbarLogLastAnchorH!).abs();
    final anchorIdChanged = computed.anchorId != _scrollbarLogLastAnchorId;
    _scrollbarLogPaintCounter++;
    final periodicWhileScrolling =
        (_motion.fling.isFlinging ||
            _dragInProgress ||
            _scrollbar.isDragging) &&
        _scrollbarLogPaintCounter % 30 == 0;

    final shouldLog =
        _scrollbar.isDragging ||
        anchorIdChanged ||
        anchorHDelta >= 1.0 ||
        progressDelta >= 0.002 ||
        periodicWhileScrolling ||
        reason == 'layout';

    if (!shouldLog) return;

    _scrollbarLogLastAnchorId = computed.anchorId;
    _scrollbarLogLastAnchorH = computed.anchorH;
    _scrollbarLogLastProgress = computed.progress;

    _scrollbarEvent(
      'progress.$reason',
      _scrollbarProgressFields(computed, reason: reason),
    );
  }

  // --- Paint -----------------------------------------------------------------

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(() {
      _debugSw
        ..reset()
        ..start();
      return true;
    }());

    // Reuse the clip layer across repaints — the framework idiom. Even though
    // this object is a repaint boundary (so its layer children are re-added on
    // every repaint), holding the ClipRectLayer in a LayerHandle and passing
    // it back as `oldLayer` keeps a stable layer identity for the engine.
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _paintContents,
      oldLayer: _clipLayer.layer,
    );

    assert(() {
      debugLastPaintDuration = _debugSw.elapsed;
      _debugSw.stop();
      debugPaintFrameId++;
      return true;
    }());
  }

  void _paintContents(PaintingContext context, Offset offset) {
    // Overlay mode: a single full-viewport child takes the place of every
    // message — no scrollbar, no floating header, no per-message cull.
    final overlay = _overlay;
    if (_overlayKind != ChatOverlayKind.none && overlay != null) {
      context.paintChild(
        overlay,
        offset + Offset(0, _parentData(overlay).offset),
      );
      return;
    }

    // The edge effect transforms the message list only. Floating date header
    // and scrollbar paint outside it; the header's rest line already follows
    // the oldest row's paint top (see [_resolveRowChromeFrame]).
    if (_edgeTransform case final edge?) {
      _edgeLayer.layer = context.pushTransform(
        needsCompositing,
        offset,
        edge,
        _paintMessages,
        oldLayer: _edgeLayer.layer,
      );
    } else {
      _edgeLayer.layer = null;
      _paintMessages(context, offset);
    }
    _paintFloatingHeader(context, offset);
    _paintScrollbar(context, offset);
  }

  /// Message-layer transform of the live edge effect, or `null` at rest.
  /// Paint, hit-testing, [applyPaintTransform], and row chrome paint tops
  /// all read this one matrix, so hits never lag what is painted.
  Matrix4? get _edgeTransform =>
      hasSize ? _motion.edge.paintTransform(size) : null;

  void _paintMessages(PaintingContext context, Offset offset) {
    final viewportHeight = size.height;
    // Navigate-select wash under message children (text/bubbles stay crisp).
    _animator.paintHighlight(
      context: context,
      offset: offset,
      viewportWidth: size.width,
      viewportHeight: viewportHeight,
    );
    // Apply stitch translations whenever the jump has happened — including
    // the pre-measure frame (provisional off-screen incoming).
    final stitching = _animator.farAnimateActive && _animator.farAnimateJumped;
    for (final child in _children.values) {
      final pd = _parentData(child);
      final paintY = pd.offset + (stitching ? _stitchPaintDy(pd.id) : 0.0);
      // Cull children fully outside the viewport — off-screen build-extent
      // children stay built but are not composited until they scroll in.
      if (paintY >= viewportHeight || paintY + child.size.height <= 0) {
        continue;
      }
      context.paintChild(child, offset + Offset(0, paintY));
    }
    for (final child in _chunkErrors.values) {
      final pd = _parentData(child);
      if (pd.offset >= viewportHeight || pd.offset + child.size.height <= 0) {
        continue;
      }
      context.paintChild(child, offset + Offset(0, pd.offset));
    }
  }

  void _paintFloatingHeader(PaintingContext context, Offset offset) {
    final header = _floatingHeader;
    if (header == null || !_shouldShowFloatingHeader()) {
      _headerOpacityLayer.layer = null;
      return;
    }
    paintChildWithOpacity(
      context,
      header,
      offset + Offset(0, _parentData(header).offset),
      _headerEffect.opacity,
      _headerOpacityLayer,
    );
  }

  void _paintScrollbar(PaintingContext context, Offset offset) {
    if (_contentFitsInViewport()) return;
    final computed = _computeScrollbarProgress();
    if (computed == null) return;
    _maybeLogScrollbarProgress(computed, reason: 'paint');
    _scrollbar.paint(
      context.canvas,
      offset,
      size,
      computed.progress,
      _textDirection,
      theme: _scrollbarTheme,
      topInset: _topPad,
      bottomInset: _bottomPad,
      thumbFraction: computed.thumbFraction,
    );
  }

  @override
  void dispose() {
    _cancelFling();
    _cancelAnimate(fadeHighlight: false);
    _clearHighlight();
    _ticker?.dispose();
    _ticker = null;
    _chunkFetchScheduler.dispose();
    _drag?.dispose();
    _drag = null;
    _selectionPointer?.dispose();
    _selectionPointer = null;
    _clipLayer.layer = null;
    _edgeLayer.layer = null;
    _headerOpacityLayer.layer = null;
    super.dispose();
  }
}

/// Reading position captured before a row chrome change, held for one
/// layout pass: the anchor it was measured against, the reference row, and
/// that row's bottom edge relative to the anchor top.
///
/// Recorded by [RenderChatScrollView._recordRowChromeReference], consumed by
/// [RenderChatScrollView._holdRowChromeReference].
typedef _RowChromeReference = ({
  int anchorId,
  int referenceId,
  double bottomFromAnchor,
});

/// Layout snapshot taken immediately before absent-anchor reassignment.
///
/// Used by [_preserveViewportAfterDelete] to compute how far to shift scroll so
/// the visible band stays at the same distance from the bottom edge.
class _BeforeDeleteLayoutSnapshot {
  const _BeforeDeleteLayoutSnapshot({
    required this.deletedId,
    required this.deletedHeight,
    required this.anchorYBefore,
    required this.bandIdBefore,
    required this.bandBottomBefore,
    required this.bandGapBefore,
    required this.bottomEdgeBefore,
    required this.userPreemptedTailBefore,
    required this.wasAtTailBefore,
  });

  final int deletedId;
  final double? deletedHeight;
  final double anchorYBefore;
  final int? bandIdBefore;
  final double? bandBottomBefore;
  final double? bandGapBefore;
  final double bottomEdgeBefore;
  final bool userPreemptedTailBefore;
  final bool wasAtTailBefore;
}
