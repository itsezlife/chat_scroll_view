import 'package:chat_scroll_view/chat_scroll_view.dart' show IChatMessage;
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:content_model/content_model.dart' show EmojiOnly;
import 'package:meta/meta.dart';

/// Whether the emoji-only body (`ChatEmojiBody`) is shown for a message, the
/// host's half of the decision. The text's half is `UserChatMessage.emojiOnly`,
/// made when the model was.
///
/// The viewport never decides this: it lays out the body it is given. The host
/// decides, as Telegram Android does (research 05, section 2):
///
/// - the user keeps the large-emoji setting on ([enabled]);
/// - the chat allows stickers ([stickersAllowed]), or the user is an admin of
///   it ([isAdmin]);
/// - the message has no media, a link preview included.
@immutable
final class LargeEmojiPolicy {
  /// A policy for a chat. A chat allows stickers, and its user is no admin,
  /// until said otherwise.
  const LargeEmojiPolicy({
    required this.enabled,
    this.stickersAllowed = true,
    this.isAdmin = false,
  });

  /// The user's large-emoji setting.
  final bool enabled;

  /// Whether the chat lets its members send stickers.
  final bool stickersAllowed;

  /// Whether the user administers the chat, which overrides a chat that does
  /// not allow stickers.
  final bool isAdmin;

  /// The emoji of [message] to show as the emoji-only body, or null for the
  /// markdown body.
  EmojiOnly? emojiOnlyOf(IChatMessage message) =>
      enabled && (stickersAllowed || isAdmin) && !message.hasMedia
      ? message.emojiOnly
      : null;

  @override
  bool operator ==(Object other) =>
      other is LargeEmojiPolicy &&
      other.enabled == enabled &&
      other.stickersAllowed == stickersAllowed &&
      other.isAdmin == isAdmin;

  @override
  int get hashCode => Object.hash(enabled, stickersAllowed, isAdmin);
}
