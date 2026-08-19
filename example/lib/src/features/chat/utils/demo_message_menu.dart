import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Demo reactions shown above the action list.
const List<String> kDemoMessageMenuReactions = <String>[
  '👍',
  '❤️',
  '🔥',
  '🥰',
  '👏',
  '😁',
  '🤔',
  '🎉',
];

/// Demo action rows (Telegram-like set; handlers may stub).
const List<ChatMessageMenuItem> kDemoMessageMenuItems = <ChatMessageMenuItem>[
  ChatMessageMenuItem(id: 'reply', label: 'Reply', icon: Icons.reply_outlined),
  ChatMessageMenuItem(
    id: 'copy',
    label: 'Copy',
    icon: Icons.content_copy_outlined,
  ),
  ChatMessageMenuItem(id: 'pin', label: 'Pin', icon: Icons.push_pin_outlined),
  ChatMessageMenuItem(
    id: 'forward',
    label: 'Forward',
    icon: Icons.shortcut_outlined,
  ),
  ChatMessageMenuItem(id: 'edit', label: 'Edit', icon: Icons.edit_outlined),
  ChatMessageMenuItem(
    id: 'delete',
    label: 'Delete',
    icon: Icons.delete_outline,
    isDestructive: true,
  ),
];

/// Forwards [ChatDataSource] data notifications as a [Listenable].
final class ChatDataSourceListenable implements Listenable {
  /// Creates a listenable over [dataSource].
  const ChatDataSourceListenable(this.dataSource);

  /// Source whose [ChatDataSource.addDataListener] is forwarded.
  final ChatDataSource dataSource;

  @override
  void addListener(VoidCallback listener) =>
      dataSource.addDataListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      dataSource.removeDataListener(listener);
}

/// Opens the package message menu for [messageId] and applies a demo result.
///
/// Presence watches [dataSource] and dismisses when that id is no longer
/// loaded. Does not enter message selection.
Future<void> presentDemoMessageMenu({
  required BuildContext context,
  required int messageId,
  required Rect messageRect,
  required Offset tapGlobal,
  required ChatDataSource dataSource,
  required ValueChanged<int> onDelete,
  required ValueChanged<int> onEdit,
}) async {
  final result = await showChatMessageMenu(
    context: context,
    messageRect: messageRect,
    tapGlobal: tapGlobal,
    items: kDemoMessageMenuItems,
    reactions: kDemoMessageMenuReactions,
    presence: ChatDataSourceListenable(dataSource),
    isPresent: () => dataSource.getMessage(messageId) != null,
  );
  if (!context.mounted || result == null) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  switch (result) {
    case ChatMessageMenuReactionResult(:final reaction):
      messenger.showSnackBar(
        SnackBar(
          content: Text('Reacted $reaction'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    case ChatMessageMenuItemResult(:final itemId):
      switch (itemId) {
        case 'copy':
          final text = _copyText(dataSource.getMessage(messageId));
          if (text == null || text.isEmpty) return;
          await Clipboard.setData(ClipboardData(text: text));
        case 'delete':
          onDelete(messageId);
        case 'edit':
          onEdit(messageId);
        case 'reply' || 'pin' || 'forward':
          messenger.showSnackBar(
            SnackBar(
              content: Text('$itemId (demo)'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        default:
          return;
      }
  }
}

String? _copyText(IChatMessage? message) => switch (message) {
  UserChatMessage(:final content) => content,
  SystemChatMessage(:final content) => content,
  _ => null,
};
