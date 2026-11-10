import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_item.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_presentation.dart';
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

/// Draws the surface of the action card around [rows]: its fill, corners and
/// shadow, in place of the package card's (a host's glass, say).
///
/// The builder clips [rows] to its shape; their press feedback stays inside
/// it. The card's width rules (`ChatMessageMenuCard`) still apply around the
/// surface.
typedef ChatMessageMenuSurfaceBuilder =
    Widget Function(BuildContext context, Widget rows);

/// Plays the menu's enter and leave on [menu].
///
/// The builder shows [menu] when [ChatMessageMenuTransition.visible] is true,
/// and when it turns false plays the leave and then calls
/// [ChatMessageMenuTransition.onHidden], once; the session removes the menu
/// from there. Scrim, placement, back and presence stay package-owned.
typedef ChatMessageMenuTransitionBuilder =
    Widget Function(
      BuildContext context,
      ChatMessageMenuTransition transition,
      Widget menu,
    );

/// What a [ChatMessageMenuTransitionBuilder] plays.
@immutable
final class ChatMessageMenuTransition {
  /// A transition.
  const ChatMessageMenuTransition({
    required this.visible,
    required this.onHidden,
    required this.presentation,
    required this.origin,
    required this.rows,
    this.hasReactions = false,
  });

  /// Whether the menu is up; false once the session is closing.
  final bool visible;

  /// Called by the builder once the leave is over.
  final VoidCallback onHidden;

  /// How the menu is presented.
  final ChatMessageMenuPresentation presentation;

  /// Where the menu is anchored: the corner at the pointer for a popup; for a
  /// sheet, which hangs to the left of the press, its right corner on the side
  /// facing the message (the bottom when the menu sits above the message).
  final Alignment origin;

  /// How many action rows the menu has.
  final int rows;

  /// Whether the menu shows a reaction strip above its actions.
  final bool hasReactions;
}

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
