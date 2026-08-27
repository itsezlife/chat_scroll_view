import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:message_media/message_media.dart';
import 'package:meta/meta.dart';

/// Base type for messages rendered in a [ChatScrollView].
///
/// Sealed so callers can pattern-match on [UserChatMessage] vs
/// [SystemChatMessage] without a catch-all. Implements [IChatMessage] for the
/// scroll engine's id / timestamp contract.
@immutable
sealed class ChatMessage implements IChatMessage {
  /// Shared fields for every message leaf — [id], [sender], and timestamps.
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.updatedAt,
    required this.createdAt,
  });

  @override
  final int id;

  @override
  final String sender;

  @override
  final DateTime createdAt;

  @override
  final DateTime updatedAt;
}

/// A system-authored message — service notifications, join/leave notices,
/// channel events. `sealed`-pattern leaf of [ChatMessage].
class SystemChatMessage extends ChatMessage {
  /// Creates a system-authored row (join notices, channel events, …).
  const SystemChatMessage({
    required super.id,
    required super.sender,
    required super.createdAt,
    required super.updatedAt,
    required this.content,
  });

  /// The content of the system message.
  final String content;
}

/// A user-authored message. `sealed`-pattern leaf of [ChatMessage].
///
/// Optional media fields drive photo/video placeholder rows: [aspectRatio]
/// non-null marks a media row; [groupId] non-null places that id in a per-chat
/// grouped-messages album (N distinct Message IDs). Text-only rows leave media
/// fields null.
class UserChatMessage extends ChatMessage {
  /// Creates a user-authored row with [content] body text.
  ///
  /// When [aspectRatio] is set, hosts may paint a media placeholder (single or
  /// group row). [groupId] is the album key shared by N members; omit it for a
  /// standalone single. [caption] is plain caption text (entities out of
  /// scope); [invertMedia] forces caption-above.
  const UserChatMessage({
    required super.id,
    required super.sender,
    required super.createdAt,
    required super.updatedAt,
    required this.content,
    this.groupId,
    this.aspectRatio,
    this.mediaKind,
    this.caption,
    this.invertMedia = false,
  });

  /// The content of the user message (body text; may be empty for media-only).
  final String content;

  /// Shared album key when this Message ID is a group-row member; `null` for
  /// singles and text-only rows.
  final int? groupId;

  /// Width / height of the media thumb. Non-null ⇒ media row; `null` ⇒ text.
  final double? aspectRatio;

  /// Photo vs video; ignored for geometry. Defaults to photo when media.
  final MediaKind? mediaKind;

  /// Plain caption for this member (group caption owner or single caption).
  final String? caption;

  /// When true, group caption is placed above the mosaic (`invert_media`).
  final bool invertMedia;

  /// Whether [aspectRatio] is set (media layout inputs present).
  bool get hasMedia => aspectRatio != null;
}

/// Extension methods for [IChatMessage].
extension ChatMessageExtension on IChatMessage {
  /// The content of the message.
  String? get text => switch (this) {
    UserChatMessage(:final content) => content,
    SystemChatMessage(:final content) => content,
    _ => null,
  };
}
