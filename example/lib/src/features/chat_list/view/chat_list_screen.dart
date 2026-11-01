import 'package:chat_scroll_view_example/src/features/chat/view/chat_page_route.dart';
import 'package:chat_scroll_view_example/src/features/chat_list/widgets/chat_list_tile.dart';
import 'package:flutter/material.dart';

/// The page a chat is opened from: a list of chats, each pushing [chat] with
/// a [ChatPageRoute].
///
/// Every row opens the same demo chat; the list exists so that a chat opens
/// the way it does in a product, slid in over a page that keeps painting,
/// with the wallpaper and glass scopes above the navigator.
class ChatListScreen extends StatelessWidget {
  /// Lists [entries]; a tap pushes [chat].
  const ChatListScreen({
    required this.chat,
    this.entries = demoEntries,
    super.key,
  });

  /// Builds the chat a row opens.
  final WidgetBuilder chat;

  /// The rows.
  final List<ChatListEntry> entries;

  /// Key of the row at [index], for a test to tap.
  static ValueKey<String> tileKey(int index) =>
      ValueKey<String>('chat-list-tile-$index');

  /// The rows the demo shows.
  static const List<ChatListEntry> demoEntries = [
    ChatListEntry(
      title: 'Design review',
      preview: 'The wallpaper moves on send now',
      time: '14:02',
      color: Color(0xFF5E9E8A),
    ),
    ChatListEntry(
      title: 'Ada',
      preview: 'Sent a sticker',
      time: '13:47',
      color: Color(0xFF8A6AA6),
    ),
    ChatListEntry(
      title: 'Release train',
      preview: 'Profile build is up on the device',
      time: '12:10',
      color: Color(0xFFA6866A),
    ),
    ChatListEntry(
      title: 'Grace',
      preview: 'See you tomorrow',
      time: 'Yesterday',
      color: Color(0xFF6A8AA6),
    ),
    ChatListEntry(
      title: 'Perf notes',
      preview: 'p99 raster under budget on open',
      time: 'Mon',
      color: Color(0xFF6AA67A),
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chats')),
    body: ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => ChatListTile(
        key: tileKey(index),
        entry: entries[index],
        onTap: () => Navigator.of(
          context,
        ).push<void>(ChatPageRoute<void>(builder: chat)),
      ),
    ),
  );
}
