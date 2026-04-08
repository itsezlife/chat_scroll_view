import 'dart:collection';
import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_scroll_view_common.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Chunk of chat messages used for pagination and rendering.
///
/// Holds both message data and render objects in parallel fixed-size arrays.
/// Chunk index is calculated by shifting the message id right by [kBits].
class _ChatScrollChunk {
  static const int kBits = 6;
  static const int kSize = 64; // 1 << kBits

  /// Get the chunk index for a given message id.
  /// Dart's `>>` is arithmetic shift — works correctly for negative IDs.
  static int chunkOf(int messageId) => messageId >> kBits;

  /// Get the first message id for a given chunk index.
  static int firstIdOf(int chunkIndex) => chunkIndex << kBits;

  _ChatScrollChunk({required this.index})
    : messages = List<IChatMessage?>.filled(kSize, null, growable: false),
      renders = List<ChatMessageRender?>.filled(kSize, null, growable: false),
      firstId = firstIdOf(index);

  /// The chunk index, calculated as messageId >> kBits.
  /// Can be negative for messages with negative IDs.
  final int index;

  /// The first message id in this chunk (inclusive).
  final int firstId;

  /// The last message id in this chunk (inclusive).
  int get lastId => firstId + kSize - 1;

  /// Message data — populated from fetch results.
  final List<IChatMessage?> messages;

  /// Render objects — created lazily by the viewport.
  final List<ChatMessageRender?> renders;

  /// Data status (dirty, fetching, error, valid).
  ChatMessageStatus status = ChatMessageStatus.dirty;

  /// Monotonic access tick — bumped on layout to track LRU order.
  int lastAccessTick = 0;

  /// Y offset of this chunk's first message within the viewport.
  double offsetY = 0.0;

  /// Total height of all laid-out messages in this chunk.
  double height = 0.0;

  /// Mark all renders in this chunk as dirty, causing them to be re-laid out
  /// and re-painted on the next frame.
  void markRendersDirty() {
    for (final render in renders) {
      if (render == null) continue;
      render.dirty = true;
      render.invalidatePaint();
    }
  }

  /// Dispose all renders in this chunk and clear the list.
  void disposeRenders() {
    for (var i = 0; i < renders.length; i++) {
      renders[i]?.dispose();
      renders[i] = null;
    }
  }
}

/// Lightweight render object for a single chat message.
///
/// Owns layout state (e.g. [TextPainter]s) between [performLayout] and
/// [paintMessage], so work done during layout is reused at paint time.
///
/// Created by the [ChatMessageRenderFactory] passed to [ChatScrollView].
/// The viewport manages [height], [offsetY], and [dirty] fields.
///
/// ### Compositing architecture
///
/// Each message owns an [OffsetLayer] → [PictureLayer] subtree.
/// The viewport calls [attachLayer] when the message enters the attach zone
/// and [detachLayer] when it leaves the detach zone (wider than attach zone
/// to avoid thrashing on small scroll oscillations).
///
/// When attached, [paintMessage] output is recorded into a [ui.Picture]
/// and stored in the [PictureLayer]. Scrolling only updates
/// [OffsetLayer.offset] — no re-recording.
///
/// For animated messages, override [needsRepaint] to return `true`.
/// The viewport will call [rerecordPicture] every frame while active.
abstract class ChatMessageRender {
  /// Called when message data or chunk status may have changed.
  ///
  /// [message] is `null` when the slot has no content yet (chunk just created,
  /// fetch in progress). Compare with previous values (e.g. via [identical]
  /// for message, `==` for status) and set [dirty] or call [invalidatePaint]
  /// as appropriate.
  void update(IChatMessage? message, ChatMessageStatus status);

  /// Lay out the message for the given [availableWidth].
  /// Returns the computed height.
  double performLayout(double availableWidth);

  /// Paint the message content onto [canvas] within [size].
  ///
  /// Override this to define what the message looks like.
  /// The result is recorded into a [ui.Picture] and cached in
  /// a [PictureLayer] inside this render's [OffsetLayer].
  void paintMessage(Canvas canvas, Size size);

  /// Whether this render has no content to display.
  ///
  /// Empty renders (e.g. null slots beyond the real message range in partial
  /// chunks) skip layer creation entirely — no [OffsetLayer], no
  /// [PictureLayer], no [paintMessage] call.
  ///
  /// Defaults to `true` when [height] is zero.
  bool get isEmpty => height == 0.0;

  /// Whether this message needs its [PictureLayer] re-recorded every frame.
  ///
  /// Override and return `true` for animations (hover, buttons, etc.).
  /// The viewport will call [rerecordPicture] and schedule another frame.
  bool get needsRepaint => false;

  /// Hit-test at [position] (local to this message's origin).
  ///
  /// Returns `true` if the message handles the hit.
  bool hitTest(Offset position) => false;

  /// Invalidate the cached picture, causing [paintMessage] to be called
  /// again on the next paint frame. Does not trigger layout.
  ///
  /// Safe to call during layout — the actual re-recording is deferred
  /// to the paint phase.
  void invalidatePaint() {
    _pictureInvalid = true;
  }

