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

  /// The message ID is permanently absent — the server confirmed it does not
  /// exist within the conversation's bounds (e.g. deleted in a batch). Unlike
  /// `null` slots in a dirty or fetching chunk, an absent slot will never
  /// return data. The viewport skips absent IDs during fan-out and they
  /// contribute zero height, keeping the scrollbar accurate.
  ///
  /// Absent slots are set by the `_executeFetch` success pass and cleared by
  /// `invalidate()` so a re-fetch always starts with a clean slate.
  ///
  /// | Bit | Name     | Value | Meaning                              |
  /// |-----|----------|-------|--------------------------------------|
  /// |  0  | dirty    |     1 | Stale — needs a re-fetch             |
  /// |  1  | error    |     2 | Last fetch failed                    |
  /// |  2  | fetching |     4 | Fetch in flight                      |
  /// |  3  | absent   |     8 | ID confirmed non-existent by server  |
  ///
  /// Bits `1 << 4` through `1 << 31` are reserved for future use.
  static const ChatMessageStatus absent = ChatMessageStatus._(1 << 3);

  // --- Can be expanded up to 1 << 31 --- //

  /// A list of all defined status flags.
  static const List<ChatMessageStatus> values = <ChatMessageStatus>[
    valid,
    dirty,
    error,
    fetching,
    absent,
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

  /// The message ID is confirmed absent — permanently non-existent within the
  /// conversation's bounds. Fan-out skips absent IDs; they render at zero
  /// height to keep scrollbar math correct.
  bool get isAbsent => contains(ChatMessageStatus.absent);
}
