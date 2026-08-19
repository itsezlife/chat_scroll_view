import 'package:flutter/widgets.dart';

/// One host-defined row in a message menu.
@immutable
sealed class ChatMessageMenuItem {
  /// An action row. Same unnamed constructor as before.
  const factory ChatMessageMenuItem({
    required String id,
    required String label,
    required IconData icon,
    bool enabled,
    bool isDestructive,
  }) = ChatMessageMenuAction;

  const ChatMessageMenuItem._();

  /// A 1px separator. Insert explicitly — not implied by [isDestructive].
  const factory ChatMessageMenuItem.divider() = ChatMessageMenuDivider;

  /// An arbitrary row. Use for chrome the package does not model.
  const factory ChatMessageMenuItem.custom({required WidgetBuilder builder}) =
      ChatMessageMenuCustom;
}

/// Tappable action row.
@immutable
final class ChatMessageMenuAction extends ChatMessageMenuItem {
  /// Creates an action row.
  const ChatMessageMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.isDestructive = false,
  }) : super._();

  /// Stable id returned on [ChatMessageMenuResult.item].
  final String id;

  /// Visible row label.
  final String label;

  /// Leading icon.
  final IconData icon;

  /// Whether the row accepts taps.
  final bool enabled;

  /// Uses error coloring (for example Delete).
  final bool isDestructive;
}

/// Horizontal rule between rows.
@immutable
final class ChatMessageMenuDivider extends ChatMessageMenuItem {
  /// Creates a divider row.
  const ChatMessageMenuDivider() : super._();
}

/// Host-built row.
@immutable
final class ChatMessageMenuCustom extends ChatMessageMenuItem {
  /// Creates a custom row.
  const ChatMessageMenuCustom({required this.builder}) : super._();

  /// Builds the row in the action card.
  final WidgetBuilder builder;
}

/// Outcome of [showChatMessageMenu].
///
/// Dismiss and presence abort complete with `null` instead of a result.
@immutable
sealed class ChatMessageMenuResult {
  const ChatMessageMenuResult();

  /// An action row was chosen.
  const factory ChatMessageMenuResult.item(String itemId) =
      ChatMessageMenuItemResult;

  /// A reaction emoji was chosen.
  const factory ChatMessageMenuResult.reaction(String reaction) =
      ChatMessageMenuReactionResult;
}

/// An action row was chosen.
@immutable
final class ChatMessageMenuItemResult extends ChatMessageMenuResult {
  /// Creates an item result.
  const ChatMessageMenuItemResult(this.itemId);

  /// Selected action id.
  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is ChatMessageMenuItemResult && other.itemId == itemId;

  @override
  int get hashCode => itemId.hashCode;
}

/// A reaction emoji was chosen.
@immutable
final class ChatMessageMenuReactionResult extends ChatMessageMenuResult {
  /// Creates a reaction result.
  const ChatMessageMenuReactionResult(this.reaction);

  /// Selected reaction emoji.
  final String reaction;

  @override
  bool operator ==(Object other) =>
      other is ChatMessageMenuReactionResult && other.reaction == reaction;

  @override
  int get hashCode => reaction.hashCode;
}
