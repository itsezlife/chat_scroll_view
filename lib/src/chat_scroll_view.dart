import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

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

/// Chunk of chat messages used for pagination.
/// The chunk index is calculated by shifting
/// the message id to the right by [ChatScrollChunk.kChunkBits].
class ChatScrollChunk {
  /// The number of bits to shift to get the chunk index.
  static const int kChunkBits = 6;

  /// The max number of items in a chunk.
  static const int kChunkSize = 64;

  /// Get the chunk index for a given message id.
  static int getChunkIndex(int messageId) =>
      messageId < 0 ? -(-messageId >> kChunkBits) : messageId >> kChunkBits;

  /// Get the first message id for a given chunk index.
  static int getChunkFirstId(int chunkIndex) =>
      chunkIndex < 0 ? -(-chunkIndex << kChunkBits) : chunkIndex << kChunkBits;

  ChatScrollChunk({required this.index})
    : items = List<IChatMessage?>.filled(kChunkSize, null, growable: false),
      firstId = getChunkFirstId(index),
      lastId = getChunkFirstId(index) + kChunkSize - 1,
      _status = ChatMessageStatus.dirty;

  /// The index of the chunk.
  /// Could be negative for messages with negative ids.
  final int index;

  /// The id of the first message in the chunk.
  final int firstId;

  /// The id of the last message in the chunk.
  final int lastId;

  /// The items in the chunk.
  /// The list is fixed length and filled with nulls initially.
  /// When a message is loaded, it is placed in the list at the index
  /// corresponding to its id relative to the chunk's first id.
  final List<IChatMessage?> items;

  /// Get the status of the chunk and its messages.
  ChatMessageStatus get status => _status;
  ChatMessageStatus _status; // ignore: prefer_final_fields
}

/// Cached layout and picture for a single message.
class MessageEntry {
  MessageEntry({required this.messageId});

  final int messageId;

  /// The computed height of this message.
  double height = 0.0;

  /// The Y offset within the viewport (set during layout).
  double offsetY = 0.0;

  /// Whether this entry needs to be re-laid out and re-painted.
  bool dirty = true;

  /// Cached picture for this message, produced by [ui.PictureRecorder].
  ui.Picture? picture;

  void dispose() {
    picture?.dispose();
    picture = null;
  }
}

/// Callback to paint a single message onto a canvas.
///
/// The canvas is sized to [size] (full viewport width x message height).
/// The painter should draw the message content within these bounds.
typedef MessagePainter =
    void Function(Canvas canvas, Size size, IChatMessage message);

/// Callback to compute the height of a message given the available width.
typedef MessageLayouter =
    double Function(double availableWidth, IChatMessage message);

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

  final Map<int, ChatScrollChunk> _chunks = <int, ChatScrollChunk>{};

  /// Get a message by ID from the chunk cache.
  IChatMessage? getMessage(int messageId) {
    final chunkIndex = ChatScrollChunk.getChunkIndex(messageId);
    final chunk = _chunks[chunkIndex];
    if (chunk == null) return null;
    final indexInChunk = messageId - chunk.firstId;
    assert(
      indexInChunk >= 0 && indexInChunk < ChatScrollChunk.kChunkSize,
      'Message ID $messageId is out of bounds for chunk index $chunkIndex',
    );
    return chunk.items[indexInChunk];
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
    required this.painter,
    required this.layouter,
    super.key, // ignore: unused_element_parameter
  });

  /// The controller that owns message data and anchor state.
  final ChatScrollController controller;

  /// Paints a single message onto the provided canvas.
  final MessagePainter painter;

  /// Computes the height of a message given the available width.
  final MessageLayouter layouter;

  @override
  RenderChatScrollView createRenderObject(BuildContext context) =>
      RenderChatScrollView(
        controller: controller,
        painter: painter,
        layouter: layouter,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatScrollView renderObject,
  ) {
    renderObject
      ..controller = controller
      ..painter = painter
      ..layouter = layouter;
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
    required MessagePainter painter,
    required MessageLayouter layouter,
  }) : _controller = controller,
       _painter = painter,
       _layouter = layouter;

  // --- Controller ---

  ChatScrollController get controller => _controller;
  ChatScrollController _controller;
  set controller(ChatScrollController value) {
    if (_controller == value) return;
    _controller.removeListener(_onControllerChanged);
    _controller = value;
    _controller.addListener(_onControllerChanged);
    markNeedsLayout();
  }

  void _onControllerChanged() {
    markNeedsLayout();
  }

  // --- Configuration ---

  MessagePainter get painter => _painter;
  MessagePainter _painter;
  set painter(MessagePainter value) {
    if (_painter == value) return;
    _painter = value;
    _markAllEntriesDirty();
    markNeedsPaint();
  }

  MessageLayouter get layouter => _layouter;
  MessageLayouter _layouter;
  set layouter(MessageLayouter value) {
    if (_layouter == value) return;
    _layouter = value;
    _markAllEntriesDirty();
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

  // --- Layout cache ---

  /// Layout cache: messageId → MessageEntry.
  final Map<int, MessageEntry> _entries = {};

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
    _markAllEntriesDirty();
    markNeedsLayout();
  }

  @override
  void dispose() {
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
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

      final entry = _ensureEntry(id);
      if (entry.dirty) {
        entry.height = _layouter(viewportWidth, message);
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

      final entry = _ensureEntry(id);
      if (entry.dirty) {
        entry.height = _layouter(viewportWidth, message);
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
    _evictEntries();
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
      final entry = _entries[id];
      if (entry == null) continue;

      // Skip if entirely outside visible area
      if (entry.offsetY + entry.height < 0 || entry.offsetY > size.height) {
        continue;
      }

      // Build picture if needed
      if (entry.picture == null) {
        final message = _controller.getMessage(id);
        if (message != null) {
          entry.picture = _recordPicture(viewportWidth, entry.height, message);
        }
      }

      if (entry.picture != null) {
        canvas.save();
        canvas.translate(offset.dx, offset.dy + entry.offsetY);
        canvas.drawPicture(entry.picture!);
        canvas.restore();
      }
    }
  }

  ui.Picture _recordPicture(double width, double height, IChatMessage message) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    _painter(canvas, Size(width, height), message);
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

  // --- Entry management ---

  MessageEntry _ensureEntry(int messageId) {
    return _entries.putIfAbsent(
      messageId,
      () => MessageEntry(messageId: messageId),
    );
  }

  void _markAllEntriesDirty() {
    for (final entry in _entries.values) {
      entry.dirty = true;
      entry.picture?.dispose();
      entry.picture = null;
    }
  }

  void _evictEntries() {
    final keepMin = _layoutMinId - ChatScrollChunk.kChunkSize;
    final keepMax = _layoutMaxId + ChatScrollChunk.kChunkSize;
    _entries.removeWhere((id, entry) {
      if (id < keepMin || id > keepMax) {
        entry.dispose();
        return true;
      }
      return false;
    });
  }
}
