import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_reactions.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_slots.dart';
import 'package:flutter/widgets.dart';

/// Default floating column: optional reaction strip above the action card.
class ChatMessageMenuColumn extends StatelessWidget {
  /// Creates the default chrome column.
  const ChatMessageMenuColumn({required this.slots, super.key});

  /// Default pieces and the data they were built from.
  final ChatMessageMenuSlots slots;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (slots.reactions.isNotEmpty) ...<Widget>[
        Align(alignment: Alignment.centerRight, child: slots.reactionStrip),
        const SizedBox(height: kChatMessageMenuReactionsGap),
      ],
      Padding(
        padding: const EdgeInsets.only(
          left: kChatMessageMenuReactionsStartOverhang,
          right: kChatMessageMenuReactionsEndOverhang,
        ),
        child: slots.actionList,
      ),
    ],
  );
}
