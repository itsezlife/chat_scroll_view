import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
import 'package:flutter/material.dart';

/// Snapshot used to present a message menu session.
@immutable
final class ChatMessageMenuPresentConfig {
  /// Creates a present config.
  const ChatMessageMenuPresentConfig({
    required this.messageRect,
    required this.items,
    required this.reactions,
    required this.keyboardHeight,
    required this.screenSize,
    this.tapGlobal,
    this.safePadding = EdgeInsets.zero,
    this.presence,
    this.isPresent,
  });

  /// Captured slot rect in overlay coordinates.
  final Rect messageRect;

  /// Action rows.
  final List<ChatMessageMenuItem> items;

  /// Reaction emojis. Empty omits the strip.
  final List<String> reactions;

  /// IME height ([MediaQuery.viewInsets.bottom]) at session start.
  final double keyboardHeight;

  /// Logical screen size at session start.
  final Size screenSize;

  /// Optional tap anchor.
  final Offset? tapGlobal;

  /// System safe insets (status / nav). Do not include the IME.
  final EdgeInsets safePadding;

  /// Optional presence listenable. No signal = no watch.
  final Listenable? presence;

  /// Returns whether the captured message is still present.
  final bool Function()? isPresent;
}
