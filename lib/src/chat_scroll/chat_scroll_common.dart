/// Chat message interface.
abstract interface class IChatMessage {
  /// The unique identifier. Must be stable for the lifetime of the message —
  /// no backend operation (delete, edit, reaction) may change this value.
  ///
  /// Negative IDs are valid; the chunk system uses arithmetic right-shift
  /// and handles them correctly. See `docs/adr/001-message-id-scheme.md`.
  ///
  /// Messages displayed in the chat scroll view should be ordered by `id`
  /// in ascending order.
  abstract final int id;

  /// The sender name of the message.
  abstract final String sender;

  /// The time the message was created.
  abstract final DateTime createdAt;

  /// The time the message was updated.
  abstract final DateTime updatedAt;
}

/// Per-chunk fetch status flags stored as a bitfield (`extension type` over
/// `int`). Allows representing multiple states simultaneously (e.g. dirty +
/// fetching).
///
/// **Footgun**: a raw [int] can be passed where [ChatMessageStatus] is expected
/// with no runtime error. Prefer the named constants below. See ADR 001.
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
