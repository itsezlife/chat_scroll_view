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

/// {@template chat_scroll_view}
/// ChatScrollView widget.
/// {@endtemplate}
class ChatScrollView extends RenderObjectWidget {
  /// {@macro chat_scroll_view}
  const ChatScrollView({
    required this.fetch,
    required this.builder,
    super.key, // ignore: unused_element_parameter
  });

  /// The function to fetch messages.
  final Future<List<IChatMessage>> Function({
    int? from,
    int? to,
    DateTime? after,
  })
  fetch;

  /// The function to build a message widget.
  final Widget Function(IChatMessage message) builder;

  @override
  RenderObjectElement createElement() =>
      ChatScrollViewElement<IChatMessage>(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      ChatScrollViewRenderObject();
}

class ChatScrollViewElement<Msg> extends RenderObjectElement {
  ChatScrollViewElement(super.widget);

  @override
  void insertRenderObjectChild(
    covariant RenderObject child,
    covariant Object? slot,
  ) {
    // TODO: implement insertRenderObjectChild
  }

  @override
  void moveRenderObjectChild(
    covariant RenderObject child,
    covariant Object? oldSlot,
    covariant Object? newSlot,
  ) {
    // TODO: implement moveRenderObjectChild
  }

  @override
  void removeRenderObjectChild(
    covariant RenderObject child,
    covariant Object? slot,
  ) {
    // TODO: implement removeRenderObjectChild
  }
}

class ChatScrollViewRenderObject extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, Object>,
        RenderBoxContainerDefaultsMixin<RenderBox, Object> {
  ChatScrollViewRenderObject();

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;
}
