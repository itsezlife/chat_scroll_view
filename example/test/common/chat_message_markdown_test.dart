import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
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
}
