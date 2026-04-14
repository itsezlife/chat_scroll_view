import 'dart:math' as math;

import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_message_render.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_bar.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_layout.dart';
import 'package:chatscrollview/src/chat_scroll/chat_selection_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// {@template chat_scroll_view}
/// A custom chat viewport that renders all messages on a single canvas
/// using [ui.Picture] caching per message. No child widgets — everything
/// is drawn by [ChatMessageRender] objects managed by [RenderChatScrollView].
/// {@endtemplate}
class ChatScrollView extends LeafRenderObjectWidget {
  /// {@macro chat_scroll_view}
  const ChatScrollView({
    required this.dataSource,
    required this.controller,
    required this.builder,
    this.selectionController,
    super.key,
  });

  /// The data source that owns message data and fetch contract.
  final ChatDataSource dataSource;

  /// The scroll controller that owns navigation and boundary state.
  final ChatScrollController controller;

  /// Creates a [ChatMessageRender] for each message.
  final ChatMessageRenderFactory builder;

  /// Optional selection controller for text/bubble selection.
  final ChatSelectionController? selectionController;

  @override
  RenderChatScrollView createRenderObject(BuildContext context) =>
      RenderChatScrollView(
        dataSource: dataSource,
        controller: controller,
        messageBuilder: builder,
        selectionController: selectionController,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatScrollView renderObject,
  ) {
    renderObject
      ..dataSource = dataSource
      ..controller = controller
      ..messageBuilder = builder
      ..selectionController = selectionController;
  }
}

/// The render object for [ChatScrollView].
///
/// Uses a [Ticker] for scroll updates (drag + fling) — the scroll path
/// bypasses the paint pipeline entirely. Only [OffsetLayer.offset] is
/// updated, and the compositor re-composites via [markNeedsAddToScene].
///
/// Layout and paint are only triggered by data changes, jumps, boundary
/// changes, and viewport resize.
class RenderChatScrollView extends RenderBox implements MouseTrackerAnnotation {
  RenderChatScrollView({
    required ChatDataSource dataSource,
    required ChatScrollController controller,
    required ChatMessageRenderFactory messageBuilder,
    ChatSelectionController? selectionController,
  }) : _dataSource = dataSource,
       _controller = controller,
       _messageBuilder = messageBuilder,
       _selectionController = selectionController;

  // --- Debug instrumentation (zero-cost in release via assert) ---

  final Stopwatch _debugSw = Stopwatch();

  @visibleForTesting
  Duration debugLastLayoutDuration = Duration.zero;

  @visibleForTesting
  int debugLayoutFrameId = 0;

  @visibleForTesting
  Duration debugLastPaintDuration = Duration.zero;

  @visibleForTesting
  int debugPaintFrameId = 0;