  /// Whether the cached picture needs re-recording in the next paint pass.
  bool _pictureInvalid = false;

  /// Release resources (TextPainters, images, etc.).
  @mustCallSuper
  void dispose() {
    if (_attached) detachLayer();
  }

  // --- Layer management (called by viewport during paint phase) ---

  /// Create the [OffsetLayer] → [PictureLayer] subtree and record
  /// the initial picture via [paintMessage].
  @nonVirtual
  void attachLayer(double width) {
    assert(!_attached);
    _layerWidth = width;
    _layer = OffsetLayer(offset: Offset(0, offsetY));
    _attached = true;
    _pictureInvalid = false;
    rerecordPicture();
  }

  /// Dispose the [PictureLayer] and [OffsetLayer], releasing the
  /// cached [ui.Picture].
  @nonVirtual
  void detachLayer() {
    assert(_attached);
    _disposePictureLayer();
    _layer = null;
    _attached = false;
  }

  /// Re-record [paintMessage] into a fresh [PictureLayer].
  /// Used for animations and after [invalidatePaint] while attached.
  @nonVirtual
  void rerecordPicture() {
    assert(_attached);
    _disposePictureLayer();
    final rect = Rect.fromLTWH(0, 0, _layerWidth, height);
    final recorder = ui.PictureRecorder();
    paintMessage(Canvas(recorder, rect), Size(_layerWidth, height));
    _pictureLayer = PictureLayer(rect)..picture = recorder.endRecording();
    _layer!.append(_pictureLayer!);
  }

  void _disposePictureLayer() {
    if (_pictureLayer case final pictureLayer?) {
      pictureLayer.remove();
      _pictureLayer = null;
    }
  }

  // --- Layer fields ---

  /// The compositing layer for this message, held via [LayerHandle]
  /// to prevent disposal when the parent [ClipRectLayer] removes children.
  final LayerHandle<OffsetLayer> _layerHandle = LayerHandle<OffsetLayer>();

  /// Convenience accessor for the underlying [OffsetLayer].
  OffsetLayer? get _layer => _layerHandle.layer;
  set _layer(OffsetLayer? value) => _layerHandle.layer = value;

  /// The picture layer holding the recorded [paintMessage] output.
  PictureLayer? _pictureLayer;

  /// Whether this render has a live layer subtree.
  bool _attached = false;

  /// Width used for recording (set at [attachLayer] time).
  double _layerWidth = 0.0;

  // --- Managed by the viewport (not overridable) ---

  /// The Y offset within the viewport (set during layout).
  @nonVirtual
  double offsetY = 0.0;

  /// The computed height of this message (set after [performLayout]).
  @nonVirtual
  double height = 0.0;

  /// Whether this message needs to be re-laid out and re-painted.
  @nonVirtual
  bool dirty = true;
}

/// Creates a [ChatMessageRender] for the given [message].
/// [message] is `null` for slots that have no content yet.
typedef ChatMessageRenderFactory =
    ChatMessageRender Function(IChatMessage? message);

// --- Controller ---

/// Controller for [ChatScrollView].
///
/// Owns the data (chunks), anchor state, and fetch function.
/// The [RenderChatScrollView] reads data from this controller
/// and listens for changes via [ChangeNotifier].
abstract class ChatScrollController extends ChangeNotifier {
  /// Fetch messages by ID range or timestamp.
  /// `from` and `to` are inclusive message IDs, where `from <= to`.
  /// `after` used for time-based pagination,
  /// fetching only updated messages after the given timestamp.
  /// If nothing is provided, fetch should return the most recent messages to
  /// dermine the initial scroll position, anchoring on the most recent message.
  Future<List<IChatMessage>> fetch({int? from, int? to, DateTime? after});

  // --- Chunk storage ---

  /// Maximum number of chunks to keep in memory.
  /// Override to control the memory/re-fetch tradeoff.
  /// Default 16 ≈ 1024 messages.
  int get maxChunks => 16;

  /// Unordered map of message chunks by chunk index.
  final Map<int, _ChatScrollChunk> _chunks = HashMap<int, _ChatScrollChunk>();

  /// Get a message by ID from the chunk cache.
  IChatMessage? getMessage(int messageId) {
    final chunkIndex = _ChatScrollChunk.chunkOf(messageId);
    final chunk = _chunks[chunkIndex];
    if (chunk == null) return null;
    return chunk.messages[messageId - chunk.firstId];
  }

  /// Upsert a message into the chunk cache.
  /// Creates the chunk if it does not exist yet.
  void upsertMessage(IChatMessage message) {
    final chunkIndex = _ChatScrollChunk.chunkOf(message.id);
    final chunk = _chunks.putIfAbsent(
      chunkIndex,
      () => _ChatScrollChunk(index: chunkIndex),
    );
    chunk.messages[message.id - chunk.firstId] = message;
    _notifyData();
  }

