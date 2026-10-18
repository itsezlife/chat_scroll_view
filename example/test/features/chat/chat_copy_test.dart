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

    group('a spoiler that holds an emoji', () {
      // A spoiler's entity runs over the emoji it holds, whichever way the
      // emoji is written, and over the selected part only.
      RichText copy(String markdown, int start, int end) => ChatCopy.selection(
        MarkdownSelectedContent(
          documents: [
            document(1, markdown, [(start, end)]),
          ],
        ),
      );

      // The unicode emoji of every shape the picker sends, as plain text.
      const thumb = '\u{1F44D}\u{1F3FD}'; // skin tone
      const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}'; // ZWJ
      const flag = '\u{1F1FA}\u{1F1F8}'; // regional indicators
      for (final (name, emoji) in [
        ('a plain emoji', '\u{1F600}'),
        ('a skin tone emoji', thumb),
        ('a ZWJ sequence', family),
        ('a flag', flag),
      ]) {
        test('keeps $name at the start, the middle and the end', () {
          for (final inside in ['$emoji b c', 'b $emoji c', 'b c $emoji']) {
            final length = inside.length;
            expect(
              copy('a ||$inside|| d', 0, 4 + length),
              RichText('a $inside d', [Entity(2, length, EntityKind.spoiler)]),
              reason: inside,
            );
          }
        });
      }

      test('keeps a custom emoji embed in it, the spoiler over the embed', () {
        // Rendered: "a b 🚀 c d"; the embed is 2 units, 4..6.
        expect(
          copy('a ||b ![\u{1F680}](document:rocket) c|| d', 0, 11),
          RichText('a b \u{1F680} c d', const [
            Entity(2, 6, EntityKind.spoiler),
            Entity(
              4,
              2,
              EntityKind.inlineContent(ContentKey.document('rocket')),
            ),
          ]),
        );
        // At the edges of the spoiler.
        expect(
          copy('||![\u{1F680}](document:rocket) c||', 0, 4),
          RichText('\u{1F680} c', const [
            Entity(0, 4, EntityKind.spoiler),
            Entity(
              0,
              2,
              EntityKind.inlineContent(ContentKey.document('rocket')),
            ),
          ]),
        );
        expect(
          copy('||c ![\u{1F680}](document:rocket)||', 0, 4),
          RichText('c \u{1F680}', const [
            Entity(0, 4, EntityKind.spoiler),
            Entity(
              2,
              2,
              EntityKind.inlineContent(ContentKey.document('rocket')),
            ),
          ]),
        );
      });

      test('keeps a spoiler over an embed that is all of it', () {
        expect(
          copy('||![\u{1F680}](document:rocket)||', 0, 2),
          RichText('\u{1F680}', const [
            Entity(0, 2, EntityKind.spoiler),
            Entity(
              0,
              2,
              EntityKind.inlineContent(ContentKey.document('rocket')),
            ),
          ]),
        );
      });

      test('keeps a spoiler over the text of an embed the selection cuts', () {
        // Rendered "b 🚀 c": the selection stops after the first unit of the
        // embed's two, so only its text is copied, still hidden.
        expect(
          copy('||b ![\u{1F680}](document:rocket) c||', 0, 3),
          RichText('b \u{1F680}'.substring(0, 3), const [
            Entity(0, 3, EntityKind.spoiler),
          ]),
        );
      });

      test('keeps only the selected part of the spoiler', () {
        // Rendered "a b 😀 c d": the selection is "😀 c".
        expect(
          copy('a ||b \u{1F600} c|| d', 4, 8),
          RichText('\u{1F600} c', const [Entity(0, 4, EntityKind.spoiler)]),
        );
      });

      test('keeps each of several spoilers', () {
        // Rendered "||x 😀|| and ||😀 y||".
        expect(
          copy('||x \u{1F600}|| and ||\u{1F600} y||', 0, 16),
          RichText('x \u{1F600} and \u{1F600} y', const [
            Entity(0, 4, EntityKind.spoiler),
            Entity(9, 4, EntityKind.spoiler),
          ]),
        );
      });

      test('keeps bold and the spoiler over an emoji, both kinds', () {
        expect(
          copy('**||b \u{1F600} c||** d', 0, 8),
          RichText('b \u{1F600} c d', const [
            Entity(0, 6, EntityKind.bold),
            Entity(0, 6, EntityKind.spoiler),
          ]),
        );
        expect(
          copy('||**b** ![\u{1F680}](document:rocket) c||', 0, 8),
          RichText('b \u{1F680} c', const [
            Entity(0, 1, EntityKind.bold),
            Entity(0, 6, EntityKind.spoiler),
            Entity(
              2,
              2,
              EntityKind.inlineContent(ContentKey.document('rocket')),
            ),
          ]),
        );
      });
    });

    test('keeps a style over the spaces between its spans', () {
      // `a `, bold `b` and ` c` are three spans of one spoiler; each gives
      // up its edge whitespace if copied as its own entity.
      expect(
        ChatCopy.selection(
          MarkdownSelectedContent(
            documents: [
              document(1, '||a **b** c||', [(0, 5)]),
            ],
          ),
        ),
        RichText('a b c', const [
          Entity(0, 5, EntityKind.spoiler),
          Entity(2, 1, EntityKind.bold),
        ]),
      );
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