  @visibleForTesting
  int get debugAttachedRenderCount {
    var count = 0;
    for (final chunk in _dataSource.chunks.values) {
      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render != null && render.isAttached) count++;
      }
    }
    return count;
  }

  @visibleForTesting
  int get debugTotalRenderCount {
    var count = 0;
    for (final chunk in _dataSource.chunks.values) {
      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        if (chunk.renders[i] != null) count++;
      }
    }
    return count;
  }

  @visibleForTesting
  int get debugChunkCount => _dataSource.chunks.length;

  @visibleForTesting
  int get debugLayoutMinChunk => _layoutMinChunk;

  @visibleForTesting
  int get debugLayoutMaxChunk => _layoutMaxChunk;

  // --- Data source ---

  ChatDataSource _dataSource;

  set dataSource(ChatDataSource value) {
    if (identical(_dataSource, value)) return;
    _dataSource.removeDataListener(_onDataChanged);
    _dataSource = value;
    _dataSource.addDataListener(_onDataChanged);
    markNeedsLayout();
  }

  // --- Scroll controller ---

  ChatScrollController _controller;

  set controller(ChatScrollController value) {
    if (identical(_controller, value)) return;
    _controller.removeJumpListener(_onJump);
    _controller.removeBoundaryListener(_onBoundaryChanged);
    _controller = value;
    _controller.addJumpListener(_onJump);
    _controller.addBoundaryListener(_onBoundaryChanged);
    markNeedsLayout();
  }

  // --- Message builder ---

  ChatMessageRenderFactory _messageBuilder;

  set messageBuilder(ChatMessageRenderFactory value) {
    if (identical(_messageBuilder, value)) return;
    _messageBuilder = value;
    _markAllRendersDirty();
    markNeedsLayout();
  }

  // --- Configuration ---

  double _cacheExtent = 250.0;

  set cacheExtent(double value) {
    if (_cacheExtent == value) return;
    _cacheExtent = value;
    markNeedsLayout();
  }

  // --- Content area constraints ---

  static const double _maxContentWidth = 620.0;
  static const double _maxBubbleWidth = 464.0;
  static const double _bubbleWidthFraction = 0.75;

  double get _contentWidth => math.min(size.width, _maxContentWidth);
  double get _contentX => (size.width - _contentWidth) / 2;
  double get _bubbleMaxWidth =>
      math.min(_maxBubbleWidth, _contentWidth * _bubbleWidthFraction);

  // --- Attach / detach zones (hysteresis) ---

  static const double _attachFactor = 1.0;
  static const double _detachFactor = 1.7;

  // --- Layout state ---

  int _accessTick = 0;
  int _layoutMinChunk = 0;
  int _layoutMaxChunk = -1; // empty range initially
  double _lastLayoutWidth = 0.0;
  final _layoutHelper = ChatScrollLayoutHelper();

  // --- Ticker & scroll state ---

  Ticker? _ticker;
  double _pendingScrollDelta = 0.0;
  ClampingScrollSimulation? _simulation;
  Duration _flingStartTime = Duration.zero;
  double _lastFlingValue = 0.0;

  // --- Gesture ---

  VerticalDragGestureRecognizer? _drag;

  // --- Selection ---

  ChatSelectionController? _selectionController;

  set selectionController(ChatSelectionController? value) {
    if (identical(_selectionController, value)) return;
    _selectionController?.removeListener(_onSelectionChanged);
    _selectionController = value;
    if (attached) {
      _selectionController?.addListener(_onSelectionChanged);
      _rebuildSelectionRecognizers();
    }
  }

  LongPressGestureRecognizer? _longPress;
  TapGestureRecognizer? _tap;

  // --- Scrollbar ---

  final ChatScrollBar _scrollBar = ChatScrollBar();
  int? _scrollbarPointerId;

  // --- MouseTrackerAnnotation (hover/exit detection) ---

  @override
  MouseCursor get cursor => MouseCursor.defer;

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => _onPointerExit;

  @override
  bool get validForMouseTracker => true;

  void _onPointerExit(PointerExitEvent event) {
    if (_scrollBar.isHovered) {
      _scrollBar.isHovered = false;
      markNeedsPaint();
    }
  }

  // --- Layer management ---

  final LayerHandle<ClipRectLayer> _clipLayerHandle =
      LayerHandle<ClipRectLayer>();

  /// Whether initial paint has run (clipLayer registered with framework).
  bool _initialPaintDone = false;

  // --- RenderBox overrides ---

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get sizedByParent => true;

  @override
  void performResize() {
    size = constraints.biggest;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ticker = Ticker(_onTick);
    _dataSource.addDataListener(_onDataChanged);
    _controller.addJumpListener(_onJump);
    _controller.addBoundaryListener(_onBoundaryChanged);
    PaintingBinding.instance.systemFonts.addListener(_onSystemFontsChange);
    _drag = VerticalDragGestureRecognizer()
      ..onStart = _onDragStart
      ..onUpdate = _onDragUpdate
      ..onEnd = _onDragEnd;
    _selectionController?.addListener(_onSelectionChanged);
    _rebuildSelectionRecognizers();
  }

  @override
  void detach() {
    _cancelFling();
    _ticker?.dispose();
    _ticker = null;
    _drag?.dispose();
    _drag = null;
    _longPress?.dispose();
    _longPress = null;
    _tap?.dispose();
    _tap = null;
    _selectionController?.removeListener(_onSelectionChanged);
    _dataSource.removeDataListener(_onDataChanged);
    _controller.removeJumpListener(_onJump);
    _controller.removeBoundaryListener(_onBoundaryChanged);
    PaintingBinding.instance.systemFonts.removeListener(_onSystemFontsChange);
    super.detach();
  }

  @override
  void dispose() {
    _cancelFling();
    // TODO(plugfox): Cancel any pending fetches in the data source
    // to avoid calling back after dispose.
    // Mike Matiunin <plugfox@gmail.com>, 14 April 2026
    _ticker?.dispose();
    _ticker = null;
    _drag?.dispose();
    _drag = null;
    _longPress?.dispose();
    _longPress = null;
    _tap?.dispose();
    _tap = null;
    _scrollBar.dispose();
    _clipLayerHandle.layer = null;
    for (final chunk in _dataSource.chunks.values) {
      chunk.dispose();
    }
    super.dispose();
  }

  // --- Typed listener handlers (no flags!) ---

  void _onDataChanged() => markNeedsLayout();

  void _onJump(int messageId) {
    _cancelFling();
    markNeedsLayout();
  }

  void _onBoundaryChanged() => markNeedsLayout();

  void _onSystemFontsChange() {
    _markAllRendersDirty();
    markNeedsLayout();
  }

  // --- Gesture handling ---

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    assert(debugHandleEvent(event, entry));

    // Scrollbar drag in progress — consume move/up/cancel events.
    if (_scrollbarPointerId != null) {
      if (event is PointerMoveEvent && event.pointer == _scrollbarPointerId) {
        _onScrollbarPointerMove(event);
        return;
      }
      if (event is PointerUpEvent && event.pointer == _scrollbarPointerId) {
        _onScrollbarPointerUp();
        return;
      }
      if (event is PointerCancelEvent && event.pointer == _scrollbarPointerId) {
        _onScrollbarPointerUp();
        return;
      }
    }

    if (event is PointerDownEvent) {
      if (_scrollBar.isInHitArea(event.localPosition.dx, size.width) &&
          _controller.newestKnownId != null) {
        _onScrollbarPointerDown(event);
        return;
      }
      // Tap outside scrollbar clears hover highlight.
      if (_scrollBar.isHovered) {
        _scrollBar.isHovered = false;
        markNeedsPaint();
      }
      _drag?.addPointer(event);
      _longPress?.addPointer(event);
      _tap?.addPointer(event);
    } else if (event is PointerPanZoomStartEvent) {
      // Trackpad two-finger scroll — route to drag recognizer.
      _cancelFling();
      _drag?.addPointerPanZoom(event);
    } else if (event is PointerScrollEvent) {
      // Mouse wheel / trackpad momentum after finger lift.
      _cancelFling();
      _pendingScrollDelta -= event.scrollDelta.dy;
      _ensureTickerStarted();
    } else if (event is PointerHoverEvent) {
      final inHitArea =
          _scrollBar.isInHitArea(event.localPosition.dx, size.width) &&
          _controller.newestKnownId != null;
      if (inHitArea != _scrollBar.isHovered) {
        _scrollBar.isHovered = inHitArea;
        markNeedsPaint();
      }
    }
  }

  void _onDragStart(DragStartDetails details) {
    _cancelFling();
    _ensureTickerStarted();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _pendingScrollDelta += details.delta.dy;
    _ensureTickerStarted();
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity != null && velocity.abs() >= 50.0) {
      _startFling(velocity);
    } else {
      _stopTickerIfIdle();
    }
  }

  // --- Selection gesture handling ---

  void _rebuildSelectionRecognizers() {
    _longPress?.dispose();
    _tap?.dispose();
    if (_selectionController != null) {
      _longPress = LongPressGestureRecognizer()
        ..onLongPressStart = _onLongPressStart;
      _tap = TapGestureRecognizer()..onTapUp = _onTapUp;
    } else {
      _longPress = null;
      _tap = null;
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final sc = _selectionController;
    if (sc == null) return;
    final id = _messageIdAtPosition(details.localPosition);
    if (id == null) return;
    sc.startSelection(id);
  }

  void _onTapUp(TapUpDetails details) {
    final sc = _selectionController;
    if (sc == null || !sc.isSelectionMode) return;
    final id = _messageIdAtPosition(details.localPosition);
    if (id == null) return;
    sc.toggle(id);
  }

  // --- Selection listener → re-record changed renders ---

  void _onSelectionChanged() {
    if (!_initialPaintDone) return;
    final newMode = _selectionController?.isSelectionMode ?? false;
    var changed = false;
    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) continue;
      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null) continue;
        final sel =
            _selectionController?.isSelected(chunk.firstId + i) ?? false;
        final modeChanged = render.selectionMode != newMode;
        final selChanged = render.selected != sel;
        if (modeChanged) render.selectionMode = newMode;
        if (selChanged) render.selected = sel;
        if ((modeChanged || selChanged) && render.isAttached) {
          render.rerecordPicture();
          changed = true;
        }
      }
    }
    // Schedule a frame so the compositor picks up the re-recorded pictures.
    if (changed) markNeedsPaint();
  }

  /// Find the message ID at [position] in viewport coordinates.
  int? _messageIdAtPosition(Offset position) {
    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) continue;
      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null || render.isEmpty) continue;
        if (position.dy >= render.offsetY &&
            position.dy < render.offsetY + render.height) {
          return chunk.firstId + i;
        }
      }
    }
    return null;
  }

  /// Restore selection state on renders after layout/creation.
  void _restoreSelectionOnChunk(ChatScrollChunk chunk) {
    final sc = _selectionController;
    if (sc == null || !sc.isSelectionMode) return;
    for (var i = 0; i < ChatScrollChunk.kSize; i++) {
      final render = chunk.renders[i];
      if (render == null) continue;
      render.selectionMode = true;
      render.selected = sc.isSelected(chunk.firstId + i);
    }
  }

  // --- Scrollbar gesture handling ---

  void _onScrollbarPointerDown(PointerDownEvent event) {
    _cancelFling();
    _scrollbarPointerId = event.pointer;
    _scrollBar.isDragging = true;
    _jumpToScrollbarPosition(event.localPosition.dy);
  }

  void _onScrollbarPointerMove(PointerMoveEvent event) {
    _jumpToScrollbarPosition(event.localPosition.dy);
  }

  void _onScrollbarPointerUp() {
    _scrollbarPointerId = null;
    _scrollBar.isDragging = false;
    _updateScrollbar();
  }

  void _jumpToScrollbarPosition(double localY) {
    final newestId = _controller.newestKnownId;
    if (newestId == null || newestId == 0) return;
    final progress = _scrollBar.progressFromY(localY, size.height);
    final targetId = ChatScrollBar.targetIdFromProgress(progress, newestId);
    if (targetId != _controller.anchorMessageId) {
      _controller.jumpTo(targetId);
    }
  }

  // --- Scrollbar update ---

  /// Compute scrollbar progress from visible messages.
  ///
  /// Returns `null` when the scrollbar should be hidden (all content fits
  /// in the viewport or data is insufficient).
  /// Returns 0.0 at the top boundary, 1.0 at the bottom boundary, and
  /// smooth intermediate values based on the first visible message with
  /// sub-message pixel interpolation.
  double? _computeScrollbarProgress() {
    final newest = _controller.newestKnownId;
    final oldest = _controller.oldestKnownId;
    if (newest == null || oldest == null) return null;
    final range = newest - oldest;
    if (range <= 0) return null;

    final viewportHeight = size.height;
    final firstChunk = _dataSource.chunks[_layoutMinChunk];
    final lastChunk = _dataSource.chunks[_layoutMaxChunk];
    if (firstChunk == null || lastChunk == null) return null;

    final contentTop = firstChunk.offsetY;
    final contentBottom = lastChunk.offsetY + lastChunk.height;

    // All content fits in viewport → hide scrollbar.
    if (_controller.reachedOldest &&
        _controller.reachedNewest &&
        contentTop >= -0.5 &&
        contentBottom <= viewportHeight + 0.5) {
      return null;
    }

    // At top boundary → 0%.
    if (_controller.reachedOldest && contentTop >= -0.5) return 0.0;

    // At bottom boundary → 100%.
    if (_controller.reachedNewest && contentBottom <= viewportHeight + 0.5) {
      return 1.0;
    }

    // In between: find first visible message and interpolate within it.
    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) continue;
      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null || render.isEmpty) continue;
        if (render.offsetY + render.height > 0) {
          final id = chunk.firstId + i;
          var fraction = 0.0;
          if (render.offsetY < 0 && render.height > 0) {
            fraction = -render.offsetY / render.height;
          }
          return ((id + fraction - oldest) / range).clamp(0.0, 1.0);
        }
      }
    }

    return null;
  }

  void _updateScrollbar() {
    if (!_initialPaintDone) return;
    final progress = _computeScrollbarProgress();
    if (progress == null) {
      // Hide scrollbar: remove from layer tree and reset state.
      final scrollbarLayer = _scrollBar.layer;
      if (scrollbarLayer != null) scrollbarLayer.remove();
      return;
    }
    _scrollBar.update(progress, size);

    final scrollbarLayer = _scrollBar.layer;
    if (scrollbarLayer != null) {
      scrollbarLayer.remove();
      _clipLayerHandle.layer?.append(scrollbarLayer);
    }
  }

  // --- Fling ---

  void _startFling(double velocity) {
    _cancelFling();
    _simulation = ClampingScrollSimulation(position: 0.0, velocity: velocity);
    _lastFlingValue = 0.0;
    _flingStartTime = Duration.zero;
    _ensureTickerStarted();
  }

  void _cancelFling() {
    _simulation = null;
  }

  void _ensureTickerStarted() {
    final ticker = _ticker;
    if (ticker != null && !ticker.isActive) {
      ticker.start();
    }
  }

  void _stopTickerIfIdle() {
    if (_simulation == null && _pendingScrollDelta == 0.0) {
      _ticker?.stop();
      // TODO(plugfox): Fetch nearby chunks
      // Mike Matiunin <plugfox@gmail.com>, 14 April 2026
    }
  }

  // --- Ticker callback: ALL scroll logic lives here ---

  void _onTick(Duration elapsed) {
    var delta = _pendingScrollDelta;
    _pendingScrollDelta = 0.0;

    // Advance fling simulation.
    if (_simulation != null) {
      if (_flingStartTime == Duration.zero) _flingStartTime = elapsed;

      final seconds =
          (elapsed - _flingStartTime).inMicroseconds /
          Duration.microsecondsPerSecond;

      if (_simulation!.isDone(seconds)) {
        _cancelFling();
      } else {
        final currentValue = _simulation!.x(seconds);
        delta += currentValue - _lastFlingValue;
        _lastFlingValue = currentValue;
      }
    }

    // Apply combined scroll delta.
    if (delta != 0.0) {
      _controller.applyScrollDelta(delta);
    }

    // Reposition chunks from anchor.
    _layoutHelper.positionFromAnchor(
      controller: _controller,
      dataSource: _dataSource,
      layoutMinChunk: _layoutMinChunk,
      layoutMaxChunk: _layoutMaxChunk,
    );

    // Clamp at conversation boundaries.
    if (_layoutHelper.clampScrollBoundaries(
      _controller,
      _dataSource,
      _layoutMinChunk,
      _layoutMaxChunk,
      size.height,
    )) {
      _cancelFling();
    }

    // Update layers (attach/detach, offsets, re-record).
    _updateLayers();

    // Update scrollbar thumb position.
    _updateScrollbar();

    // Trigger full layout if laid-out chunks don't cover the viewport
    // and more chunks are available beyond the current range.
    if (_needsLayoutExpansion()) {
      markNeedsLayout();
    }

    // Stop ticker if nothing left to do.
    if (_simulation == null) {
      _stopTickerIfIdle();
    }
  }

  /// Whether the laid-out chunk range doesn't cover the viewport
  /// and more chunks are available to fill the gap.
  bool _needsLayoutExpansion() {
    final first = _dataSource.chunks[_layoutMinChunk];
    final last = _dataSource.chunks[_layoutMaxChunk];
    if (first == null || last == null) return true;

    // All chunks completely out of view.
    if (first.offsetY > size.height || last.offsetY + last.height < 0) {
      return true;
    }

    // Gap at bottom with more content available.
    if (last.offsetY + last.height < size.height + _cacheExtent &&
        _dataSource.chunks.containsKey(_layoutMaxChunk + 1)) {
      return true;
    }

    // Gap at top with more content available.
    if (first.offsetY > -_cacheExtent &&
        _dataSource.chunks.containsKey(_layoutMinChunk - 1)) {
      return true;
    }

    return false;
  }

  // --- Layer update (called from Ticker, NOT from paint) ---

  void _updateLayers() {
    if (!_initialPaintDone) return;

    final viewportHeight = size.height;
    final attachExtent = viewportHeight * _attachFactor;
    final detachExtent = viewportHeight * _detachFactor;
    final attachTop = -attachExtent;
    final attachBottom = viewportHeight + attachExtent;
    final detachTop = -detachExtent;
    final detachBottom = viewportHeight + detachExtent;
    final contentWidth = _contentWidth;
    final contentX = _contentX;

    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) continue;

      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null) continue;

        if (render.isEmpty) {
          if (render.isAttached) render.detachLayer();
          continue;
        }

        final top = render.offsetY;
        final bottom = top + render.height;

        if (render.isAttached) {
          // Check detach zone.
          if (bottom < detachTop || top > detachBottom) {
            render.layer?.remove();
            render.detachLayer();
            continue;
          }
          // Update layer offset.
          render.layer!.offset = Offset(contentX, top);
          // Re-record if invalidated or animated.
          if (render.pictureInvalid || render.needsRepaint) {
            render.pictureInvalid = false;
            render.layerWidth = contentWidth;
            render.rerecordPicture();
          }
        } else {
          // Check attach zone.
          if (bottom >= attachTop && top <= attachBottom) {
            render.attachLayer(contentWidth);
            render.layer!.offset = Offset(contentX, top);
            _clipLayerHandle.layer?.append(render.layer!);
          }
        }
      }
    }
  }

  // --- Layout ---

  @override
  void performLayout() {
    assert(() {
      _debugSw
        ..reset()
        ..start();
      return true;
    }());

    final viewportWidth = size.width;
    final viewportHeight = size.height;

    // Width changed → all renders need re-layout.
    if (_lastLayoutWidth != viewportWidth) {
      _lastLayoutWidth = viewportWidth;
      _markAllRendersDirty();
    }

    _expandAndPosition(viewportHeight);

    _layoutHelper.renormalizeAnchor(
      _controller,
      _dataSource,
      _layoutMinChunk,
      _layoutMaxChunk,
      _cacheExtent,
      viewportHeight,
    );

    if (_layoutHelper.clampScrollBoundaries(
      _controller,
      _dataSource,
      _layoutMinChunk,
      _layoutMaxChunk,
      viewportHeight,
    )) {
      _cancelFling();
      // Clamping changed anchor offset — re-expand to cover the viewport.
      _expandAndPosition(viewportHeight);
    }

    _layoutHelper.evictChunks(
      _dataSource.chunks,
      _dataSource.maxChunks,
      _layoutMinChunk,
      _layoutMaxChunk,
    );

    // Fetch dirty chunks when not actively scrolling.
    if (_ticker == null || !_ticker!.isActive) {
      // TODO(plugfox): Fetch nearby chunks around the current range
      // Mike Matiunin <plugfox@gmail.com>, 14 April 2026
    }

    assert(() {
      debugLastLayoutDuration = _debugSw.elapsed;
      _debugSw.stop();
      debugLayoutFrameId++;
      return true;
    }());
  }

  /// Layout chunks from anchor, expand up/down to fill viewport + cacheExtent,
  /// then position all via [positionFromAnchor].
  void _expandAndPosition(double viewportHeight) {
    final bubbleMaxWidth = _bubbleMaxWidth;
    final upperBound = -_cacheExtent;
    final lowerBound = viewportHeight + _cacheExtent;
    final anchorChunkIndex = ChatScrollChunk.chunkOf(
      _controller.anchorMessageId,
    );

    final anchorChunk = _dataSource.chunks[anchorChunkIndex];
    if (anchorChunk == null) return;

    // Layout anchor chunk.
    _layoutHelper.layoutChunkRenders(
      anchorChunk,
      bubbleMaxWidth,
      _messageBuilder,
      ++_accessTick,
    );
    _restoreSelectionOnChunk(anchorChunk);

    // Compute anchor chunk's actual Y position to determine expansion bounds.
    final anchorId = _controller.anchorMessageId;
    final anchorLocalIndex = anchorId - anchorChunk.firstId;
    var beforeAnchorHeight = 0.0;
    for (var i = 0; i < anchorLocalIndex; i++) {
      final r = anchorChunk.renders[i];
      if (r != null) beforeAnchorHeight += r.height;
    }
    final anchorChunkTop = _controller.anchorPixelOffset - beforeAnchorHeight;

    _layoutMinChunk = anchorChunkIndex;
    _layoutMaxChunk = anchorChunkIndex;

    // Expand downward from the actual bottom of the anchor chunk.
    var y = anchorChunkTop + anchorChunk.height;
    for (var ci = anchorChunkIndex + 1; y < lowerBound; ci++) {
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) break;
      _layoutHelper.layoutChunkRenders(
        chunk,
        bubbleMaxWidth,
        _messageBuilder,
        ++_accessTick,
      );
      _restoreSelectionOnChunk(chunk);
      y += chunk.height;
      _layoutMaxChunk = ci;
    }

    // Expand upward from the actual top of the anchor chunk.
    y = anchorChunkTop;
    for (var ci = anchorChunkIndex - 1; y > upperBound; ci--) {
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) break;
      _layoutHelper.layoutChunkRenders(
        chunk,
        bubbleMaxWidth,
        _messageBuilder,
        ++_accessTick,
      );
      _restoreSelectionOnChunk(chunk);
      y -= chunk.height;
      _layoutMinChunk = ci;
    }

    // Position all chunks from anchor (single call, no duplication).
    _layoutHelper.positionFromAnchor(
      controller: _controller,
      dataSource: _dataSource,
      layoutMinChunk: _layoutMinChunk,
      layoutMaxChunk: _layoutMaxChunk,
    );
  }

  // --- Paint (minimal — only initial setup + resize) ---

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(() {
      _debugSw
        ..reset()
        ..start();
      return true;
    }());

    final clipLayer = _clipLayerHandle.layer ??= ClipRectLayer();
    clipLayer.clipRect = offset & size;
    clipLayer.clipBehavior = Clip.hardEdge;

    // On initial paint or after layout, rebuild layer children.
    _updateLayersForPaint(offset);

    context.addLayer(clipLayer);
    _initialPaintDone = true;

    assert(() {
      debugLastPaintDuration = _debugSw.elapsed;
      _debugSw.stop();
      debugPaintFrameId++;
      return true;
    }());
  }

  /// Full layer rebuild during paint (after layout, initial paint, resize).
  void _updateLayersForPaint(Offset offset) {
    final clipLayer = _clipLayerHandle.layer!;
    final viewportHeight = size.height;
    final attachExtent = viewportHeight * _attachFactor;
    final attachTop = -attachExtent;
    final attachBottom = viewportHeight + attachExtent;
    final detachExtent = viewportHeight * _detachFactor;
    final detachTop = -detachExtent;
    final detachBottom = viewportHeight + detachExtent;
    final contentWidth = _contentWidth;
    final contentX = _contentX;

    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) continue;

      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null) continue;

        if (render.isEmpty) {
          if (render.isAttached) render.detachLayer();
          continue;
        }

        final top = render.offsetY;
        final bottom = top + render.height;

        if (render.isAttached) {
          if (bottom < detachTop || top > detachBottom) {
            render.detachLayer();
            continue;
          }
          render.layer!.offset = Offset(offset.dx + contentX, offset.dy + top);
          if (render.pictureInvalid || render.needsRepaint) {
            render.pictureInvalid = false;
            render.layerWidth = contentWidth;
            render.rerecordPicture();
          }
        } else if (bottom >= attachTop && top <= attachBottom) {
          render.attachLayer(contentWidth);
          render.layer!.offset = Offset(offset.dx + contentX, offset.dy + top);
        }
      }
    }

    // Rebuild clip layer children.
    clipLayer.removeAllChildren();
    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) continue;
      for (var i = 0; i < ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null || !render.isAttached) continue;
        clipLayer.append(render.layer!);
      }
    }

    // Append scrollbar layer on top of message layers.
    final progress = _computeScrollbarProgress();
    if (progress != null) {
      _scrollBar.update(progress, size);
      final scrollbarLayer = _scrollBar.layer;
      if (scrollbarLayer != null) {
        clipLayer.append(scrollbarLayer);
      }
    }
  }

  // --- Hit testing ---

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  // --- Render management ---

  void _markAllRendersDirty() {
    for (final chunk in _dataSource.chunks.values) {
      chunk.markRendersDirty();
    }
  }
}
