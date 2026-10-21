import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:content_model/content_model.dart'
    show ContentKey, EmojiOnlyItem;
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserChatMessage markdown body', () {
    test('parses markdown once at construction', () {
      final message = UserChatMessage(
        id: 1,
        sender: 'alice',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        content: '**bold** and plain',
      );

      expect(message.content, '**bold** and plain');
      expect(message.body, isA<Markdown>());
      expect(message.body.markdown, '**bold** and plain');
      expect(message.body.blocks, isNotEmpty);
    });

    test('preParsed keeps the supplied Markdown instance', () {
      final parsed = Markdown.fromString('hello **world**');
      final message = UserChatMessage.preParsed(
        id: 2,
        sender: 'bob',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        body: parsed,
      );

      expect(identical(message.body, parsed), isTrue);
      expect(message.content, 'hello **world**');
    });
  });

  group('UserChatMessage emoji-only classification', () {
    UserChatMessage message(String content, {bool hasMedia = false}) =>
        UserChatMessage(
          id: 1,
          sender: 'alice',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          content: content,
          hasMedia: hasMedia,
        );

    test('a body of emoji is classified as the model is made', () {
      final emojiOnly = message('\u{1F44D}\u{1F680} \u{1F525}').emojiOnly;

      expect(emojiOnly?.items.map((item) => item.key), const [
        ContentKey.unicode('\u{1F44D}'),
        ContentKey.unicode('\u{1F680}'),
        ContentKey.unicode('\u{1F525}'),
      ]);
    });

    test('the line breaks between emoji are kept', () {
      final emojiOnly = message('\u{1F44D}\n\n\u{1F44D} ').emojiOnly;

      expect(emojiOnly?.items, const [
        EmojiOnlyItem(ContentKey.unicode('\u{1F44D}')),
        EmojiOnlyItem(ContentKey.unicode('\u{1F44D}'), lineBreaksBefore: 2),
      ]);
    });

    test('a custom emoji is an item of its document', () {
      final emojiOnly = message('![\u{1F680}](document:5368)').emojiOnly;

      expect(emojiOnly?.items.single.key, const ContentKey.document('5368'));
    });

    test('text, a style or a link keeps the markdown body', () {
      for (final body in [
        'hello \u{1F44D}',
        '**\u{1F44D}**',
        '[\u{1F44D}](https://a.b)',
        '',
        'hello',
      ]) {
        expect(message(body).emojiOnly, isNull, reason: body);
      }
    });

    test('a unicode embed from another client is not emoji-only', () {
      expect(message('![\u{1F44D}](unicode:1F44D)').emojiOnly, isNull);
    });

    test('a pre-parsed body is classified too', () {
      final preParsed = UserChatMessage.preParsed(
        id: 2,
        sender: 'bob',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        body: Markdown.fromString('\u{1F44D}'),
      );

      expect(preParsed.emojiOnly?.items, hasLength(1));
    });

    test('a message with media says so', () {
      expect(message('\u{1F44D}').hasMedia, isFalse);
      expect(message('\u{1F44D}', hasMedia: true).hasMedia, isTrue);
    });
  });
}
