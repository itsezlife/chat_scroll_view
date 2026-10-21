/// What a copy of selected messages puts on the clipboard, per platform
/// family, after the reference clients:
///
/// * `$Desktop`: Telegram Desktop, `HistoryInner::getSelectedText` ->
///   `HistorySelectedItemsText` (`history_item_text.cpp`): one message is its
///   text alone; several are `[time] Name: text` lines, a newline apart.
/// * `$Mobile`: Telegram Android, `ChatActivity` copy action and
///   `getMessageContent`: messages a blank line apart, a `Name:` line before
///   the first and wherever the sender changes, none for a single message.
///   (Telegram iOS has no Copy on a selection of several messages.)
///
/// **Seam:** `ChatMessagesCopyFormat.compose` (rich text out), plus the
/// policy that picks the format. The date and time of the desktop header are
/// the reference's `QLocale::ShortFormat`, a locale's own; the tests pin the
/// format that is injected and the default's en-US shape.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatSelectionPolicy;
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_messages_copy_format.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

ChatCopiedMessage _message(
  String sender,
  String markdown, {
  DateTime? sentAt,
}) => ChatCopiedMessage(
  sender: sender,
  sentAt: sentAt ?? DateTime(2026, 10, 18, 15, 5),
  markdown: markdown,
);

String _stamp(DateTime at) =>
    '${at.hour}:${at.minute.toString().padLeft(2, '0')}';

void main() {
  group('the format follows the selection policy', () {
    test('mobile policy: Android format, desktop policy: Desktop format', () {
      expect(
        ChatMessagesCopyFormat.forPolicy(const ChatSelectionPolicy.mobile()),
        isA<ChatMessagesCopyFormat$Mobile>(),
      );
      expect(
        ChatMessagesCopyFormat.forPolicy(const ChatSelectionPolicy.desktop()),
        isA<ChatMessagesCopyFormat$Desktop>(),
      );
    });
  });

  group(r'$Desktop', () {
    const format = ChatMessagesCopyFormat$Desktop(formatTime: _stamp);

    test('one message is its text alone, entities kept', () {
      expect(
        format.compose([_message('Ann', '**bold** first')]),
        RichText('bold first', const [Entity(0, 4, EntityKind.bold)]),
      );
    });

    test('several are [time] Name: text lines, a newline apart', () {
      expect(
        format.compose([
          _message('Ann', 'one', sentAt: DateTime(2026, 10, 18, 9, 5)),
          _message('Bob', 'two', sentAt: DateTime(2026, 10, 18, 15, 30)),
        ]),
        const RichText.plain('[9:05] Ann: one\n[15:30] Bob: two'),
      );
    });

    test('the header repeats for each message, also of one sender', () {
      expect(
        format.compose([_message('Ann', 'one'), _message('Ann', 'two')]).plain,
        '[15:05] Ann: one\n[15:05] Ann: two',
      );
    });

    test('entities move behind the headers of the messages before them', () {
      // "[15:05] Ann: " is 13 characters, so "bold" is at 13; "\n" and
      // the second 13-character header follow it.
      expect(
        format.compose([
          _message('Ann', '**bold**'),
          _message('Bob', 'see ||it|| [@Cy](mention:7)'),
        ]),
        RichText('[15:05] Ann: bold\n[15:05] Bob: see it @Cy', const [
          Entity(13, 4, EntityKind.bold),
          Entity(35, 2, EntityKind.spoiler),
          Entity(38, 3, EntityKind.mention('7')),
        ]),
      );
    });

    test('a body of several lines stays whole after its header', () {
      expect(
        format.compose([_message('Ann', 'a\nb'), _message('Bob', 'c')]).plain,
        '[15:05] Ann: a\nb\n[15:05] Bob: c',
      );
    });

    test('an emoji-only message is its emoji', () {
      expect(
        format.compose([
          _message('Ann', '\u{1F44D}'),
          _message('Bob', 'ok'),
        ]).plain,
        '[15:05] Ann: \u{1F44D}\n[15:05] Bob: ok',
      );
    });

    test('a custom emoji keeps its entity behind the header', () {
      expect(
        format.compose([
          _message('Ann', 'x'),
          _message('Bob', '![\u{1F680}](document:rocket)'),
        ]),
        RichText('[15:05] Ann: x\n[15:05] Bob: \u{1F680}', const [
          Entity(
            28,
            2,
            EntityKind.inlineContent(ContentKey.document('rocket')),
          ),
        ]),
      );
    });

    test('a message with no text is left out, and so is its header', () {
      expect(
        format.compose([
          _message('Ann', 'one'),
          _message('Bob', ''),
          _message('Cy', 'three'),
        ]).plain,
        '[15:05] Ann: one\n[15:05] Cy: three',
      );
    });

    test('a single message left among empty ones is its text alone', () {
      expect(
        format.compose([_message('Ann', ''), _message('Bob', 'two')]).plain,
        'two',
      );
    });

    test('nothing selected copies nothing', () {
      expect(format.compose(const []), RichText.empty);
    });
  });

  group(r'$Desktop time', () {
    test('the default is the en-US short date and time of the local clock', () {
      String at(int h, int m) => ChatMessagesCopyFormat$Desktop.shortDateTime(
        DateTime(2026, 10, 8, h, m),
      );
      expect(at(15, 5), '10/8/26, 3:05 PM');
      expect(at(0, 0), '10/8/26, 12:00 AM');
      expect(at(12, 30), '10/8/26, 12:30 PM');
      expect(at(9, 59), '10/8/26, 9:59 AM');
    });

    test('a message sent in UTC is stamped in local time', () {
      final utc = DateTime.utc(2026, 10, 8, 15, 5);
      expect(
        ChatMessagesCopyFormat$Desktop.shortDateTime(utc),
        ChatMessagesCopyFormat$Desktop.shortDateTime(utc.toLocal()),
      );
    });
  });

  group(r'$Mobile', () {
    const format = ChatMessagesCopyFormat$Mobile();

    test('one message is its text alone, entities kept', () {
      expect(
        format.compose([_message('Ann', '**bold** first')]),
        RichText('bold first', const [Entity(0, 4, EntityKind.bold)]),
      );
    });

    test('several of one sender: a Name: line once, a blank line apart', () {
      expect(
        format.compose([_message('Ann', 'one'), _message('Ann', 'two')]).plain,
        'Ann:\none\n\ntwo',
      );
    });

    test('a Name: line wherever the sender changes', () {
      expect(
        format.compose([
          _message('Ann', 'one'),
          _message('Bob', 'two'),
          _message('Bob', 'three'),
          _message('Ann', 'four'),
        ]).plain,
        'Ann:\none\n\nBob:\ntwo\n\nthree\n\nAnn:\nfour',
      );
    });

    test('entities move behind the headers and the separators', () {
      expect(
        format.compose([
          _message('Ann', '**bold**'),
          _message('Bob', 'a ||b||'),
        ]),
        RichText('Ann:\nbold\n\nBob:\na b', const [
          Entity(5, 4, EntityKind.bold),
          Entity(18, 1, EntityKind.spoiler),
        ]),
      );
    });

    test('a message with no text is left out, and so is its Name: line', () {
      expect(
        format.compose([
          _message('Ann', 'one'),
          _message('Bob', ''),
          _message('Ann', 'three'),
        ]).plain,
        'Ann:\none\n\nthree',
      );
    });

    test('nothing selected copies nothing', () {
      expect(format.compose(const []), RichText.empty);
    });
  });
}
