import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
import 'package:flutter/widgets.dart';

/// Builds one action row. [onSelect] is null when the item is disabled.
///
/// Dividers and custom rows are not passed here.
typedef ChatMessageMenuItemBuilder =
    Widget Function(
      BuildContext context,
      ChatMessageMenuAction item,
      VoidCallback? onSelect,
    );

/// Builds one reaction slot.
typedef ChatMessageMenuReactionBuilder =
    Widget Function(
      BuildContext context,
      String reaction,
      VoidCallback onSelect,
    );

/// Builds the floating chrome (reactions + actions).
///
/// Scrim, placement, enter/leave, back, and presence stay package-owned.
/// Reuse [ChatMessageMenuSlots.reactionStrip] and
/// [ChatMessageMenuSlots.actionList] to keep the defaults.
typedef ChatMessageMenuBuilder =
    Widget Function(BuildContext context, ChatMessageMenuSlots slots);

/// Default chrome pieces and the data they were built from.
@immutable
final class ChatMessageMenuSlots {
  /// Creates a slot bundle.
  const ChatMessageMenuSlots({
    required this.items,
    required this.reactions,
    required this.onSelectItem,
    required this.onSelectReaction,
    required this.actionList,
    required this.reactionStrip,
  });

  /// Host action rows for this session.
  final List<ChatMessageMenuItem> items;

  /// Host reaction emojis. Empty omits the default strip.
  final List<String> reactions;

  /// Completes the session with [ChatMessageMenuResult.item].
  final ValueChanged<String> onSelectItem;

  /// Completes the session with [ChatMessageMenuResult.reaction].
  final ValueChanged<String> onSelectReaction;

  /// Default action card (already using [ChatMessageMenuItemBuilder] if set).
  final Widget actionList;

  /// Default reaction pill, or [SizedBox.shrink] when [reactions] is empty.
  final Widget reactionStrip;
}
