// ignore_for_file: prefer_asserts_with_message

import 'dart:async' show scheduleMicrotask, unawaited;
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_animator.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_chunk_fetch_scheduler.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_floating_header_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_mutations.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_dev_log.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_events.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_physics.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_sender_run_layout.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_data_source_ext.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_element.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_metrics.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_pointer.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:meta/meta.dart' show internal;

/// Parent data for a viewport child.
///
/// For a message: its [id], the [offset] of its top edge within the viewport
/// (viewport-local Y, may be negative), whether it [startsDay] (carries an
/// inline date divider), its [dayBucket] (day-grouping key, `null` until the
/// message loads), and the [dividerOpacity] of its inline date separator. The
/// floating day header reuses this type — only [offset] is meaningful for it.
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

  /// Fade opacity (0..1) for this message's inline date separator — set by
  /// `RenderChatScrollView` from [offset] so the separator fades out as it
  /// rises into the floating day header's zone. Only meaningful when
  /// [startsDay] is `true`; read by `RenderDatedMessage`.
  double dividerOpacity = 1;

  /// Local Y of the message body within this child. `0` when the child is
  /// the body. A dated row writes the inline separator height here during
  /// layout so a long-press on the date chrome does not select.
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

/// Contract the render object uses to lazily inflate / dispose children.
///
/// Implemented by `ChatScrollElement` only. The render object calls the
/// build methods during `performLayout` (wrapped in `invokeLayoutCallback`)
/// and the remove methods to garbage-collect children outside the build
/// range. Public API consumers should never implement or call this directly.
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
    ChatSenderRunLayout senderRunLayout = DefaultChatSenderRunLayout.instance,
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
    void Function(int id, Rect slotGlobal, Offset tapGlobal)? onIdleMessageTap,
    bool Function(IChatMessage message)? isSelfMessage,
  }) : _dataSource = dataSource,
       _controller = controller,
       _selectionController = selectionController,
       _onIdleMessageTap = onIdleMessageTap,
       _isSelfMessage = isSelfMessage,
       _cacheExtent = cacheExtent,
       _extraBuildExtent = extraBuildExtent,
       _ticking = ticking,
       _reverse = reverse,
       _bottomPadding = bottomPadding,
       _topPadding = topPadding,
       _groupBy = groupBy,
       _senderRunLayout = senderRunLayout,
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
      cancelBounceback: _cancelBounceback,
      prepareStitchCapture: _prepareStitchCapture,
      clearStitchCapture: _clearStitchCapture,
      highlightColor: highlightColor,
      highlightDuration: highlightDuration,
    );
  }

  /// Chunk-load / anchor-persistence diagnostics — filter `ChatScrollFetchAnchor`.
  final ChatScrollDevLog _fetchAnchorLog = ChatScrollDevLog(
    'ChatScrollFetchAnchor',
    enabled: false,
  );

  /// Scrollbar thumb / id-linear progress diagnostics — filter
  /// `ChatScrollScrollbar`. Set [ChatScrollDevLog.enabled] to `true` while
  /// investigating thumb jumps, stale position, or height-change drift.
  final ChatScrollDevLog _scrollbarLog = ChatScrollDevLog(
    'ChatScrollScrollbar',
    enabled: false,
  );

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
      _cancelBounceback();
      // Clear any leftover navigate highlight — its target id refers
      // to a message position resolved against the old controller's anchor;
      // painting it under the new controller would tint an arbitrary row.
      _clearHighlight();
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

  void Function(int id, Rect slotGlobal, Offset tapGlobal)? _onIdleMessageTap;
  set onIdleMessageTap(
    void Function(int id, Rect slotGlobal, Offset tapGlobal)? value,
  ) {
    if (identical(_onIdleMessageTap, value)) return;
    _onIdleMessageTap = value;
    _selectionPointer?.onIdleMessageTap = value == null
        ? null
        : _dispatchIdleMessageTap;
  }

  /// See [ChatScrollView.isSelfMessage].
  bool Function(IChatMessage message)? _isSelfMessage;
  set isSelfMessage(bool Function(IChatMessage message)? value) {
    if (identical(_isSelfMessage, value)) return;
    _isSelfMessage = value;
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

  /// Host policy for [MessageRunLayout]. See [ChatScrollView.senderRunLayout].
  ChatSenderRunLayout _senderRunLayout;
  set senderRunLayout(ChatSenderRunLayout value) {
    if (_senderRunLayout == value) return;
    _senderRunLayout = value;
    markNeedsLayout();
  }

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

  // --- Ticker / scroll physics ----------------------------------------------

  Ticker? _ticker;
  double _pendingScrollDelta = 0;

  /// Fling simulation, drag resistance, and overscroll bounceback. Boundary
  /// geometry is measured here in the render object and fed back through
  /// [_overscrollOnSide] — [ChatScrollPhysics] owns only the simulation state.
  ///
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

  late final ChatScrollPhysics _physics = ChatScrollPhysics(
    overscrollOnSide: _overscrollOnSide,
  );

  VerticalDragGestureRecognizer? _drag;

  ChatSelectionPointer? _selectionPointer;

  /// Pointer that cancelled an in-flight fling; long-press is suppressed until
  /// this pointer lifts.
  int? _flingCancelPointer;

  // --- Overscroll bounce ---------------------------------------------------
  //
  // Spring-back state lives on [_physics]. This section keeps drag-time
  // behaviour: while [_dragInProgress] the boundary clamp is suspended,
  // overshoot is allowed, and incoming drag delta is scaled by resistance
  // (see [_applyOverscrollResistance]) so the further past the boundary the
  // user pulls, the harder it pushes back.

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
      _animator.log.event('stitch.capture', {
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
    _animator.log.event('stitch.capture', {
      'target': targetId,
      'anchorBefore': _stitchAnchorIdBeforeJump,
      'towardNewer': _stitchTowardNewer,
      'vh': DevLogFormat.f(viewportHeight),
      'outgoingN': _stitchOutgoingIds.length,
      'outgoingIds': DevLogFormat.ids(_stitchOutgoingIds),
      'stripH': DevLogFormat.f(_stitchOutgoingStripBottom()),
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
    _animator.log.event('stitch.measureGeom', {
      'target': _animator.animateTargetId,
      'towardNewer': towardNewer,
      'vh': DevLogFormat.f(viewportHeight),
      'oldT': DevLogFormat.f(oldT),
      'oldH': DevLogFormat.f(oldH),
      'finalH': DevLogFormat.f(finalHeight),
      'hasIncoming': hasIncoming,
      'inTop': hasIncoming ? DevLogFormat.f(incomingTop) : null,
      'inBot': hasIncoming ? DevLogFormat.f(incomingBottom) : null,
      'scrollLen': DevLogFormat.f(travel),
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
    // [navigationAlignment] pending so [performLayout] applies it once the real
    // message is built (same contract as [jumpTo]). [_applyNavigationAlignment]
    // clears when aligned; do not clear here unconditionally — that dropped
    // deferred alignment and regressed post-load landing for non-zero alignment.
    if (_controller.navigationAlignment != 0.0) {
      _applyNavigationAlignment();
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

  /// Whether a floating day header render box is currently attached.
  bool get debugHasFloatingHeader => _floatingHeader != null;

  /// Whether the floating header would be painted this frame (suppressed above
  /// the oldest boundary during short content or top overscroll).
  bool get debugFloatingHeaderVisible =>
      _floatingHeader != null && _shouldShowFloatingHeader();

  /// Viewport-local Y of the floating header's top edge, if built.
  double? get debugFloatingHeaderOffset =>
      _floatingHeader == null ? null : _parentData(_floatingHeader!).offset;

  /// Calendar date shown in the floating header, if any.
  DateTime? get debugHeaderDate => _floatingHeaderController.headerDate;

  /// Debug-only: group bucket the floating header was last built for.
  Object? get debugHeaderBucket => _floatingHeaderController.headerBucket;

  /// Message id currently receiving the post-navigation highlight tint.
  int? get debugHighlightTargetId => _animator.highlightTargetId;

  /// Message id waiting for its chunk to load before the highlight arms.
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

  /// Inline-divider fade opacity (0..1) of the built child [id], or `null`
  /// when [id] is not currently built.
  double? debugDividerOpacity(int id) {
    final child = _children[id];
    return child == null ? null : _parentData(child).dividerOpacity;
  }

  /// Whether the built child [id] carries an inline day separator, or `false`
  /// when [id] is not currently built.
  bool debugStartsDay(int id) {
    final child = _children[id];
    return child != null && _parentData(child).startsDay;
  }

  void _fetchAnchorEvent(String tag, Map<String, Object?> fields) {
    _fetchAnchorLog.event(tag, fields);
  }

  void _scrollbarEvent(String tag, Map<String, Object?> fields) {
    _scrollbarLog.event(tag, fields);
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
      'layout': _fetchAnchorLog.layoutFrame,
      'anchorId': anchorId,
      'anchorY': DevLogFormat.f(anchorY),
      'anchorFetching': anchorStatus.isFetching,
      'anchorAbsent': anchorStatus.isAbsent,
      'anchorDirty': anchorStatus.isDirty,
      'anchorLoaded': _dataSource.getMessage(anchorId) != null,
      'anchorTop': anchorTop == null ? null : DevLogFormat.f(anchorTop),
      'anchorBottom': anchorBottom == null
          ? null
          : DevLogFormat.f(anchorBottom),
      'anchorH': anchorH == null ? null : DevLogFormat.f(anchorH),
      'bottomEdge': bottomEdge == null ? null : DevLogFormat.f(bottomEdge),
      'bandId': band?.id,
      'bandTop': band == null ? null : DevLogFormat.f(band.top),
      'bandBottom': band == null ? null : DevLogFormat.f(band.bottom),
      'bandGap': band == null ? null : DevLogFormat.f(band.gapToBottomEdge),
      'bandFullyAboveInset':
          band != null && bottomEdge != null && band.bottom <= bottomEdge + 0.5,
      'isAtTail': hasSize ? _computeIsAtTail() : null,
      'wasAtTail': _wasAtTailLastLayout,
      'pendingTailPin': _pendingTailPinUntilSettled,
      'userPreemptedTail': _userPreemptedTailSettle,
      'drag': _dragInProgress,
      'fling': _physics.isFlinging,
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
          : _dispatchIdleMessageTap;
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
      VerticalDragGestureRecognizer()
        ..onStart = _onDragStart
        ..onUpdate = _onDragUpdate
        ..onEnd = _onDragEnd;

  @override
  void detach() {
    _cancelFling();
    _controller.flingCancelSuppressesLongPress = false;
    _flingCancelPointer = null;
    _ticker?.dispose();
    _ticker = null;
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
      ..isAtTail = false;
    _cancelAnimate();
    _bottomPadding?.removeListener(_onBottomPaddingChanged);
    _topPadding?.removeListener(_onTopPaddingChanged);
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

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    final pd = child.parentData! as ChatMessageParentData;
    transform.translateByDouble(0, pd.offset, 0, 1);
  }

  // --- Typed listeners -------------------------------------------------------

  void _onDataChanged() {
    _abortSpanIfOriginAbsent();
    _fetchAnchorEvent('fetch.data', {
      ..._fetchAnchorSnapshot(),
      'fetchingChunks': DevLogFormat.ids(_fetchingChunkIndices(), max: 8),
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
      'prev': DevLogFormat.f(previous),
      'current': DevLogFormat.f(current),
      'delta': DevLogFormat.f(delta),
    });
    _controller.applyScrollDelta(delta);
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
            'newestTop': DevLogFormat.f(pd.offset),
            'bottomEdge': DevLogFormat.f(bottomEdge),
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
  /// [_alignedTopForMessage].
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

  /// Apply a pending [ChatScrollController.navigationAlignment] after the
  /// anchor message is laid out. Returns whether the anchor offset moved.
  ///
  /// **Dual-writer guard:** close-path `animateTo` sets [navigationAlignment]
  /// and [ChatAnimator.tickAnimate] interpolates [anchorPixelOffset] each tick.
  /// Snapping here on every [performLayout] while that animation runs fights
  /// the interpolator and produces the non-zero-alignment micro-jump (alignment
  /// `0` never reaches this snap — it returns above). Deferred [jumpTo] and
  /// post-[animateTo] settle call this when no close-path animation is in flight;
  /// [navigationAlignment] stays set until the target row is built and aligned.
  bool _applyNavigationAlignment() {
    final alignment = _controller.navigationAlignment;
    final targetId = _controller.navigationAlignmentMessageId;
    if (targetId == null) return false;
    if (_animator.isAnimating && !_animator.farAnimateActive) {
      return false;
    }
    if (_controller.anchorMessageId != targetId) {
      return false;
    }

    final newest = _dataSource.newestKnownId;
    if (_dataSource.reachedNewest && newest != null && targetId == newest) {
      _controller.clearNavigationAlignment();
      return false;
    }

    final child = _boundaryBox(targetId);
    if (child == null || !child.hasSize) {
      return false;
    }

    final desiredTop = _alignedTopForMessage(child.size.height, alignment);
    final currentTop = _controller.anchorPixelOffset;
    if ((desiredTop - currentTop).abs() < 0.5) {
      if (_dataSource.getMessage(targetId) != null) {
        _controller.clearNavigationAlignment();
      }
      return false;
    }

    _fetchAnchorEvent('layout.align', {
      ..._fetchAnchorSnapshot(),
      'targetId': targetId,
      'alignment': DevLogFormat.f(alignment),
      'from': DevLogFormat.f(currentTop),
      'to': DevLogFormat.f(desiredTop),
      'childH': DevLogFormat.f(child.size.height),
    });
    _controller.reassignAnchor(targetId, desiredTop);
    _repositionFromAnchor();
    return true;
  }

  /// Clamp a pre-mount [jumpTo] anchor that landed past [newestKnownId].
  /// [_onJump] handles the mounted case; this covers the listener gap.
  void _normalizeAnchorToKnownTail() {
    final anchorId = _controller.anchorMessageId;
    final targetId = _clampJumpTarget(anchorId);
    if (targetId == anchorId) return;
    _controller
      ..reassignAnchor(targetId, 0)
      ..syncNavigationAlignmentTarget(targetId);
    _markPinTailOnJumpIfNeeded(targetId);
  }

  void _onJump(int messageId) {
    final targetId = _clampJumpTarget(messageId);
    if (targetId != messageId) {
      _controller.reassignAnchor(targetId, 0);
    }
    _controller.syncNavigationAlignmentTarget(targetId);
    _markPinTailOnJumpIfNeeded(targetId);
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
    _cancelBounceback();
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
    markNeedsLayout();
  }

  void _onScrollBy(double delta) {
    _cancelFling();
    _cancelAnimate();
    // Programmatic scroll is explicit user intent — it should win over a
    // passive spring-back. Otherwise the bounceback keeps pulling against
    // the new anchor offset for the rest of its window.
    _cancelBounceback();
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

    if (_dataSource.isEmpty || overlayKind != ChatOverlayKind.none) {
      _layoutOverlayMode(overlayKind);
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

    _fetchAnchorLog.bumpLayoutFrame();
    _fetchLogAnchorIdAtLayoutStart = _controller.anchorMessageId;
    _fetchLogAnchorYAtLayoutStart = _controller.anchorPixelOffset;
    final bandAtStart = _bottomBandMessage();
    _fetchLogBandIdAtLayoutStart = bandAtStart?.id;
    _fetchLogBandBottomAtLayoutStart = bandAtStart?.bottom;
    _fetchAnchorEvent('layout.begin', {
      ..._fetchAnchorSnapshot(),
      'fetchingChunks': DevLogFormat.ids(_fetchingChunkIndices(), max: 8),
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
        'yBefore': DevLogFormat.f(anchorYBefore),
        'yAfter': DevLogFormat.f(anchorYAfterRenorm),
      });
    }
    final alignmentMoved = _applyNavigationAlignment();
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
    if (!occupyingSpanAutoScroll) {
      _applyPendingTailPin();
    }
    // Self-insert animate owns follow-tail motion: skip instant pin on id
    // advance (teleport). Same-id height growth still repins (edit expand).
    final followTailRepin =
        (!_deferTailAdvancedRepin && tailAdvanced) || newestHeightGrew;
    final repinBottom =
        (!occupyingSpanAutoScroll && _pinTailOnJump) ||
        (_dataSource.reachedNewest &&
            _wasAtTailLastLayout &&
            followTailRepin &&
            !occupyingSpanAutoScroll);
    if (repinBottom || _pendingTailPinUntilSettled || _pinTailOnJump) {
      _fetchAnchorEvent('layout.tailPinFlags', {
        ..._fetchAnchorSnapshot(),
        'repinBottom': repinBottom,
        'tailAdvanced': tailAdvanced,
        'newestHeightGrew': newestHeightGrew,
        'pinTailOnJump': _pinTailOnJump,
      });
    }
    _pinTailOnJump = false;
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
    if (clamped ||
        _controller.anchorMessageId != anchorBefore ||
        alignmentMoved) {
      _fetchAnchorEvent('layout.refan', {
        ..._fetchAnchorSnapshot(),
        'clamped': clamped,
        'alignmentMoved': alignmentMoved,
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
        _animator.log.event('stitch.gc', {
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
        'removed': DevLogFormat.ids(staleMessages, max: 12),
        'removedCount': staleMessages.length,
        'removedChunks': DevLogFormat.ids(staleErrorChunks, max: 4),
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
        'anchorDy': anchorDy == null ? null : DevLogFormat.f(anchorDy),
        'anchorIdChanged': idChanged,
        'bandIdWas': _fetchLogBandIdAtLayoutStart,
        'bandIdNow': bandAtEnd?.id,
        'bandBottomDy': bandBottomDy == null
            ? null
            : DevLogFormat.f(bandBottomDy),
        'clamped': clamped,
        'refan':
            clamped ||
            _controller.anchorMessageId != anchorBefore ||
            alignmentMoved,
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
    if (_scrollbarLog.enabled) {
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
    // The overlay-branch `_clearHighlight()` in `_onTick` is unreachable
    // once the ticker has stopped — clear here so a highlight that was
    // alive when the viewport entered overlay mode does not survive across
    // the transition and tint a re-mounted target id on the next paint.
    _clearHighlight();
    // Clear drag + bounceback state so that the next normal-mode layout's
    // `_clampBoundaries` is not silently suppressed by stale flags. The
    // ticker is about to stop, so the overlay branch of `_onTick` can no
    // longer reset them.
    _dragInProgress = false;
    _cancelBounceback();
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
          : DevLogFormat.f(before.deletedHeight!),
      'anchorYBefore': DevLogFormat.f(before.anchorYBefore),
      'scrollDelta': DevLogFormat.f(scrollDelta),
      'anchorHeightAfter': DevLogFormat.f(anchorHeightAfter),
      'bandIdBefore': before.bandIdBefore,
      'bandBottomBefore': before.bandBottomBefore == null
          ? null
          : DevLogFormat.f(before.bandBottomBefore!),
      'bandBottomAfterPre': bandAfterLayout == null
          ? null
          : DevLogFormat.f(bandAfterLayout.bottom),
      'bandBottomAfter': bandAfter == null
          ? null
          : DevLogFormat.f(bandAfter.bottom),
      'bottomEdge': DevLogFormat.f(bottomEdge),
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
    child.layout(cc, parentUsesSize: true);
    _touchChunk(id);
    final loaded = _dataSource.getMessage(id) != null;
    if (_fetchAnchorLog.enabled) {
      _fetchAnchorEvent('build.tile', {
        'id': id,
        'loaded': loaded,
        'h': DevLogFormat.f(child.size.height),
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
    final navTarget = _controller.navigationAlignmentMessageId;
    if (navTarget != null) pinned.add(navTarget);
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
        'fromY': DevLogFormat.f(fromY),
        'toY': DevLogFormat.f(bestOffset),
      });
      if (_scrollbarLog.enabled) {
        final before = _computeScrollbarProgress(
          anchorIdOverride: fromId,
          anchorYOverride: fromY,
        );
        final after = _computeScrollbarProgress();
        _scrollbarEvent('renormalize', {
          'fromId': fromId,
          'toId': bestId,
          'fromY': DevLogFormat.f(fromY),
          'toY': DevLogFormat.f(bestOffset),
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
  /// When true there is no scroll range — same as a non-scrollable [ListView].
  /// Overscroll, bounceback, fling, and dual-boundary clamp fights are suppressed;
  /// only the chat/list short-content pin runs ([pinNewest] when [reverse],
  /// [pinOldest] otherwise).
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

  /// Signed overscroll amount, in pixels. Positive = oldest has been pulled
  /// *below* the top edge (user dragged past the top); negative = newest
  /// has been pulled *above* the bottom edge (past the bottom). Zero means
  /// no boundary is being violated. Reads `_boundaryBox`, so chunk-error
  /// tiles count as boundaries too.
  ///
  /// When the conversation fits inside the viewport and both boundaries are
  /// violated, returns the larger-magnitude violation so the bounceback
  /// pulls toward the dominant side. Returns zero when [_contentFitsInViewport]
  /// — there is no scroll range to overshoot.
  double _signedOverscroll() {
    if (_contentFitsInViewport()) return 0;
    final top = _overscrollOnSide(BouncebackSide.top);
    final bottom = _overscrollOnSide(BouncebackSide.bottom);
    if (top == 0.0) return bottom;
    if (bottom == 0.0) return top;
    // Both violated — return the dominant side.
    return top.abs() >= bottom.abs() ? top : bottom;
  }

  /// Signed overscroll for a *specific* side, ignoring the opposite side.
  /// Used by [ChatScrollPhysics.tickBounceback] so the spring-back animation
  /// stays locked onto the boundary it started from, even when fling composition or
  /// dual-boundary geometry would flip the dominant violator mid-animation.
  ///
  /// Positive top-side return = oldest below top edge; negative bottom-side
  /// return = newest above bottom edge. Zero when the requested side is
  /// inside its boundary or no boundary is configured on that side.
  double _overscrollOnSide(BouncebackSide side) {
    if (_contentFitsInViewport()) return 0;
    switch (side) {
      case BouncebackSide.top:
        final oldest = _dataSource.oldestKnownId;
        if (!_dataSource.reachedOldest || oldest == null) return 0;
        final first = _boundaryBox(oldest);
        if (first == null) return 0;
        final topY = _parentData(first).offset;
        return topY > 0 ? topY : 0.0;
      case BouncebackSide.bottom:
        final newest = _dataSource.newestKnownId;
        if (!_dataSource.reachedNewest || newest == null) return 0;
        final last = _boundaryBox(newest);
        if (last == null) return 0;
        final bottom = _parentData(last).offset + last.size.height;
        final bottomEdge = size.height - _bottomPad;
        return bottom < bottomEdge ? bottom - bottomEdge : 0.0;
    }
  }

  /// Delegates to [_physics] after measuring [_signedOverscroll]. Only used
  /// while [_dragInProgress] and a boundary is reachable — fling / animate /
  /// wheel / keyboard skip resistance and go through the normal clamp instead.
  double _applyOverscrollResistance(double delta) =>
      _physics.applyOverscrollResistance(delta, _signedOverscroll());

  bool _clampBoundaries({bool repinBottom = false}) {
    // Skip clamping during an active drag — overshoot is allowed there,
    // and the spring-back animation handles the return on release. The
    // bounceback animation itself also drives the anchor past the boundary
    // and back, so it owns the clamp until it ends.
    if (_dragInProgress || _physics.isBouncing) return false;
    var cancelFling = false;

    bool pinNewest() {
      final newest = _dataSource.newestKnownId;
      if (!_dataSource.reachedNewest || newest == null) return false;
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
          'delta': DevLogFormat.f(delta),
          'repinBottom': repinBottom,
          'newestId': newest,
          'newestBottom': DevLogFormat.f(bottom),
          'newestTop': DevLogFormat.f(_parentData(last).offset),
          'newestH': DevLogFormat.f(last.size.height),
          'newestLoaded': _dataSource.getMessage(newest) != null,
        });
        _controller.applyScrollDelta(delta);
        _repositionFromAnchor();
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
          'delta': DevLogFormat.f(delta),
          'oldestId': oldest,
          'oldestTop': DevLogFormat.f(topY),
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
      _setOffset(child, y);
      y += child.size.height;
    }
    y = _controller.anchorPixelOffset;
    for (var id = anchorId - 1; id >= minBuiltId; id--) {
      final child = _children[id];
      if (child == null) continue; // skip absent / unbuilt IDs in the range
      y -= child.size.height;
      _setOffset(child, y);
    }
  }

  // --- Day separators --------------------------------------------------------

  /// Set a child's viewport [offset]. For a day-starting message it also
  /// refreshes the inline separator's fade opacity from the paint position —
  /// Tier-1-safe (parent-data + optional stitch dy), no `getMessage`.
  void _setOffset(RenderBox child, double offset) {
    final pd = _parentData(child)..offset = offset;
    if (pd.startsDay) {
      pd.dividerOpacity = _floatingHeaderController.dividerOpacityFor(
        topY: offset + _stitchPaintDyIfActive(pd.id),
        topPad: _topPad,
        floatingHeaderHeight: _effectiveFloatingHeaderHeight(),
      );
    }
  }

  /// Paint translation while stitch is jumped; `0` otherwise.
  double _stitchPaintDyIfActive(int id) =>
      (_animator.farAnimateActive && _animator.farAnimateJumped)
      ? _stitchPaintDy(id)
      : 0.0;

  /// Refresh inline-separator fades from paint Y during stitch ticks (progress
  /// changes without `_setOffset`).
  void _refreshStitchDividerOpacities() {
    if (!_animator.farAnimateActive || !_animator.farAnimateJumped) return;
    final headerH = _effectiveFloatingHeaderHeight();
    for (final entry in _children.entries) {
      final pd = _parentData(entry.value);
      if (!pd.startsDay) continue;
      pd.dividerOpacity = _floatingHeaderController.dividerOpacityFor(
        topY: pd.offset + _stitchPaintDy(pd.id),
        topPad: _topPad,
        floatingHeaderHeight: headerH,
      );
    }
  }

  /// Header height used for inline-divider fade — zero when the floating
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

  /// Rebuild (only on a group change), lay out, and pin the floating header.
  /// Called from [performLayout]. Widget inflation stays in the render object
  /// via [invokeLayoutCallback]; bucket/date logic is on the controller.
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
    _placeFloatingHeader();
  }

  /// During a Tier-1 scroll: re-pin the header and report whether the topmost
  /// day changed — the caller then relayouts to rebuild the header text.
  bool _tickFloatingHeader() {
    if (_groupBy == null) return false;
    if (!_shouldShowFloatingHeader()) {
      return _floatingHeader != null;
    }
    if (_floatingHeader == null) return true;
    final scan = _scanTopDay();
    _placeFloatingHeader();
    return _floatingHeaderController.tickForDayChange(
      scan: scan,
      groupBy: _groupBy,
      hasFloatingHeader: _floatingHeader != null,
    );
  }

  /// Pin the floating header just below the top inset — see
  /// [ChatFloatingHeaderController.placeHeaderOffset].
  void _placeFloatingHeader() {
    final header = _floatingHeader;
    if (header != null) {
      _parentData(header).offset = _floatingHeaderController.placeHeaderOffset(
        topPad: _topPad,
      );
    }
  }

  // --- Scroll ----------------------------------------------------------------

  void _markScrollActive() => _chunkFetchScheduler.markScrollActive();

  void _ensureTicker() {
    final ticker = _ticker;
    if (ticker != null && !ticker.isActive) ticker.start();
  }

  void _stopTickerIfIdle() {
    if (!_physics.isFlinging &&
        _pendingScrollDelta == 0.0 &&
        _animator.highlightTargetId == null &&
        !_animator.isAnimating &&
        !_physics.isBouncing &&
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
    _physics.startFling(velocity);
    _ensureTicker();
    _controller.notifyScrollEvent(ChatFlingStart(velocity));
  }

  /// Clears fling simulation and emits [ChatFlingEnd] when a fling was active.
  void _cancelFling() {
    final wasFlinging = _physics.isFlinging;
    _physics.cancelFling();
    if (wasFlinging) _controller.notifyScrollEvent(const ChatFlingEnd());
  }

  void _clearHighlight({bool animated = false}) =>
      _animator.clearHighlight(animated: animated);

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
      _clearHighlight();
      _cancelBounceback();
      _dragInProgress = false;
      _ticker?.stop();
      return;
    }

    // Skip the scroll path entirely on highlight-only frames so the fetch
    // poll's debounce isn't constantly reset by `_markScrollActive`.
    final occupyingSpanAutoScroll = _spanAutoScrollOccupying;
    final hasScrollWork =
        _pendingScrollDelta != 0.0 ||
        _physics.isFlinging ||
        (!occupyingSpanAutoScroll && _animator.isAnimating) ||
        _physics.isBouncing ||
        occupyingSpanAutoScroll;
    if (!hasScrollWork) {
      // Highlight-only frame: advance the fade and bail.
      if (_animator.tickHighlight(elapsed)) markNeedsPaint();
      if (!_animator.hasHighlight) _stopTickerIfIdle();
      return;
    }

    _markScrollActive();
    // Drag / wheel accumulate into `_pendingScrollDelta`. Only that plus fling
    // ticks are user-driven for [ChatViewportScrolled] — animate, bounceback,
    // and span auto-scroll are excluded.
    var userDelta = _pendingScrollDelta;
    _pendingScrollDelta = 0.0;

    if (_contentFitsInViewport()) {
      _cancelFling();
      _cancelBounceback();
      userDelta = 0.0;
    }

    // While the user is dragging, scale incoming delta by the boundary
    // resistance so pulling further past the edge gets progressively
    // harder. Fling / animate / wheel / keyboard skip this — they go
    // through the normal clamp instead. The `reached*` gate elides the
    // per-tick `_signedOverscroll` walk on the dominant case where the
    // user is dragging mid-conversation with no boundary in sight.
    if (_dragInProgress &&
        (_dataSource.reachedOldest || _dataSource.reachedNewest)) {
      userDelta = _applyOverscrollResistance(userDelta);
    }

    final wasFlinging = _physics.isFlinging;
    final flingDelta = _physics.tickFling(elapsed);
    userDelta += flingDelta;
    // tickFling clears the simulation internally when done; the render object
    // owns scroll-event dispatch (ChatScrollPhysics does not touch controller).
    if (wasFlinging && !_physics.isFlinging) {
      _controller.notifyScrollEvent(const ChatFlingEnd());
    }
    var delta = userDelta;
    // animateTo drives the same Ticker — the close path contributes a delta
    // to the anchor offset, the far path mutates fade opacity and triggers
    // jumpTo on its own. Inserted *between* fling and bounceback so the
    // original composition order is preserved when multiple phases overlap.
    // Span auto-scroll is the sole origin writer while the edge band is
    // occupied — close-path animate yields.
    if (occupyingSpanAutoScroll) {
      _cancelAnimate();
    } else {
      delta += _animator.tickAnimate(elapsed);
    }
    // Spring-back from an overscroll release. Runs after the user lets go,
    // pulling the boundary back to its edge over [kOverscrollBounceDuration].
    delta += _physics.tickBounceback(elapsed);
    delta += _spanAutoScrollDelta(elapsed, lastElapsed);

    if (userDelta != 0.0) {
      _controller.notifyScrollEvent(ChatViewportScrolled(userDelta));
    }
    if (delta != 0.0) _controller.applyScrollDelta(delta);
    // Smooth the per-frame scroll delta; biases the next fan-out lead.
    _scrollVelocity = _scrollVelocity * 0.7 + delta * 0.3;
    _repositionFromAnchor();
    if (occupyingSpanAutoScroll) _applyLiveSpanHit();
    // Keep the anchor on a visible message so the next layout fans out a
    // tight range rather than rebuilding everything back to a drifted anchor.
    if (!_skipRenormalizeDuringClosePath()) {
      _renormalizeAnchor();
    }
    if (_clampBoundaries()) {
      _cancelFling();
      // Stitch owns the anchor until dual-translate settles — clamping must
      // not abort the far path mid-flight.
      if (!_animator.farAnimateActive) {
        _cancelAnimate();
      }
    }
    _updateScrollSemantics();
    _publishControllerState();
    // Reposition the header (Tier-1); a day crossing needs a relayout to
    // rebuild its text. Stitch also refreshes inline-separator fades from
    // paint Y as dual-translate progress moves rows.
    _refreshStitchDividerOpacities();
    final headerDayChanged = _tickFloatingHeader();

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
    final coverageNeedsLayout =
        !_animator.farAnimateActive && _rangeNoLongerCovers();
    if (coverageNeedsLayout || headerDayChanged) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }

    if (!_physics.isFlinging &&
        !_animator.isAnimating &&
        !_animator.hasHighlight &&
        !_physics.isBouncing &&
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
    // User takes control — attach/jump pending settle must not compete.
    _cancelPendingTailPin();
    _controller.clearNavigationAlignment();
    _cancelFling();
    // Drag takes over: fade navigate-select if a flight or hold is live.
    _cancelAnimate();
    if (_animator.hasHighlight) {
      _clearHighlight(animated: true);
    }
    _cancelBounceback();
    _dragInProgress = true;
    _ensureTicker();
    _controller.notifyScrollEvent(const ChatUserDragStart());
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_contentFitsInViewport()) return;
    _markScrollActive();
    // Resistance is applied at the *tick* layer (`_onTick`), not here, so
    // multiple updates within a single frame still see one combined delta
    // and the resistance scales it once against the current overscroll.
    _pendingScrollDelta += details.delta.dy;
    _ensureTicker();
  }

  void _onDragEnd(DragEndDetails details) {
    _dragInProgress = false;
    final velocity = details.primaryVelocity ?? 0.0;
    _controller.notifyScrollEvent(ChatUserDragEnd(velocity));
    if (_contentFitsInViewport()) {
      _clampBoundaries();
      if (!_physics.isBouncing) _stopTickerIfIdle();
      return;
    }
    // A high-velocity release while overscrolled would otherwise launch
    // straight into a fling and skip the spring-back entirely — the next
    // `_clampBoundaries` would hard-snap the boundary. Run bounceback
    // unconditionally; the fling (if started) composes additively in
    // `_onTick`, and the bounceback shortens its own life as overscroll
    // shrinks past zero.
    _maybeStartBounceback();
    if (velocity.abs() >= 50.0) {
      _startFling(velocity);
    } else if (!_physics.isBouncing) {
      _stopTickerIfIdle();
    }
  }

  /// Cancel any in-flight bounceback. Called from `_onDragStart`,
  /// `_onScrollBy`, and the close-path of `animate()` so a programmatic
  /// scroll / animateTo / new drag does not have to fight the spring-back.
  void _cancelBounceback() {
    _physics.cancelBounceback();
  }

  /// If the viewport is currently overscrolled, arm a spring-back
  /// animation that pulls the boundary back to its edge across
  /// [kOverscrollBounceDuration]. No-op when nothing is past a boundary.
  ///
  /// Locks onto the dominant violator's side and uses *only* that side's
  /// overscroll for the duration of the animation. When both boundaries
  /// are violated (short-content viewport with aggressive drag) the lesser
  /// side stays in its post-release position until the dominant spring-back
  /// finishes — `_clampBoundaries` then snaps the residual on the first
  /// post-bounceback layout. The alternative (running two springs in
  /// parallel) compounds delta and fights itself in the symmetric case.
  void _maybeStartBounceback() {
    if (_contentFitsInViewport()) return;
    final top = _overscrollOnSide(BouncebackSide.top);
    final bottom = _overscrollOnSide(BouncebackSide.bottom);
    if (top == 0.0 && bottom == 0.0) return;
    final BouncebackSide side;
    final double initial;
    if (top.abs() >= bottom.abs()) {
      side = BouncebackSide.top;
      initial = top;
    } else {
      side = BouncebackSide.bottom;
      initial = bottom;
    }
    _physics.maybeStartBounceback(initial, side);
    _ensureTicker();
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
      _cancelBounceback();
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
      if (_dataSource.getMessage(id) != null && _isSelectionAllowed(id)) {
        ids.add(id);
      }
      if (id == hit) break;
    }
    return ids;
  }

  bool _isSelectionAllowed(int id) =>
      _selectionController?.isSelectionAllowed(id) ?? true;

  /// Present loaded message under [local], ignoring selection-allowed.
  int? _presentMessageIdAt(Offset local) =>
      _selectionMessageIdAt(local, requireSelectionAllowed: false);

  /// Converts a viewport-local idle tap into the host callback's global
  /// slot rect and tap offset.
  void _dispatchIdleMessageTap(int id, Offset local) {
    final callback = _onIdleMessageTap;
    if (callback == null) return;
    final child = _children[id];
    if (child == null || !child.hasSize) return;
    final pd = _parentData(child);
    final origin = localToGlobal(Offset(0, pd.offset));
    final slotGlobal = origin & Size(size.width, child.size.height);
    callback(id, slotGlobal, localToGlobal(local));
  }

  /// Loaded message whose selectable body contains [local], or `null` when
  /// the point is over overlay, chunk-error, shimmer, date chrome, or empty
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
    if (header != null && _shouldShowFloatingHeader()) {
      final top = _parentData(header).offset;
      pinnedHeaderCovers =
          local.dy >= top && local.dy < top + header.size.height;
      if (pinnedHeaderCovers && !hitThroughPinnedHeader) {
        return null;
      }
    }

    for (final child in _chunkErrors.values) {
      final pd = _parentData(child);
      if (pd.offset >= h || pd.offset + child.size.height <= 0) continue;
      if (local.dy >= pd.offset && local.dy < pd.offset + child.size.height) {
        return null;
      }
    }

    for (final entry in _children.entries) {
      final child = entry.value;
      final pd = _parentData(child);
      if (pd.offset >= h || pd.offset + child.size.height <= 0) continue;
      if (local.dy < pd.offset || local.dy >= pd.offset + child.size.height) {
        continue;
      }
      if (_dataSource.getMessage(entry.key) == null) return null;
      if (requireSelectionAllowed && !_isSelectionAllowed(entry.key)) {
        return null;
      }
      final inDateChrome = local.dy < pd.offset + pd.messageBodyTop;
      if (inDateChrome && !hitFullRow && !pinnedHeaderCovers) return null;
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
      if (_physics.isFlinging) {
        _cancelFling();
        _pendingScrollDelta = 0.0;
        _scrollVelocity = 0.0;
        _controller.flingCancelSuppressesLongPress = true;
        _flingCancelPointer = event.pointer;
      } else if (_flingCancelPointer == null &&
          _controller.flingCancelSuppressesLongPress) {
        // A new pointer without cancelling fling — drop stale suppression left
        // over from a prior fling-cancel tap whose post-frame clear has not
        // run yet.
        _controller.flingCancelSuppressesLongPress = false;
      }
      _drag?.addPointer(event);
      _selectionPointer?.addPointer(event);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_flingCancelPointer == event.pointer) {
        _flingCancelPointer = null;
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
      _cancelFling();
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
    if (header != null && _shouldShowFloatingHeader()) {
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

  // --- Visible range publishing --------------------------------------------

  /// Push the current first/last on-screen ids + anchor id to the controller's
  /// `visibleRange` listenable, and update its `isAtTail` flag. Called after
  /// every layout and Tier-1 tick — O(visible children) of pure parent-data
  /// reads.
  void _publishControllerState() {
    _publishBoundaries();
    _publishVisibleRange();
    _publishNewestHeightSample();
    _publishIsAtTail();
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
    if (_scrollbarLog.enabled) {
      final current = _computeScrollbarProgress();
      _scrollbarEvent('jump', {
        'dragProgress': DevLogFormat.f(progress),
        'targetId': targetId,
        'oldest': oldest,
        'newest': newest,
        if (current != null) 'thumbProgress': DevLogFormat.f(current.progress),
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
      'topEdge': DevLogFormat.f(_topPad),
      'bottomEdge': DevLogFormat.f(bottomEdge),
      'newestTop': newestTop == null ? null : DevLogFormat.f(newestTop),
      'newestBottom': newestBottom == null
          ? null
          : DevLogFormat.f(newestBottom),
      'oldestTop': oldestTop == null ? null : DevLogFormat.f(oldestTop),
      'anchorBottom': anchorBottom == null
          ? null
          : DevLogFormat.f(anchorBottom),
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
      'sumHAbove': DevLogFormat.f(sumAbove),
      'sumHBelow': DevLogFormat.f(sumBelow),
      'totalBuiltH': DevLogFormat.f(totalH),
      'progressByBuiltIds': progressByBuiltIds == null
          ? null
          : DevLogFormat.f(progressByBuiltIds),
      'prevId': prevId,
      'prevH': prevH == null ? null : DevLogFormat.f(prevH),
      'nextId': nextId,
      'nextH': nextH == null ? null : DevLogFormat.f(nextH),
      'anchorTop': anchorTop == null ? null : DevLogFormat.f(anchorTop),
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
      'progress': DevLogFormat.ratio(computed.progress),
      'thumbFraction': DevLogFormat.ratio(computed.thumbFraction),
      if (thumbHeightPx != null) 'thumbHeightPx': DevLogFormat.f(thumbHeightPx),
      'fractionalId': DevLogFormat.ratio(computed.fractionalId, decimals: 2),
      'bandRefY': DevLogFormat.f(computed.bandRefY),
      'heightAtBandTop': DevLogFormat.f(computed.heightAtBandTop),
      if (extrapModel != null)
        'heightAtBandTopExtrap': DevLogFormat.f(extrapModel.heightAtRef),
      'estimatedExtent': DevLogFormat.f(computed.estimatedExtent),
      if (extrapModel != null)
        'estimatedExtentExtrap': DevLogFormat.f(extrapModel.estimatedExtent),
      'avgRowH': DevLogFormat.f(computed.avgRowH),
      if (bandHeight != null) 'bandHeight': DevLogFormat.f(bandHeight),
      if (maxScroll != null) 'maxScroll': DevLogFormat.f(maxScroll),
      'progressIdLinear': DevLogFormat.ratio(computed.idLinearProgress),
      if (bandTopFrac != null)
        'fractionalIdTop': DevLogFormat.ratio(bandTopFrac, decimals: 2),
      if (bandBottomFrac != null)
        'fractionalIdBottom': DevLogFormat.ratio(bandBottomFrac, decimals: 2),
      if (bandTopFrac != null && bandBottomFrac != null)
        'visibleIdSpan': DevLogFormat.ratio(
          bandBottomFrac - bandTopFrac,
          decimals: 2,
        ),
      if (hasSize) 'bandBottomRefY': DevLogFormat.f(size.height - _bottomPad),
      'progressLegacy': DevLogFormat.ratio(computed.legacyProgress),
      'fractionalIdLegacy': DevLogFormat.ratio(
        computed.legacyFractionalId,
        decimals: 2,
      ),
      'anchorId': computed.anchorId,
      'anchorY': DevLogFormat.f(computed.anchorY),
      'anchorH': DevLogFormat.f(computed.anchorH),
      'slotHeight': DevLogFormat.f(computed.slotHeight),
      'slotHeightIsFallback': computed.slotHeightIsFallback,
      'anchorBuilt': computed.anchorBuilt,
      'anchorLoaded': computed.anchorLoaded,
      'offsetAsIdAtSlot': DevLogFormat.f(offsetAsIdAtSlot),
      if (offsetAsIdAtAnchorH != null)
        'offsetAsIdAtAnchorH': DevLogFormat.f(offsetAsIdAtAnchorH),
      if (progressAtAnchorH != null)
        'progressIfAnchorH': DevLogFormat.f(progressAtAnchorH),
      'progressAtSlotH': DevLogFormat.f(progressAtSlotH),
      'progressDeltaVsAnchorH': progressAtAnchorH == null
          ? null
          : DevLogFormat.f((computed.progress - progressAtAnchorH).abs()),
      'oldest': computed.oldest,
      'newest': computed.newest,
      'idRange': computed.idRange,
      'drag': _scrollbar.isDragging,
      'fling': _physics.isFlinging,
      ...boundary,
      if (tailDeficit != null && tailDeficit > 0.01)
        'tailDeficit': DevLogFormat.f(tailDeficit),
      if (legacyTailDeficit != null && legacyTailDeficit > 0.01)
        'tailDeficitLegacy': DevLogFormat.f(legacyTailDeficit),
      if (headSurplus != null && headSurplus > 0.01)
        'headSurplus': DevLogFormat.f(headSurplus),
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
    if (!_scrollbarLog.enabled) return;

    final progressDelta = _scrollbarLogLastProgress == null
        ? double.infinity
        : (computed.progress - _scrollbarLogLastProgress!).abs();
    final anchorHDelta = _scrollbarLogLastAnchorH == null
        ? double.infinity
        : (computed.anchorH - _scrollbarLogLastAnchorH!).abs();
    final anchorIdChanged = computed.anchorId != _scrollbarLogLastAnchorId;
    _scrollbarLogPaintCounter++;
    final periodicWhileScrolling =
        (_physics.isFlinging || _dragInProgress || _scrollbar.isDragging) &&
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
    // The floating day header — above the messages, below the scrollbar.
    final header = _floatingHeader;
    if (header != null && _shouldShowFloatingHeader()) {
      context.paintChild(
        header,
        offset + Offset(0, _parentData(header).offset),
      );
    }
    _paintScrollbar(context, offset);
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
    super.dispose();
  }
}

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
