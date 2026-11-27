import 'package:chat_scroll_view_example/src/common/models/chat_kind.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/demo_chat_rights.dart';
import 'package:chat_scroll_view_example/src/features/chat/view/chat_page_route.dart';
import 'package:chat_scroll_view_example/src/features/chat_list/widgets/chat_list_tile.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chat_scroll_view_example/src/features/logs/view/journal_page.dart';
import 'package:flutter/material.dart';

/// The page a chat is opened from: a list of chats, each pushing [chat] with
/// a [ChatPageRoute].
///
/// Every row opens the same demo chat as its entry's [ChatListEntry.kind]
/// (private, group, channel), which weighs what its media download by
/// themselves, and with its entry's [ChatListEntry.rights] (a channel is
/// read only; one group bans some sends, another is in slow mode); the list
/// exists so that a chat opens
/// the way it does in a product, slid in over a page that keeps painting,
/// with the wallpaper and glass scopes above the navigator.
class ChatListScreen extends StatelessWidget {
  /// Lists [entries]; a tap pushes [chat].
  const ChatListScreen({
    required this.chat,
    this.entries = demoEntries,
    this.journal,
    super.key,
  });

  /// The diagnostics journal the Logs action opens; no action when null.
  final DiagnosticsJournal? journal;

  /// Builds the chat a row opens, for the row's entry.
  final Widget Function(BuildContext context, ChatListEntry entry) chat;

  /// The rows.
  final List<ChatListEntry> entries;

  /// Key of the row at [index], for a test to tap.
  static ValueKey<String> tileKey(int index) =>
      ValueKey<String>('chat-list-tile-$index');

  /// The rows the demo shows.
  static const List<ChatListEntry> demoEntries = [
    ChatListEntry(
      id: 'design-review',
      title: 'Design review',
      preview: 'The wallpaper moves on send now',
      time: '14:02',
      color: Color(0xFF5E9E8A),
    ),
    ChatListEntry(
      id: 'ada',
      title: 'Ada',
      preview: 'Sent a sticker',
      time: '13:47',
      color: Color(0xFF8A6AA6),
      kind: ChatKind.privateChat,
    ),
    ChatListEntry(
      id: 'moderated',
      title: 'Moderated group',
      preview: 'Photos and stickers are off for you',
      time: '13:20',
      color: Color(0xFFA66A6A),
      rights: DemoChatRights.banned,
    ),
    ChatListEntry(
      id: 'slow-lane',
      title: 'Slow lane',
      preview: 'One message every 30 seconds',
      time: '12:41',
      color: Color(0xFF6A9EA6),
      rights: DemoChatRights.slowMode,
    ),
    ChatListEntry(
      id: 'release-train',
      title: 'Release train',
      preview: 'Profile build is up on the device',
      time: '12:10',
      color: Color(0xFFA6866A),
      kind: ChatKind.channel,
    ),
    ChatListEntry(
      id: 'grace',
      title: 'Grace',
      preview: 'See you tomorrow',
      time: 'Yesterday',
      color: Color(0xFF6A8AA6),
      kind: ChatKind.privateChat,
    ),
    ChatListEntry(
      id: 'perf-notes',
      title: 'Perf notes',
      preview: 'p99 raster under budget on open',
      time: 'Mon',
      color: Color(0xFF6AA67A),
      kind: ChatKind.channel,
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Chats'),
      actions: [
        if (journal case final journal?)
          IconButton(
            tooltip: 'Logs',
            onPressed: () =>
                Navigator.of(context).push(JournalPage.route(journal: journal)),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
      ],
    ),
    body: ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => ChatListTile(
        key: tileKey(index),
        entry: entries[index],
        onTap: () => Navigator.of(context).push<void>(
          ChatPageRoute<void>(
            builder: (context) => chat(context, entries[index]),
          ),
        ),
      ),
    ),
  );
}