  /// Upsert multiple messages into the chunk cache.
  /// Creates chunks as needed for messages that fall into uncached chunks.
  void upsertMessages(Iterable<IChatMessage> messages) {
    var changed = false;
    for (final message in messages) {
      final chunkIndex = _ChatScrollChunk.chunkOf(message.id);
      final chunk = _chunks.putIfAbsent(
        chunkIndex,
        () => _ChatScrollChunk(index: chunkIndex),
      );
      chunk.messages[message.id - chunk.firstId] = message;
      changed = true;
    }
    if (changed) _notifyData();
  }

  // --- Notification type ---

  /// When `true`, the next [notifyListeners] is a scroll-only change
  /// (only [anchorPixelOffset] moved). The viewport uses this to skip
  /// relayout and only update [OffsetLayer] offsets.
  bool _scrollOnly = false;

  void _notifyScroll() {
    _scrollOnly = true;
    notifyListeners();
    _scrollOnly = false;
  }

  void _notifyData() {
    _scrollOnly = false;
    notifyListeners();
  }

  // --- Anchor state ---

  /// The message ID used as layout origin.
  int get anchorMessageId => _anchorMessageId;
  int _anchorMessageId = 0;

  /// Set a new anchor message ID and notify listeners to trigger relayout.
  set anchorMessageId(int value) {
    if (_anchorMessageId == value) return;
    _anchorMessageId = value;
    _notifyData();
  }

  /// Pixel offset of the anchor message's top edge from the viewport top.
  double get anchorPixelOffset => _anchorPixelOffset;
  double _anchorPixelOffset = 0.0;

  /// Set a new anchor pixel offset and notify listeners.
  /// This is a scroll-only change — the viewport updates layer offsets
  /// without relaying out message renders.
  set anchorPixelOffset(double value) {
    if (_anchorPixelOffset == value) return;
    _anchorPixelOffset = value;
    _notifyScroll();
  }

  /// Jump to a specific message, resetting the anchor.
  void jumpTo(int messageId) {
    _anchorMessageId = messageId;
    _anchorPixelOffset = 0.0;
    _notifyData();
  }

  // --- Boundary state ---

  /// Whether the oldest message in the conversation has been fetched.
  bool get reachedOldest => _reachedOldest;
  bool _reachedOldest = false;
  set reachedOldest(bool value) {
    if (_reachedOldest == value) return;
    _reachedOldest = value;
    _notifyData();
  }

  /// Whether the newest message in the conversation has been fetched.
  bool get reachedNewest => _reachedNewest;
  bool _reachedNewest = false;
  set reachedNewest(bool value) {
    if (_reachedNewest == value) return;
    _reachedNewest = value;
    _notifyData();
  }

  /// The ID of the oldest known message, if any.
  int? oldestKnownId;

  /// The ID of the newest known message, if any.
  int? newestKnownId;
}

/// {@template chat_scroll_view}
/// ChatScrollView widget.
///
/// A custom chat viewport that renders all messages on a single canvas
/// using [ui.Picture] caching per message. No child widgets — everything
/// is drawn directly by the [RenderChatScrollView].
/// {@endtemplate}
class ChatScrollView extends LeafRenderObjectWidget {
  /// {@macro chat_scroll_view}
  const ChatScrollView({
    required this.controller,
    required this.builder,
    super.key, // ignore: unused_element_parameter
  });

  /// The controller that owns message data and anchor state.
  final ChatScrollController controller;

  /// Creates a [ChatMessageRender] for each message.
  /// Receives `null` for slots that have no content yet.
  final ChatMessageRenderFactory builder;

  @override
  RenderChatScrollView createRenderObject(BuildContext context) =>
      RenderChatScrollView(controller: controller, messageBuilder: builder);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatScrollView renderObject,
  ) {
    renderObject
      ..controller = controller
      ..messageBuilder = builder;
  }
}

/// The render object for [ChatScrollView].
///
/// Reads message data and anchor state from [ChatScrollController].
/// Each visible message owns an [OffsetLayer] → [PictureLayer] subtree.
/// Scrolling updates [OffsetLayer.offset] — GPU composites without
/// re-recording pictures.
class RenderChatScrollView extends RenderBox {
  RenderChatScrollView({
    required ChatScrollController controller,
    required ChatMessageRenderFactory messageBuilder,
  }) : _controller = controller,
       _messageBuilder = messageBuilder;

  // --- Debug instrumentation (zero-cost in release) ---

  /// Duration of the last [performLayout] call. Set only in debug/profile mode.
  @visibleForTesting
  Duration debugLastLayoutDuration = Duration.zero;

  /// Monotonic counter incremented each time [performLayout] runs.
  @visibleForTesting
  int debugLayoutFrameId = 0;

  /// Duration of the last [paint] call. Set only in debug/profile mode.
  @visibleForTesting
  Duration debugLastPaintDuration = Duration.zero;

  /// Monotonic counter incremented each time [paint] runs.
  @visibleForTesting
  int debugPaintFrameId = 0;

