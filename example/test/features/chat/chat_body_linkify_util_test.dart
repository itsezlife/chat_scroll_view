import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_linkify_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatBodyLinkifyUtil.materialize', () {
    test('rewrites bare https and leaves @username plain', () {
      // Host policy is ChatLinkifyPolicy.webUrls (mentions not auto-rewritten).
      expect(
        ChatBodyLinkifyUtil.materialize('ping @alice at https://example.com'),
        'ping @alice at [https://example.com](https://example.com)',
      );
    });

    test('is idempotent', () {
      const input = 'hi @bob see https://example.com';
      final once = ChatBodyLinkifyUtil.materialize(input);
      expect(ChatBodyLinkifyUtil.materialize(once), once);
    });
  });

  group('LinkActivation.fromUrl', () {
    test('classifies http and https as web', () {
      expect(
        LinkActivation.fromUrl('https://example.com'),
        isA<WebLinkActivation>().having((a) => a.uri.scheme, 'scheme', 'https'),
      );
      expect(
        LinkActivation.fromUrl('http://example.com'),
        isA<WebLinkActivation>(),
      );
    });

    test('classifies mention scheme with username', () {
      expect(
        LinkActivation.fromUrl('mention:alice'),
        isA<MentionLinkActivation>().having(
          (a) => a.username,
          'username',
          'alice',
        ),
      );
      expect(
        ChatBodyLinkifyUtil.activation('mention:alice'),
        isA<MentionLinkActivation>(),
      );
    });

    test('classifies other schemes as other', () {
      expect(
        LinkActivation.fromUrl('mailto:a@b.c'),
        isA<OtherLinkActivation>().having((a) => a.url, 'url', 'mailto:a@b.c'),
      );
    });
  });

  group('GeneratedChatDataSource host linkify', () {
    test('sendMessage stores a linkified body', () {
      final ds = GeneratedChatDataSource(messageCount: 0);
      final message = ds.sendMessage(
        sender: 'Hixie',
        content: 'see https://example.com and @alice',
      );
      expect(
        message.content,
        'see [https://example.com](https://example.com) and @alice',
      );
      ds.dispose();
    });

    test('editMessage stores a linkified body', () {
      final ds = GeneratedChatDataSource(messageCount: 0);
      final sent = ds.sendMessage(sender: 'Hixie', content: 'plain');
      ds.editMessage(sent, 'hi @carol https://flutter.dev');
      expect(
        ds.getMessage(sent.id)?.text,
        'hi @carol [https://flutter.dev](https://flutter.dev)',
      );
      ds.dispose();
    });
  });
}
