import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:content_model/content_model.dart' as model;
import 'package:meta/meta.dart';

/// One message of a copy of selected messages: who sent it, when, and the
/// markdown body it carries.
@immutable
final class ChatCopiedMessage {
  /// A message to copy.
  const ChatCopiedMessage({
    required this.sender,
    required this.sentAt,
    required this.markdown,
  });

  /// The messages [ids] name in [dataSource], oldest first; one the source
  /// does not hold, or without a body, is left out.
  static List<ChatCopiedMessage> of(
    Iterable<int> ids,
    ChatDataSource dataSource,
  ) => [
    for (final id in ids.toList()..sort())
      if (dataSource.getMessage(id) case final message?)
        if (message.text case final text?)
          ChatCopiedMessage(
            sender: message.sender,
            sentAt: message.createdAt,
            markdown: text,
          ),
  ];

  /// The sender's display name.
  final String sender;

  /// When the message was sent.
  final DateTime sentAt;

  /// The body, as markdown (`ChatBodyMarkdown`).
  final String markdown;
}

/// How a copy of selected messages reads, per platform family: the header
/// each message gets and what separates the messages. The text of a message
/// is its body, with its entities, in every format.
///
/// Chosen by the selection policy ([ChatMessagesCopyFormat.forPolicy]), the
/// way the message menu's rows are. A single message is its body alone in
/// both formats.
sealed class ChatMessagesCopyFormat {
  /// A format.
  const ChatMessagesCopyFormat();

  /// The format of [policy]: the Android client's under `$Mobile` (the iOS
  /// client has no Copy for several messages), the desktop client's under
  /// `$Desktop`.
  factory ChatMessagesCopyFormat.forPolicy(ChatSelectionPolicy policy) =>
      switch (policy) {
        ChatSelectionPolicy$Mobile() ||
        ChatSelectionPolicy$TextOnly() => const ChatMessagesCopyFormat$Mobile(),
        ChatSelectionPolicy$Desktop() => const ChatMessagesCopyFormat$Desktop(),
      };

  /// What goes between two messages.
  @protected
  String get separator;

  /// What goes before [message]'s body when [several] messages are copied;
  /// [previous] is the message copied before it, if any.
  @protected
  String header(
    ChatCopiedMessage message, {
    required ChatCopiedMessage? previous,
  });

  /// [messages], in the order given, as one rich text. A message with no body
  /// is left out with its header.
  model.RichText compose(List<ChatCopiedMessage> messages) {
    final kept = [
      for (final message in messages)
        if (message.markdown.isNotEmpty) message,
    ];
    var out = model.RichText.empty;
    void append(model.RichText text) {
      if (text.isEmpty) return;
      out = out.insert(out.length, text);
    }

    ChatCopiedMessage? previous;
    for (final message in kept) {
      if (previous != null) append(model.RichText.plain(separator));
      if (kept.length > 1) {
        append(model.RichText.plain(header(message, previous: previous)));
      }
      append(ChatBodyMarkdown.decode(message.markdown));
      previous = message;
    }
    return out;
  }
}

/// The Android client's copy of selected messages (`ChatActivity`, the copy
/// action and `getMessageContent`): messages a blank line apart, and a
/// `Name:` line before the first and wherever the sender changes.
///
/// Not carried over: the client leaves the names out in the user's own saved
/// messages, a chat kind the demo does not have.
final class ChatMessagesCopyFormat$Mobile extends ChatMessagesCopyFormat {
  /// The Android format.
  const ChatMessagesCopyFormat$Mobile();

  @override
  String get separator => '\n\n';

  @override
  String header(
    ChatCopiedMessage message, {
    required ChatCopiedMessage? previous,
  }) => previous?.sender == message.sender ? '' : '${message.sender}:\n';
}

/// The desktop client's copy of selected messages (`HistorySelectedItemsText`
/// in `history_item_text.cpp`, reached from the chat's `getSelectedText`):
/// each message of several as `[time] Name: ` and its body, a newline apart.
///
/// Not carried over: the placeholders of media (`[ Photo ]`), the reply
/// context (`in reply to Name`) and a forum topic's line, none of which the
/// demo's messages have.
final class ChatMessagesCopyFormat$Desktop extends ChatMessagesCopyFormat {
  /// The desktop format, stamping each message with [formatTime].
  ///
  /// The client stamps with the system locale's short date and time
  /// (`QLocale::ShortFormat`), which is the locale's and not one string: a
  /// host with locale data passes its own [formatTime]. The default is the
  /// en-US shape ([shortDateTime]).
  const ChatMessagesCopyFormat$Desktop({
    String Function(DateTime sentAt) formatTime = shortDateTime,
  }) : _formatTime = formatTime;

  final String Function(DateTime sentAt) _formatTime;

  /// [sentAt] in local time as en-US writes a short date and time:
  /// `10/8/26, 3:05 PM`.
  static String shortDateTime(DateTime sentAt) {
    final local = sentAt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    final year = (local.year % 100).toString().padLeft(2, '0');
    return '${local.month}/${local.day}/$year, $hour:$minute $period';
  }

  @override
  String get separator => '\n';

  @override
  String header(
    ChatCopiedMessage message, {
    required ChatCopiedMessage? previous,
  }) => '[${_formatTime(message.sentAt)}] ${message.sender}: ';
}
