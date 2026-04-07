import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Chat message interface.
abstract interface class IChatMessage {
  /// The unique identifier of the message.
  /// This is used to identify the message
  /// and should be unique across all messages.
  /// Messages displayed in the chat scroll view
  /// should be ordered by their `id` in ascending order.
  abstract final int id;

  /// The time the message was created.
  abstract final DateTime createdAt;

  /// The time the message was updated.
  abstract final DateTime updatedAt;
}

/// Chat message status flags.
/// Could be implemented as a bitfield for efficient storage and combination.
/// Allows representing multiple states simultaneously (e.g. dirty + fetching).
extension type const ChatMessageStatus._(int _value) {
  /// The message has been fetched and contains actual content.
  static const ChatMessageStatus valid = ChatMessageStatus._(0);

  /// The message is dirty and needs to be refetched.
  static const ChatMessageStatus dirty = ChatMessageStatus._(1 << 0);

  /// An error occurred while fetching the message.
  static const ChatMessageStatus error = ChatMessageStatus._(1 << 1);

  /// The message is being fetched.
  static const ChatMessageStatus fetching = ChatMessageStatus._(1 << 2);

  // --- Can be expanded up to 1 << 31 --- //

  /// A list of all defined status flags.
  static const List<ChatMessageStatus> values = <ChatMessageStatus>[
    valid,
    dirty,
    error,
    fetching,
  ];

  /// Check if the current status contains a specific flag.
  bool contains(ChatMessageStatus flag) => (_value & flag._value) != 0;

  /// Add a flag to the current status.
  ChatMessageStatus add(ChatMessageStatus flag) =>
      ChatMessageStatus._(_value | flag._value);

  /// Remove a flag from the current status.
  ChatMessageStatus remove(ChatMessageStatus flag) =>
      ChatMessageStatus._(_value & ~flag._value);

  /// Toggle a flag in the current status.
  ChatMessageStatus toggle(ChatMessageStatus flag) =>
      ChatMessageStatus._(_value ^ flag._value);

  /// Toggle a flag in the current status.
  ChatMessageStatus operator ^(ChatMessageStatus other) =>
      ChatMessageStatus._(_value ^ other._value);

  /// Currently has no status flags set, meaning the message is valid.
  bool get isValid => _value == 0;

  /// The message is dirty and needs to be refetched.
  bool get isDirty => contains(ChatMessageStatus.dirty);

  /// An error occurred while fetching the message.
  bool get isError => contains(ChatMessageStatus.error);

  /// The message is being fetched.
  bool get isFetching => contains(ChatMessageStatus.fetching);
}

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
  /// again on the next frame. Does not trigger layout.
  ///
  /// If attached, immediately re-records the [PictureLayer].
  /// If not attached, the picture will be recorded upon [attachLayer].
  void invalidatePaint() {
    if (_attached) {
      rerecordPicture();
    }
  }

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
    rerecordPicture();
    _attached = true;
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
    if (_pictureLayer != null) {
      _pictureLayer!.picture?.dispose();
      _pictureLayer!.remove();
      _pictureLayer = null;
    }
  }

  // --- Layer fields ---

  /// The compositing layer for this message.
  OffsetLayer? _layer;

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

  void _onControllerChanged() {
    if (_controller._scrollOnly) {
      // Scroll-only: just update OffsetLayer offsets, no relayout.
      markNeedsPaint();
    } else {
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
  }

  @override
  void detach() {
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
    for (final chunk in _controller._chunks.values) {
      chunk.disposeRenders();
    }
    super.dispose();
  }

  // --- Layout ---

  @override
  void performLayout() {
    final viewportWidth = size.width;
    final viewportHeight = size.height;
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

  // --- Paint (layer-tree based) ---

  @override
  void paint(PaintingContext context, Offset offset) {
    // Reuse or create the root clip layer.
    final clipLayer =
        (layer as ClipRectLayer?) ??
        ClipRectLayer(clipRect: offset & size, clipBehavior: Clip.hardEdge);
    clipLayer.clipRect = offset & size;
    layer = clipLayer;

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
    if (_controller._scrollOnly) _repositionChunks();

    var hasAnimating = false;

    // Single pass: attach/detach layers, update offsets, re-record animations.
    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _controller._chunks[ci];
      if (chunk == null) continue;

      for (var i = 0; i < _ChatScrollChunk.kSize; i++) {
        final render = chunk.renders[i];
        if (render == null) continue;

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
          // Re-record animated renders.
          if (render.needsRepaint) {
            render.rerecordPicture();
            hasAnimating = true;
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

    // TODO: Sticky overlays (avatars, date separators) — append a
    // PictureLayer last in clipLayer so it draws on top of all messages.

    if (hasAnimating) markNeedsPaint();
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
