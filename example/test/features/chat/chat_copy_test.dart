import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatCopyOrigin, ChatTextCopy;
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart' show TextRange;
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('a snippet is code; a block of code, with its language, is a code '
      'block', () {
    expect(
      ChatCopy.code('a()'),
      RichText('a()', const [Entity(0, 3, EntityKind.code)]),
    );
    expect(
      ChatCopy.code('a()', language: 'dart'),
      RichText('a()', const [
        Entity(0, 3, EntityKind.codeBlock(language: 'dart')),
      ]),
    );
    expect(
      ChatCopy.code('a()\nb()'),
      RichText('a()\nb()', const [Entity(0, 7, EntityKind.codeBlock())]),
    );
    expect(ChatCopy.code(''), RichText.empty);
  });

  group('a selection', () {
    MarkdownSelectedDocument document(
      Object id,
      String markdown,
      List<(int, int)> ranges,
    ) {
      // The blocks with text: a spacer stands between paragraphs.
      final blocks = [
        for (final block in Markdown.fromString(markdown).blocks)
          if (block is! MD$Spacer) block,
      ];
      return MarkdownSelectedDocument(
        documentId: id,
        blocks: [
          for (final (index, (start, end)) in ranges.indexed)
            MarkdownSelectedBlock(
              blockIndex: index,
              type: blocks[index].type,
              text: '',
              renderedRange: TextRange(start: start, end: end),
              block: blocks[index],
            ),
        ],
      );
    }

    test('keeps the styles, links and whole custom emoji of what is '
        'selected', () {
      // Rendered: "Hello bold and link 🚀 tail"; the selection starts inside
      // "Hello" and stops after the emoji.
      final content = MarkdownSelectedContent(
        documents: [
          document(
            1,
            'Hello **bold** and [link](https://e.com) '
            '![\u{1F680}](document:rocket) tail',
            [(2, 22)],
          ),
        ],
      );

      expect(
        ChatCopy.selection(content),
        RichText('llo bold and link \u{1F680}', const [
          Entity(4, 4, EntityKind.bold),
          Entity(13, 4, EntityKind.link('https://e.com')),
          Entity(
            18,
            2,
            EntityKind.inlineContent(ContentKey.document('rocket')),
          ),
        ]),
      );
    });

    test('reads the mention bit, not the link, for mentions and hashtags, and '
        'keeps embeds and spoilers', () {
      // Rendered: "hi @Ann @bob #tag 🚀 secret".
      final content = MarkdownSelectedContent(
        documents: [
          document(
            1,
            'hi [@Ann](mention:42) [@bob](username:bob) [#tag](hashtag:tag) '
            '![\u{1F680}](document:rocket) ||secret||',
            [(0, 27)],
          ),
        ],
      );

      expect(
        ChatCopy.selection(content),
        RichText('hi @Ann @bob #tag \u{1F680} secret', const [
          Entity(3, 4, EntityKind.mention('42')),
          Entity(8, 4, EntityKind.username('bob')),
          Entity(13, 4, EntityKind.hashtag('tag')),
          Entity(
            18,
            2,
            EntityKind.inlineContent(ContentKey.document('rocket')),
          ),
          Entity(21, 6, EntityKind.spoiler),
        ]),
      );
    });

    test('keeps the styles of a mention, a spoiler\'s included', () {
      final content = MarkdownSelectedContent(
        documents: [
          document(1, '||[@Ann](mention:42)||', [(0, 4)]),
        ],
      );

      expect(
        ChatCopy.selection(content),
        RichText('@Ann', const [
          Entity(0, 4, EntityKind.mention('42')),
          Entity(0, 4, EntityKind.spoiler),
        ]),
      );
    });

    test('keeps a mention only whole: a cut one is its text', () {
      final content = MarkdownSelectedContent(
        documents: [
          document(1, '[@Ann](mention:42) [#tag](hashtag:tag)', [(1, 6)]),
        ],
      );

      expect(ChatCopy.selection(content), const RichText.plain('Ann #'));
    });

    test('is plain text where it cuts through a custom emoji\'s text', () {
      final content = MarkdownSelectedContent(
        documents: [
          document(1, '![ab](document:x)', [(0, 1)]),
        ],
      );

      expect(ChatCopy.selection(content), const RichText.plain('a'));
    });

    test('quotes a quote and codes a code block, a line apart', () {
      final content = MarkdownSelectedContent(
        documents: [
          document(1, '> quoted\n\n```dart\ncode()\n```', [(0, 6), (0, 6)]),
        ],
      );

      expect(
        ChatCopy.selection(content),
        RichText('quoted\ncode()', const [
          Entity(0, 6, EntityKind.quote),
          Entity(7, 6, EntityKind.codeBlock(language: 'dart')),
        ]),
      );
    });

    test('puts a blank line between messages', () {
      final content = MarkdownSelectedContent(
        documents: [
          document(1, 'one', [(0, 3)]),
          document(2, '*two*', [(0, 3)]),
        ],
      );

      expect(
        ChatCopy.selection(content),
        RichText('one\n\ntwo', const [Entity(5, 3, EntityKind.italic)]),
      );
    });
  });

  test('what the viewport copies: a selection by its spans, a code tap as '
      'code, anything else as text', () {
    final content = MarkdownSelectedContent(
      documents: [
        MarkdownSelectedDocument(
          documentId: 1,
          blocks: [
            MarkdownSelectedBlock(
              blockIndex: 0,
              type: 'paragraph',
              text: 'bold',
              renderedRange: const TextRange(start: 0, end: 4),
              block: Markdown.fromString('**bold**').blocks.first,
            ),
          ],
        ),
      ],
    );

    expect(
      ChatCopy.of(
        ChatTextCopy(
          plainText: 'bold',
          origin: ChatCopyOrigin.textSelection,
          content: content,
        ),
      ),
      RichText('bold', const [Entity(0, 4, EntityKind.bold)]),
    );
    expect(
      ChatCopy.of(
        const ChatTextCopy(plainText: 'a()', origin: ChatCopyOrigin.codeTap),
      ),
      RichText('a()', const [Entity(0, 3, EntityKind.code)]),
    );
    expect(
      ChatCopy.of(
        const ChatTextCopy(
          plainText: 'x',
          origin: ChatCopyOrigin.textSelection,
        ),
      ),
      const RichText.plain('x'),
    );
  });
}
