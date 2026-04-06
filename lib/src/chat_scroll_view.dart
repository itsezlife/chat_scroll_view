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
  static int chunkOf(int messageId) =>
      messageId < 0 ? -(-messageId >> kBits) : messageId >> kBits;

  /// Get the first message id for a given chunk index.
  static int firstIdOf(int chunkIndex) =>
      chunkIndex < 0 ? -(-chunkIndex << kBits) : chunkIndex << kBits;

  _ChatScrollChunk({required this.index})
    : messages = List<IChatMessage?>.filled(kSize, null, growable: false),
      renders = List<ChatMessageRender?>.filled(kSize, null, growable: false),
      firstId = firstIdOf(index);

  final int index;
  final int firstId;
  int get lastId => firstId + kSize - 1;

  /// Message data — populated from fetch results.
  final List<IChatMessage?> messages;

  /// Render objects — created lazily by the viewport.
  final List<ChatMessageRender?> renders;

  /// Data status (dirty, fetching, error, valid).
  ChatMessageStatus status = ChatMessageStatus.dirty;

  void markRendersDirty() {
    for (final render in renders) {
      if (render == null) continue;
      render.dirty = true;
      render.picture?.dispose();
      render.picture = null;
    }
  }

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
/// [paint], so work done during layout is reused at paint time.
///
/// Created by the [ChatMessageRenderFactory] passed to [ChatScrollView].
/// The viewport manages [height], [offsetY], [dirty], and [picture] fields.
abstract class ChatMessageRender {
  /// Lay out the message for the given [availableWidth].
  /// Returns the computed height.
  double performLayout(double availableWidth);

  /// Paint the message onto [canvas] within [size].
  ///
  /// Called once after [performLayout]; the result is cached as a
  /// [ui.Picture] by the viewport — subsequent frames use the cached
  /// picture until the entry is marked dirty.
  void paint(Canvas canvas, Size size);

  /// Hit-test at [position] (local to this message's origin).
  ///
  /// Returns `true` if the message handles the hit.
  bool hitTest(Offset position) => false;

  /// Release resources (TextPainters, images, etc.).
  @mustCallSuper
  void dispose() {
    picture?.dispose();
    picture = null;
  }

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

  /// Cached [ui.Picture] produced from [paint].
  @nonVirtual
  ui.Picture? picture;
}

/// Creates a [ChatMessageRender] for the given [message].
typedef ChatMessageRenderFactory =
    ChatMessageRender Function(IChatMessage message);

// --- Controller ---

/// Controller for [ChatScrollView].
///
/// Owns the data (chunks), anchor state, and fetch function.
/// The [RenderChatScrollView] reads data from this controller
/// and listens for changes via [ChangeNotifier].
abstract class ChatScrollController extends ChangeNotifier {
  ChatScrollController();

  /// Fetch messages by ID range or timestamp.
  Future<List<IChatMessage>> fetch({int? from, int? to, DateTime? after});

  // --- Chunk storage ---

  /// Unordered map of message chunks by chunk index.
  final Map<int, _ChatScrollChunk> _chunks = HashMap<int, _ChatScrollChunk>();

  /// Get or create a chunk for the given [chunkIndex].
  _ChatScrollChunk _ensureChunk(int chunkIndex) => _chunks.putIfAbsent(
    chunkIndex,
    () => _ChatScrollChunk(index: chunkIndex),
  );

  /// Get a message by ID from the chunk cache.
  IChatMessage? getMessage(int messageId) {
    final chunkIndex = _ChatScrollChunk.chunkOf(messageId);
    final chunk = _chunks[chunkIndex];
    if (chunk == null) return null;
    return chunk.messages[messageId - chunk.firstId];
  }

  // --- Anchor state ---

  /// The message ID used as layout origin.
  int get anchorMessageId => _anchorMessageId;
  int _anchorMessageId = 0;
  set anchorMessageId(int value) {
    if (_anchorMessageId == value) return;
    _anchorMessageId = value;
    notifyListeners();
  }

  /// Pixel offset of the anchor message's top edge from the viewport top.
  double get anchorPixelOffset => _anchorPixelOffset;
  double _anchorPixelOffset = 0.0;
  set anchorPixelOffset(double value) {
    if (_anchorPixelOffset == value) return;
    _anchorPixelOffset = value;
    notifyListeners();
  }

