import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatEmojiPolicy, ChatEmojiPolicy$Desktop, IChatMessage;
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:content_model/content_model.dart' show EmojiOnly;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:meta/meta.dart';

/// Whether the emoji-only body (`ChatEmojiBody`) is shown for a message, the
/// host's half of the decision. The text's half is `UserChatMessage.emojiOnly`,
/// made when the model was.
///
/// The viewport never decides this: it lays out the body it is given. The host
/// decides, as the reference client does:
///
/// - the user keeps the large-emoji setting on ([enabled]);
/// - on a platform that gates on it (Android), the chat allows stickers
///   ([stickersAllowed]), or the user is an admin of it ([isAdmin]);
/// - the message has no media, a link preview included;
/// - the platform admits the emoji (`ChatEmojiPolicy.admits`: desktop shows at
///   most [desktopRegularLimit] regular emoji large, 3 by default).
@immutable
final class LargeEmojiPolicy {
  /// A policy for a chat. A chat allows stickers, and its user is no admin,
  /// until said otherwise.
  const LargeEmojiPolicy({
    required this.enabled,
    this.stickersAllowed = true,
    this.isAdmin = false,
    this.desktopRegularLimit = ChatEmojiPolicy$Desktop.defaultRegularLimit,
  });

  /// The user's large-emoji setting.
  final bool enabled;

  /// Whether the chat lets its members send stickers.
  final bool stickersAllowed;

  /// Whether the user administers the chat, which overrides a chat that does
  /// not allow stickers.
  final bool isAdmin;

  /// How many regular emoji a message may hold and still be enlarged on
  /// desktop (and the web): the reference client's 3 until the user moves
  /// it. The other families have no cap and ignore it.
  final int desktopRegularLimit;

  /// The emoji-only policy of the platform the app runs on, carrying the cap
  /// the user chose: what [emojiOnlyOf] and the body's chrome are given.
  ChatEmojiPolicy family({TargetPlatform? platform, bool? isWeb}) =>
      ChatEmojiPolicy.forPlatform(
        platform: platform,
        isWeb: isWeb,
        desktopRegularLimit: desktopRegularLimit,
      );

  /// The emoji of [message] to show as the emoji-only body under [platform]
  /// (the Android family's when null), or null for the markdown body.
  EmojiOnly? emojiOnlyOf(IChatMessage message, {ChatEmojiPolicy? platform}) {
    final family = platform ?? const ChatEmojiPolicy.android();
    final allowed =
        !family.gatesOnStickerPermission || stickersAllowed || isAdmin;
    if (!enabled || !allowed || message.hasMedia) return null;
    final emoji = message.emojiOnly;
    return emoji != null && family.admits(emoji) ? emoji : null;
  }

  @override
  bool operator ==(Object other) =>
      other is LargeEmojiPolicy &&
      other.enabled == enabled &&
      other.stickersAllowed == stickersAllowed &&
      other.isAdmin == isAdmin &&
      other.desktopRegularLimit == desktopRegularLimit;

  @override
  int get hashCode =>
      Object.hash(enabled, stickersAllowed, isAdmin, desktopRegularLimit);
}