  /// Number of currently attached (has live layer subtree) renders.
  @visibleForTesting
  int get debugAttachedRenderCount {
    var count = 0;
    for (final chunk in _controller._chunks.values) {
      for (var i = 0; i < _ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render != null && render._attached) count++;
      }
    }
    return count;
  }

  /// Total number of created render objects across all chunks.
  @visibleForTesting
  int get debugTotalRenderCount {
    var count = 0;
    for (final chunk in _controller._chunks.values) {
      for (var i = 0; i < _ChatScrollChunk.kSize; i++) {
        if (chunk.renders[i] != null) count++;
      }
    }
    return count;
  }

  /// Number of chunks currently held by the controller.
  @visibleForTesting
  int get debugChunkCount => _controller._chunks.length;

  // --- Controller ---

  /// The controller that owns message data and anchor state.
  ChatScrollController _controller;

  /// Update the controller,
  /// removing listener from the old one and adding to the new one.
  set controller(ChatScrollController value) {
    if (identical(_controller, value)) return;
    _controller.removeListener(_onControllerChanged);
    _controller = value;
    _controller.addListener(_onControllerChanged);
    markNeedsLayout();
  }

  /// Whether the pending paint was triggered by a scroll-only change.
  /// Captured synchronously in [_onControllerChanged] because the
  /// controller resets [_scrollOnly] immediately after notifying.
  bool _pendingScrollOnly = false;

  void _onControllerChanged() {
    if (_controller._scrollOnly) {
      // Scroll-only: just update OffsetLayer offsets, no relayout.
      if (!_layoutPending) {
        _pendingScrollOnly = true;
        markNeedsPaint();
      }
    } else {
      _pendingScrollOnly = false;
      markNeedsLayout();
    }
  }

  // --- Configuration ---

  /// Factory to create a [ChatMessageRender] for each message.
  ChatMessageRenderFactory _messageBuilder;

  /// Update the message builder and mark all renders dirty to trigger re-layout
  /// and re-paint with the new builder.
  set messageBuilder(ChatMessageRenderFactory value) {
    if (identical(_messageBuilder, value)) return;
    _messageBuilder = value;
    _markAllRendersDirty();
    markNeedsLayout();
  }

  /// Extra pixels to lay out beyond the visible viewport.
  double _cacheExtent = 250.0;

  /// Update the cache extent and trigger layout if it changes.
  set cacheExtent(double value) {
    if (_cacheExtent == value) return;
    _cacheExtent = value;
    markNeedsLayout();
  }

  // --- Attach / detach zones (hysteresis) ---

  /// Layers are created when a render enters this distance from viewport edges.
  static const double _attachFactor = 1.0;

  /// Layers are disposed when a render leaves this (wider) distance.
  /// Must be > [_attachFactor] to prevent thrashing on small scroll jitter.
  static const double _detachFactor = 1.7;

  /// Monotonic counter for LRU chunk eviction.
  int _accessTick = 0;

  /// Range of chunk indices currently laid out (inclusive).
  int _layoutMinChunk = 0;
  int _layoutMaxChunk = -1; // empty range initially

  // --- Gesture & scroll physics ---

  VerticalDragGestureRecognizer? _drag;
  ClampingScrollSimulation? _simulation;
  Duration? _flingStartTime;
  double _lastFlingValue = 0.0;

  /// Clip layer owned by this render object, appended as child of
  /// the framework-managed [OffsetLayer] (which is [layer]).
  /// Held via [LayerHandle] to prevent the framework from disposing it
  /// when [OffsetLayer.removeAllChildren] is called between paint calls.
  final LayerHandle<ClipRectLayer> _clipLayerHandle =
      LayerHandle<ClipRectLayer>();

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
    _controller.addListener(_onControllerChanged);
    PaintingBinding.instance.systemFonts.addListener(_onSystemFontsChange);
    _drag = VerticalDragGestureRecognizer()
      ..onStart = _onDragStart
      ..onUpdate = _onDragUpdate
      ..onEnd = _onDragEnd;
  }

  @override
  void detach() {
    _cancelFling();
    _drag?.dispose();
    _drag = null;
    _controller.removeListener(_onControllerChanged);
    PaintingBinding.instance.systemFonts.removeListener(_onSystemFontsChange);
    super.detach();
  }

  /// Mark all renders dirty when system fonts change,
  /// as this may affect layout.
  void _onSystemFontsChange() {
    _markAllRendersDirty();
    markNeedsLayout();
  }

  @override
  void dispose() {
    _cancelFling();
    _drag?.dispose();
    _drag = null;
    _clipLayerHandle.layer = null;
    for (final chunk in _controller._chunks.values) {
      chunk.disposeRenders();
    }
    super.dispose();
  }

  // --- Gesture handling ---

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    assert(debugHandleEvent(event, entry));
    if (event is PointerDownEvent) _drag?.addPointer(event);
  }

  void _onDragStart(DragStartDetails details) {
    _cancelFling();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _applyScrollDelta(details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null || velocity.abs() < 50.0) return;
    _startFling(velocity);
  }

  // --- Fling (inertia, paint-driven) ---

  void _startFling(double velocity) {
    _cancelFling();
    _simulation = ClampingScrollSimulation(position: 0.0, velocity: velocity);
    _lastFlingValue = 0.0;
    // _flingStartTime is set on the first _advanceFling call inside paint,
    // where currentFrameTimeStamp is guaranteed to be valid.
    _flingStartTime = null;
    markNeedsPaint();
  }

  void _cancelFling() {
    _simulation = null;
    _flingStartTime = null;
  }

  /// Advance the fling simulation using the current frame timestamp.
  /// Called from [paint]; schedules another paint if not done.
  void _advanceFling() {
    final simulation = _simulation;
    if (simulation == null) return;

    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final startTime = _flingStartTime ??= now;

    final elapsed = now - startTime;
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;

    if (simulation.isDone(seconds)) {
      _cancelFling();
      return;
    }

    final currentValue = simulation.x(seconds);
    final delta = currentValue - _lastFlingValue;
    _lastFlingValue = currentValue;
    _controller._anchorPixelOffset += delta;
  }

  /// Apply a scroll delta from drag gestures.
  void _applyScrollDelta(double delta) {
    if (delta == 0.0) return;
    _controller._anchorPixelOffset += delta;
    if (!_layoutPending) {
      _pendingScrollOnly = true;
      markNeedsPaint();
    }
  }

  /// Tracks whether a layout pass is pending, so that scroll-only
  /// updates (drag/fling) don't call [markNeedsPaint] on a dirty object.
  bool _layoutPending = true; // starts true, cleared after first layout

  @override
  void markNeedsLayout() {
    _layoutPending = true;
    super.markNeedsLayout();
  }

  // --- Layout ---

  /// Last width used for laying out message renders.
  double _lastLayoutWidth = 0.0;

  @override
  void performLayout() {
    final sw = Stopwatch()..start();
    _performLayoutImpl();
    debugLastLayoutDuration = sw.elapsed;
    debugLayoutFrameId++;
  }

  void _performLayoutImpl() {
    _layoutPending = false;
    final viewportWidth = size.width;
    final viewportHeight = size.height;

    // If viewport width changed, all renders need re-layout
    // (text wrapping depends on available width).
    if (_lastLayoutWidth != viewportWidth) {
      _lastLayoutWidth = viewportWidth;
      _markAllRendersDirty();
    }
    final upperBound = -_cacheExtent;
    final lowerBound = viewportHeight + _cacheExtent;

    final anchorId = _controller.anchorMessageId;
    final anchorOffset = _controller.anchorPixelOffset;
    final anchorChunkIndex = _ChatScrollChunk.chunkOf(anchorId);

    // Layout anchor chunk
    final anchorChunk = _controller._chunks[anchorChunkIndex];
    if (anchorChunk == null) return;

    _layoutChunkRenders(anchorChunk, viewportWidth);

    // Position anchor chunk so that anchorId's top edge is at anchorOffset
    var beforeAnchorHeight = 0.0;
    final anchorLocalIndex = anchorId - anchorChunk.firstId;
    for (var i = 0; i < anchorLocalIndex; i++) {
      final r = anchorChunk.renders[i];
      if (r != null) beforeAnchorHeight += r.height;
    }
    anchorChunk.offsetY = anchorOffset - beforeAnchorHeight;
    _positionChunkRenders(anchorChunk);

    _layoutMinChunk = anchorChunkIndex;
    _layoutMaxChunk = anchorChunkIndex;

    // Layout chunks downward
    var y = anchorChunk.offsetY + anchorChunk.height;
    for (var ci = anchorChunkIndex + 1; y < lowerBound; ci++) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) break;
      _layoutChunkRenders(chunk, viewportWidth);
      chunk.offsetY = y;
      _positionChunkRenders(chunk);
      y += chunk.height;
      _layoutMaxChunk = ci;
    }

    // Layout chunks upward
    y = anchorChunk.offsetY;
    for (var ci = anchorChunkIndex - 1; y > upperBound; ci--) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) break;
      _layoutChunkRenders(chunk, viewportWidth);
      y -= chunk.height;
      chunk.offsetY = y;
      _positionChunkRenders(chunk);
      _layoutMinChunk = ci;
    }

    // Re-normalize anchor if it drifted beyond cacheExtent from viewport.
    _renormalizeAnchor();

    // Clamp scroll at conversation boundaries.
    _clampScrollBoundaries();

    // Evict old chunks if we exceed the limit,
    // prioritizing keeping currently visible chunks.
    _evictRenderChunks();
  }

  /// Layout all renders in [chunk], recomputing [chunk.height].
  void _layoutChunkRenders(_ChatScrollChunk chunk, double viewportWidth) {
    chunk.lastAccessTick = ++_accessTick;
    var totalHeight = 0.0;
    for (var i = 0; i < _ChatScrollChunk.kSize; i++) {
      final message = chunk.messages[i];
      var render = chunk.renders[i];
      if (render == null) {
        render = _messageBuilder(message);
        chunk.renders[i] = render;
      }
      render.update(message, chunk.status);
      if (render.dirty) {
        render.height = render.performLayout(viewportWidth);
        render.invalidatePaint();
        render.dirty = false;
      }
      totalHeight += render.height;
    }
    chunk.height = totalHeight;
  }

  /// Recompute all chunk and render [offsetY] positions from the current
  /// anchor state without relaying out renders. Used on scroll-only changes
  /// where heights have not changed — only the anchor pixel offset moved.
  void _repositionChunks() {
    final anchorId = _controller.anchorMessageId;
    final anchorOffset = _controller.anchorPixelOffset;
    final anchorChunkIndex = _ChatScrollChunk.chunkOf(anchorId);

    final anchorChunk = _controller._chunks[anchorChunkIndex];
    if (anchorChunk == null) return;

    // Recompute anchor chunk offsetY.
    var beforeAnchorHeight = 0.0;
    final anchorLocalIndex = anchorId - anchorChunk.firstId;
    for (var i = 0; i < anchorLocalIndex; i++) {
      final r = anchorChunk.renders[i];
      if (r != null) beforeAnchorHeight += r.height;
    }
    anchorChunk.offsetY = anchorOffset - beforeAnchorHeight;
    _positionChunkRenders(anchorChunk);

    // Reposition chunks downward.
    var y = anchorChunk.offsetY + anchorChunk.height;
    for (var ci = anchorChunkIndex + 1; ci <= _layoutMaxChunk; ci++) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) break;
      chunk.offsetY = y;
      _positionChunkRenders(chunk);
      y += chunk.height;
    }

    // Reposition chunks upward.
    y = anchorChunk.offsetY;
    for (var ci = anchorChunkIndex - 1; ci >= _layoutMinChunk; ci--) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) break;
      y -= chunk.height;
      chunk.offsetY = y;
      _positionChunkRenders(chunk);
    }
  }

  /// Set [offsetY] on each render in [chunk] based on [chunk.offsetY].
  void _positionChunkRenders(_ChatScrollChunk chunk) {
    var y = chunk.offsetY;
    for (var i = 0; i < _ChatScrollChunk.kSize; i++) {
      final render = chunk.renders[i];
      if (render == null) continue;
      render.offsetY = y;
      y += render.height;
    }
  }

  // --- Anchor re-normalization ---

  /// If the anchor message drifted beyond [_cacheExtent] from the viewport,
  /// silently reassign to the first visible message. Direct field writes —
  /// no [notifyListeners] since we are inside [performLayout].
  void _renormalizeAnchor() {
    final anchorId = _controller.anchorMessageId;
    final anchorChunkIndex = _ChatScrollChunk.chunkOf(anchorId);
    final anchorChunk = _controller._chunks[anchorChunkIndex];
    if (anchorChunk == null) return;

    final anchorLocalIndex = anchorId - anchorChunk.firstId;
    final anchorRender = anchorChunk.renders[anchorLocalIndex];
    if (anchorRender == null) return;

    final anchorTop = anchorRender.offsetY;
    final anchorBottom = anchorTop + anchorRender.height;
    final viewportHeight = size.height;

    // Anchor still within viewport + cacheExtent — nothing to do.
    if (anchorBottom >= -_cacheExtent &&
        anchorTop <= viewportHeight + _cacheExtent) {
      return;
    }

    // Find first message whose bottom edge is below viewport top.
    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) continue;
      for (var i = 0; i < _ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null || render.isEmpty) continue;
        if (render.offsetY + render.height > 0) {
          _controller._anchorMessageId = chunk.firstId + i;
          _controller._anchorPixelOffset = render.offsetY;
          return;
        }
      }
    }
  }

  // --- Boundary clamping ---

  /// Clamp scroll so content doesn't detach from viewport edges
  /// when the conversation boundary has been reached.
  void _clampScrollBoundaries() {
    final viewportHeight = size.height;

    // Bottom: if newest message reached AND the newest chunk is in the
    // laid-out range, pin content bottom to viewport bottom.
    if (_controller._reachedNewest && _controller.newestKnownId != null) {
      final newestChunkIndex = _ChatScrollChunk.chunkOf(
        _controller.newestKnownId!,
      );
      if (newestChunkIndex <= _layoutMaxChunk) {
        final lastChunk = _controller._chunks[_layoutMaxChunk];
        if (lastChunk != null) {
          final contentBottom = lastChunk.offsetY + lastChunk.height;
          if (contentBottom < viewportHeight) {
            final correction = viewportHeight - contentBottom;
            _controller._anchorPixelOffset += correction;
            _repositionAfterClamp();
            _cancelFling();
          }
        }
      }
    }

    // Top: if oldest message reached AND the oldest chunk is in the
    // laid-out range, pin content top to viewport top.
    if (_controller._reachedOldest && _controller.oldestKnownId != null) {
      final oldestChunkIndex = _ChatScrollChunk.chunkOf(
        _controller.oldestKnownId!,
      );
      if (oldestChunkIndex >= _layoutMinChunk) {
        final firstChunk = _controller._chunks[_layoutMinChunk];
        if (firstChunk != null) {
          final contentTop = firstChunk.offsetY;
          if (contentTop > 0) {
            _controller._anchorPixelOffset -= contentTop;
            _repositionAfterClamp();
            _cancelFling();
          }
        }
      }
    }
  }

  /// Recompute chunk/render positions after a boundary clamp correction.
  void _repositionAfterClamp() {
    final anchorId = _controller._anchorMessageId;
    final anchorOffset = _controller._anchorPixelOffset;
    final anchorChunkIndex = _ChatScrollChunk.chunkOf(anchorId);
    final anchorChunk = _controller._chunks[anchorChunkIndex];
    if (anchorChunk == null) return;

    var beforeAnchorHeight = 0.0;
    final anchorLocalIndex = anchorId - anchorChunk.firstId;
    for (var i = 0; i < anchorLocalIndex; i++) {
      final r = anchorChunk.renders[i];
      if (r != null) beforeAnchorHeight += r.height;
    }
    anchorChunk.offsetY = anchorOffset - beforeAnchorHeight;
    _positionChunkRenders(anchorChunk);

    var y = anchorChunk.offsetY + anchorChunk.height;
    for (var ci = anchorChunkIndex + 1; ci <= _layoutMaxChunk; ci++) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) break;
      chunk.offsetY = y;
      _positionChunkRenders(chunk);
      y += chunk.height;
    }

    y = anchorChunk.offsetY;
    for (var ci = anchorChunkIndex - 1; ci >= _layoutMinChunk; ci--) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) break;
      y -= chunk.height;
      chunk.offsetY = y;
      _positionChunkRenders(chunk);
    }
  }

  // --- Paint (layer-tree based) ---

  @override
  void paint(PaintingContext context, Offset offset) {
    final sw = Stopwatch()..start();
    _paintImpl(context, offset);
    debugLastPaintDuration = sw.elapsed;
    debugPaintFrameId++;
  }

  void _paintImpl(PaintingContext context, Offset offset) {
    // Reuse or create the clip layer (child of framework-managed OffsetLayer).
    final clipLayer = _clipLayerHandle.layer ??= ClipRectLayer();
    clipLayer.clipRect = offset & size;
    clipLayer.clipBehavior = Clip.hardEdge;

    final viewportHeight = size.height;
    final attachExtent = viewportHeight * _attachFactor;
    final detachExtent = viewportHeight * _detachFactor;
    final attachTop = -attachExtent;
    final attachBottom = viewportHeight + attachExtent;
    final detachTop = -detachExtent;
    final detachBottom = viewportHeight + detachExtent;
    final viewportWidth = size.width;

    // On scroll-only changes, performLayout was skipped — recompute
    // chunk/render offsetY positions from the current anchor state.
    // If the scroll moved so far that laid-out chunks no longer cover
    // the viewport, fall back to a full layout pass.
    // Advance fling simulation (paint-driven, no Ticker).
    if (_simulation != null) {
      _advanceFling();
      _pendingScrollOnly = true;
    }

    if (_pendingScrollOnly) {
      _pendingScrollOnly = false;
      _repositionChunks();

      // Apply boundary clamping during scroll-only updates too.
      _clampScrollBoundaries();

      final first = _controller._chunks[_layoutMinChunk];
      final last = _controller._chunks[_layoutMaxChunk];
      if (first == null ||
          last == null ||
          first.offsetY > viewportHeight ||
          last.offsetY + last.height < 0) {
        // Chunks no longer cover the viewport — need full layout.
        // Defer to post-frame since we cannot call markNeedsLayout
        // during paint.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          markNeedsLayout();
        });
        return;
      }
    }

    var hasAnimating = false;

    // Single pass: attach/detach layers, update offsets, re-record animations.
    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) continue;

      for (var i = 0; i < _ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null) continue;

        // Skip empty renders — no layer needed for zero-height slots.
        if (render.isEmpty) {
          if (render._attached) render.detachLayer();
          continue;
        }

        final top = render.offsetY;
        final bottom = top + render.height;

        if (render._attached) {
          // Check if render left the detach zone.
          if (bottom < detachTop || top > detachBottom) {
            render.detachLayer();
            continue;
          }
          // Update layer offset for scroll.
          render._layer!.offset = Offset(offset.dx, offset.dy + top);
          // Re-record invalidated or animated renders.
          if (render._pictureInvalid || render.needsRepaint) {
            render._pictureInvalid = false;
            render._layerWidth = viewportWidth;
            render.rerecordPicture();
            if (render.needsRepaint) hasAnimating = true;
          }
        } else {
          // Check if render entered the attach zone.
          if (bottom >= attachTop && top <= attachBottom) {
            render.attachLayer(viewportWidth);
            render._layer!.offset = Offset(offset.dx, offset.dy + top);
          }
        }
      }
    }

    // Rebuild clip layer children: remove all, re-append attached layers.
    // O(n) where n ≈ 10-20 attached renders — trivial cost.
    clipLayer.removeAllChildren();
    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) continue;
      for (var i = 0; i < _ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null || !render._attached) continue;
        clipLayer.append(render._layer!);
      }
    }

    // Append clip layer to the framework-managed OffsetLayer.
    context.addLayer(clipLayer);

    // TODO: Sticky overlays (avatars, date separators) — append a
    // PictureLayer last in clipLayer so it draws on top of all messages.

    // Schedule next frame for animations or active fling.
    // Cannot call markNeedsPaint() during paint — defer to post-frame.
    if (hasAnimating || _simulation != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_layoutPending) markNeedsPaint();
      });
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

  // --- Render management (via controller's chunks) ---

  /// Invalidate the cached picture for [messageId] without triggering layout.
  /// Use for animations, selection highlights, or any visual-only change.
  void markMessageNeedsPaint(int messageId) {
    final chunkIndex = _ChatScrollChunk.chunkOf(messageId);
    final chunk = _controller._chunks[chunkIndex];
    if (chunk == null) return;
    final render = chunk.renders[messageId - chunk.firstId];
    if (render == null) return;
    render.invalidatePaint();
    markNeedsPaint();
  }

  /// Mark all renders in all chunks as dirty, causing them to be re-laid out
  /// and re-painted on the next frame.
  /// Use for global changes like font updates.
  void _markAllRendersDirty() {
    for (final chunk in _controller._chunks.values) {
      chunk.markRendersDirty();
    }
  }

  /// Evict old chunks if we exceed [ChatScrollController.maxChunks].
  /// Never evict chunks in the current layout range or the two newest chunks
  /// (most recent messages the user will likely return to).
  /// Among the rest, evict the oldest based on [_ChatScrollChunk.lastAccessTick].
  void _evictRenderChunks() {
    final chunks = _controller._chunks;
    final toRemove = chunks.length - _controller.maxChunks;
    if (toRemove <= 0) return;

    // Find the two newest chunks by index — these are never evicted.
    var maxChunkIndex = -1 >>> 1; // will be overwritten
    var secondMaxChunkIndex = maxChunkIndex;
    var first = true;
    for (final chunk in chunks.values) {
      if (first) {
        maxChunkIndex = chunk.index;
        secondMaxChunkIndex = chunk.index;
        first = false;
      } else if (chunk.index > maxChunkIndex) {
        secondMaxChunkIndex = maxChunkIndex;
        maxChunkIndex = chunk.index;
      } else if (chunk.index > secondMaxChunkIndex) {
        secondMaxChunkIndex = chunk.index;
      }
    }

    // Find the N oldest evictable chunks via partial selection.
    // Fixed-size list, filled with the oldest candidates so far.
    final victims = List<_ChatScrollChunk?>.filled(
      toRemove,
      null,
      growable: false,
    );
    var filled = 0;
    var maxVictimTick = 0; // highest tick among current victims

    // Iterate all chunks to find eviction candidates.
    for (final chunk in chunks.values) {
      // Never evict chunks in the current layout range.
      if (chunk.index >= _layoutMinChunk && chunk.index <= _layoutMaxChunk) {
        continue;
      }

      // Never evict the two newest chunks (most recent messages).
      if (chunk.index == maxChunkIndex || chunk.index == secondMaxChunkIndex) {
        continue;
      }

      // Always fill the victim list until full, then only replace if older than
      // the youngest victim so far. This gives a good approximation of LRU
      // order without needing to sort the entire list on every eviction.
      if (filled < toRemove) {
        // Still filling — take any evictable chunk.
        victims[filled++] = chunk;
        if (chunk.lastAccessTick > maxVictimTick) {
          maxVictimTick = chunk.lastAccessTick;
        }
      } else if (chunk.lastAccessTick < maxVictimTick) {
        // Replace the youngest victim with this older chunk.
        var youngestIdx = 0;
        var youngestTick = victims[0]!.lastAccessTick;
        for (var i = 1; i < toRemove; i++) {
          if (victims[i]!.lastAccessTick > youngestTick) {
            youngestTick = victims[i]!.lastAccessTick;
            youngestIdx = i;
          }
        }
        victims[youngestIdx] = chunk;
        // Recompute maxVictimTick.
        maxVictimTick = victims[0]!.lastAccessTick;
        for (var i = 1; i < toRemove; i++) {
          if (victims[i]!.lastAccessTick > maxVictimTick) {
            maxVictimTick = victims[i]!.lastAccessTick;
          }
        }
      }
    }

    // Evict the selected chunks.
    for (var i = 0; i < filled; i++) {
      final chunk = victims[i]!;
      chunk.disposeRenders();
      chunks.remove(chunk.index);
    }
  }
}