  /// Jump to a specific message, resetting the anchor.
  void jumpTo(int messageId) {
    _anchorMessageId = messageId;
    _anchorPixelOffset = 0.0;
    notifyListeners();
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
/// Manages layout cache ([MessageEntry]) and [ui.Picture] caching.
/// Paints all visible messages onto a single canvas.
class RenderChatScrollView extends RenderBox {
  RenderChatScrollView({
    required ChatScrollController controller,
    required ChatMessageRenderFactory messageBuilder,
  }) : _controller = controller,
       _messageBuilder = messageBuilder;

  // --- Controller ---

  ChatScrollController get controller => _controller;
  ChatScrollController _controller;
  set controller(ChatScrollController value) {
    if (identical(_controller, value)) return;
    _controller.removeListener(_onControllerChanged);
    _controller = value;
    _controller.addListener(_onControllerChanged);
    markNeedsLayout();
  }

  void _onControllerChanged() {
    markNeedsLayout();
  }

  // --- Configuration ---

  ChatMessageRenderFactory get messageBuilder => _messageBuilder;
  ChatMessageRenderFactory _messageBuilder;
  set messageBuilder(ChatMessageRenderFactory value) {
    if (identical(_messageBuilder, value)) return;
    _messageBuilder = value;
    _markAllRendersDirty();
    markNeedsLayout();
  }

  /// Extra pixels to lay out beyond the visible viewport.
  double get cacheExtent => _cacheExtent;
  double _cacheExtent = 250.0;
  set cacheExtent(double value) {
    if (_cacheExtent == value) return;
    _cacheExtent = value;
    markNeedsLayout();
  }

  /// Range of message IDs currently laid out (inclusive).
  int _layoutMinId = 0;
  int _layoutMaxId = -1; // empty range initially

  // --- RenderBox overrides ---

  @override
  bool get isRepaintBoundary => true;

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

    var newMaxId = anchorId - 1;

    // Layout downward from anchor
    var y = anchorOffset;
    var id = anchorId;
    while (y < lowerBound) {
      final message = _controller.getMessage(id);
      if (message == null) break;

      final entry = _ensureRender(id, message);
      if (entry.dirty) {
        entry.height = entry.performLayout(viewportWidth);
        entry.picture?.dispose();
        entry.picture = null;
        entry.dirty = false;
      }
      entry.offsetY = y;
      y += entry.height;
      newMaxId = id;
      id++;
    }

    // Layout upward from anchor
    y = anchorOffset;
    id = anchorId - 1;
    var newMinId = anchorId;
    while (y > upperBound) {
      final message = _controller.getMessage(id);
      if (message == null) break;

      final entry = _ensureRender(id, message);
      if (entry.dirty) {
        entry.height = entry.performLayout(viewportWidth);
        entry.picture?.dispose();
        entry.picture = null;
        entry.dirty = false;
      }
      y -= entry.height;
      entry.offsetY = y;
      newMinId = id;
      id--;
    }

    _layoutMinId = newMinId;
    _layoutMaxId = newMaxId;

    // Evict entries far outside the laid-out range
    _evictRenderChunks();
  }

  // --- Paint ---

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _paintMessages,
    );
  }

  void _paintMessages(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final viewportWidth = size.width;

    for (var id = _layoutMinId; id <= _layoutMaxId; id++) {
      final render = _getRender(id);
      if (render == null) continue;

      // Skip if entirely outside visible area
      if (render.offsetY + render.height < 0 || render.offsetY > size.height) {
        continue;
      }

      // Build picture if needed
      render.picture ??= _recordPicture(viewportWidth, render.height, render);

      if (render.picture case final picture?) {
        canvas.save();
        canvas.translate(offset.dx, offset.dy + render.offsetY);
        canvas.drawPicture(picture);
        canvas.restore();
      }
    }
  }

  ui.Picture _recordPicture(
    double width,
    double height,
    ChatMessageRender render,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    render.paint(canvas, Size(width, height));
    return recorder.endRecording();
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

  /// Get an existing render for [messageId], or null.
  ChatMessageRender? _getRender(int messageId) {
    final chunkIndex = _ChatScrollChunk.chunkOf(messageId);
    final chunk = _controller._chunks[chunkIndex];
    if (chunk == null) return null;
    return chunk.renders[messageId - chunk.firstId];
  }

  /// Get or create a render for [messageId].
  ChatMessageRender _ensureRender(int messageId, IChatMessage message) {
    final chunk = _controller._ensureChunk(_ChatScrollChunk.chunkOf(messageId));
    final i = messageId - chunk.firstId;
    return chunk.renders[i] ??= _messageBuilder(message);
  }

  void _markAllRendersDirty() {
    for (final chunk in _controller._chunks.values) {
      chunk.markRendersDirty();
    }
  }

  void _evictRenderChunks() {
    final keepMin = _ChatScrollChunk.chunkOf(_layoutMinId) - 1;
    final keepMax = _ChatScrollChunk.chunkOf(_layoutMaxId) + 1;
    _controller._chunks.removeWhere((chunkIndex, chunk) {
      if (chunkIndex < keepMin || chunkIndex > keepMax) {
        chunk.disposeRenders();
        return true;
      }
      return false;
    });
  }
}
