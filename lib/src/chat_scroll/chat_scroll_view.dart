import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_message_render.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// {@template chat_scroll_view_v2}
/// A custom chat viewport that renders all messages on a single canvas
/// using [ui.Picture] caching per message. No child widgets — everything
/// is drawn by [ChatMessageRender] objects managed by [RenderChatScrollView].
/// {@endtemplate}
class ChatScrollView extends LeafRenderObjectWidget {
  /// {@macro chat_scroll_view_v2}
  const ChatScrollView({
    required this.dataSource,
    required this.controller,
    required this.builder,
    super.key,
  });

  /// The data source that owns message data and fetch contract.
  final ChatDataSource dataSource;

  /// The scroll controller that owns navigation and boundary state.
  final ChatScrollController controller;

  /// Creates a [ChatMessageRender] for each message.
  final ChatMessageRenderFactory builder;

  @override
  RenderChatScrollView createRenderObject(BuildContext context) =>
      RenderChatScrollView(
        dataSource: dataSource,
        controller: controller,
        messageBuilder: builder,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatScrollView renderObject,
  ) {
    renderObject
      ..dataSource = dataSource
      ..controller = controller
      ..messageBuilder = builder;
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
class RenderChatScrollView extends RenderBox {
  RenderChatScrollView({
    required ChatDataSource dataSource,
    required ChatScrollController controller,
    required ChatMessageRenderFactory messageBuilder,
  }) : _dataSource = dataSource,
       _controller = controller,
       _messageBuilder = messageBuilder;

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
  }

  @override
  void detach() {
    _cancelFling();
    _ticker?.dispose();
    _ticker = null;
    _drag?.dispose();
    _drag = null;
    _dataSource.removeDataListener(_onDataChanged);
    _controller.removeJumpListener(_onJump);
    _controller.removeBoundaryListener(_onBoundaryChanged);
    PaintingBinding.instance.systemFonts.removeListener(_onSystemFontsChange);
    super.detach();
  }

  @override
  void dispose() {
    _cancelFling();
    _ticker?.dispose();
    _ticker = null;
    _drag?.dispose();
    _drag = null;
    _clipLayerHandle.layer = null;
    for (final chunk in _dataSource.chunks.values) {
      chunk.disposeRenders();
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
    if (event is PointerDownEvent) _drag?.addPointer(event);
  }

  void _onDragStart(DragStartDetails details) {
    _cancelFling();
    _ensureTickerStarted();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _pendingScrollDelta += details.delta.dy;
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity != null && velocity.abs() >= 50.0) {
      _startFling(velocity);
    } else {
      _stopTickerIfIdle();
    }
  }

  // --- Fling ---

  void _startFling(double velocity) {
    _cancelFling();
    _simulation = ClampingScrollSimulation(
      position: 0.0,
      velocity: velocity,
    );
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
    final viewportWidth = size.width;

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
          render.layer!.offset = Offset(0, top);
          // Re-record if invalidated or animated.
          if (render.pictureInvalid || render.needsRepaint) {
            render.pictureInvalid = false;
            render.layerWidth = viewportWidth;
            render.rerecordPicture();
          }
        } else {
          // Check attach zone.
          if (bottom >= attachTop && top <= attachBottom) {
            render.attachLayer(viewportWidth);
            render.layer!.offset = Offset(0, top);
            _clipLayerHandle.layer?.append(render.layer!);
          }
        }
      }
    }
  }

  // --- Layout ---

  @override
  void performLayout() {
    assert(() { _debugSw..reset()..start(); return true; }());

    final viewportWidth = size.width;
    final viewportHeight = size.height;

    // Width changed → all renders need re-layout.
    if (_lastLayoutWidth != viewportWidth) {
      _lastLayoutWidth = viewportWidth;
      _markAllRendersDirty();
    }

    _expandAndPosition(viewportWidth, viewportHeight);

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
      _expandAndPosition(viewportWidth, viewportHeight);
    }

    _layoutHelper.evictChunks(
      _dataSource.chunks,
      _dataSource.maxChunks,
      _layoutMinChunk,
      _layoutMaxChunk,
    );

    assert(() { debugLastLayoutDuration = _debugSw.elapsed; _debugSw.stop(); debugLayoutFrameId++; return true; }());
  }

  /// Layout chunks from anchor, expand up/down to fill viewport + cacheExtent,
  /// then position all via [positionFromAnchor].
  void _expandAndPosition(double viewportWidth, double viewportHeight) {
    final upperBound = -_cacheExtent;
    final lowerBound = viewportHeight + _cacheExtent;
    final anchorChunkIndex =
        ChatScrollChunk.chunkOf(_controller.anchorMessageId);

    final anchorChunk = _dataSource.chunks[anchorChunkIndex];
    if (anchorChunk == null) return;

    // Layout anchor chunk.
    _layoutHelper.layoutChunkRenders(
      anchorChunk,
      viewportWidth,
      _messageBuilder,
      ++_accessTick,
    );

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
        viewportWidth,
        _messageBuilder,
        ++_accessTick,
      );
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
        viewportWidth,
        _messageBuilder,
        ++_accessTick,
      );
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
    assert(() { _debugSw..reset()..start(); return true; }());

    final clipLayer = _clipLayerHandle.layer ??= ClipRectLayer();
    clipLayer.clipRect = offset & size;
    clipLayer.clipBehavior = Clip.hardEdge;

    // On initial paint or after layout, rebuild layer children.
    _updateLayersForPaint(offset);

    context.addLayer(clipLayer);
    _initialPaintDone = true;

    assert(() { debugLastPaintDuration = _debugSw.elapsed; _debugSw.stop(); debugPaintFrameId++; return true; }());
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
    final viewportWidth = size.width;

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
          render.layer!.offset = Offset(offset.dx, offset.dy + top);
          if (render.pictureInvalid || render.needsRepaint) {
            render.pictureInvalid = false;
            render.layerWidth = viewportWidth;
            render.rerecordPicture();
          }
        } else if (bottom >= attachTop && top <= attachBottom) {
          render.attachLayer(viewportWidth);
          render.layer!.offset = Offset(offset.dx, offset.dy + top);
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
