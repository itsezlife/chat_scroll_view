/// What the example's local sources do with a message body: detect once as a
/// message is materialised, and store a sent or edited body as the composer
/// made it.
library;

import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/showcase_bodies.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_markdown.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeneratedChatDataSource bodies', () {
    test('sendMessage stores the body it was given', () {
      final ds = GeneratedChatDataSource(messageCount: 0);
      addTearDown(ds.dispose);
      const sent = 'see [https://example.com](https://example.com) and @alice';

      final message = ds.sendMessage(sender: 'Hixie', content: sent);

      expect(message.content, sent);
    });

    test('editMessage stores the body it was given', () {
      final ds = GeneratedChatDataSource(messageCount: 0);
      addTearDown(ds.dispose);
      final sent = ds.sendMessage(sender: 'Hixie', content: 'plain');
      const edited = 'hi [@carol](username:carol)';

      ds.editMessage(sent, edited);

      expect(ds.getMessage(sent.id)?.text, edited);
    });
  });

  group('GeneratedChatDataSource showcase', () {
    late GeneratedChatDataSource ds;
    late List<UserChatMessage> messages;

    setUp(() async {
      final count = ShowcaseBodies.all.length;
      ds = GeneratedChatDataSource(
        messageCount: count,
        style: GeneratedMessageStyle.showcase,
      );
      messages = [
        for (final message in await ds.fetchRange(fromId: 0, toId: count - 1))
          message as UserChatMessage,
      ];
    });
    tearDown(() => ds.dispose());

    Iterable<EntityKind> kinds(UserChatMessage message) =>
        ChatBodyMarkdown.decode(message.content).entities.map((e) => e.kind);

    test('serves each body in turn', () {
      expect(messages.map((message) => message.content), [
        for (final body in ShowcaseBodies.all) ChatBodyMarkdown.received(body),
      ]);
    });

    test('has custom emoji in the text, several to a line', () {
      final inline = kinds(messages[0]).whereType<EntityKind$InlineContent>();

      expect(inline, hasLength(3));
      expect(inline.every((kind) => kind.key is ContentKey$Document), isTrue);
      expect(messages[0].emojiOnly, isNull);
    });

    test('has a spoiler with an embed inside', () {
      final text = ChatBodyMarkdown.decode(messages[7].content);
      final spoiler = text.entities.singleWhere(
        (e) => e.kind == EntityKind.spoiler,
      );
      final embed = text.entities.singleWhere(
        (e) => e.kind is EntityKind$InlineContent,
      );

      expect(embed.offset, greaterThanOrEqualTo(spoiler.offset));
      expect(embed.end, lessThanOrEqualTo(spoiler.end));
    });

    test('has a mention, a username and a hashtag', () {
      expect(kinds(messages[8]), [
        const EntityKind.mention('42'),
        const EntityKind.username('bob'),
        const EntityKind.hashtag('release'),
      ]);
    });

    test('has emoji-only messages for each layout', () {
      expect(
        [
          for (final message in messages.skip(10))
            message.emojiOnly?.items.length,
        ],
        [1, 1, 3, 5, 12, 3],
      );
      expect(
        messages.last.emojiOnly!.items.map((item) => item.lineBreaksBefore),
        [0, 2, 0],
      );
    });

    test('has no emoji-only message among the text ones', () {
      expect(
        messages.take(10).map((message) => message.emojiOnly),
        everyElement(isNull),
      );
    });
  });
}
