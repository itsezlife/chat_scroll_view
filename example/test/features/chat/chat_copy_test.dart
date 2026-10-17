import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('several messages are one text, a blank line apart, with their '
      'entities', () {
    expect(
      ChatCopy.messages([
        '**bold** first',
        '',
        'second ![\u{1F680}](document:rocket)',
      ]),
      RichText('bold first\n\nsecond \u{1F680}', const [
        Entity(0, 4, EntityKind.bold),
        Entity(19, 2, EntityKind.inlineContent(ContentKey.document('rocket'))),
      ]),
    );
  });

  test('a custom emoji is itself over its text; a unicode emoji is text', () {
    expect(
      ChatCopy.content(const ContentKey.document('rocket'), '\u{1F680}'),
      RichText('\u{1F680}', const [
        Entity(0, 2, EntityKind.inlineContent(ContentKey.document('rocket'))),
      ]),
    );
    expect(
      ChatCopy.content(const ContentKey.unicode('\u{1F44D}'), '\u{1F44D}'),
      const RichText.plain('\u{1F44D}'),
    );
  });

  test('code is code', () {
    expect(
      ChatCopy.code('a()'),
      RichText('a()', const [Entity(0, 3, EntityKind.code)]),
    );
    expect(ChatCopy.code(''), RichText.empty);
  });
}
