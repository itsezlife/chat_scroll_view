import 'package:flutter/material.dart';

/// One chat in the chat list: avatar, title, the last message and its time.
class ChatListTile extends StatelessWidget {
  /// A row for [entry] that calls [onTap].
  const ChatListTile({required this.entry, required this.onTap, super.key});

  /// The chat the row stands for.
  final ChatListEntry entry;

  /// Opens the chat.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: entry.color,
        child: Text(
          entry.title.characters.first,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(entry.time, style: theme.textTheme.bodySmall),
    );
  }
}

/// What the chat list shows of one chat.
@immutable
final class ChatListEntry {
  /// A chat titled [title] whose last message is [preview], sent at [time].
  const ChatListEntry({
    required this.title,
    required this.preview,
    required this.time,
    required this.color,
  });

  /// The chat's name.
  final String title;

  /// The last message, one line.
  final String preview;

  /// When the last message was sent, as the list shows it.
  final String time;

  /// The avatar's fill.
  final Color color;
}
