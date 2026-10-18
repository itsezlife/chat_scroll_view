import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/simulated_input.dart';

const _mention = EntityKind.mention('42');

void main() {
  late ComposerTextController controller;

  setUp(() => controller = ComposerTextController());
  tearDown(() => controller.dispose());

  /// Puts [text] in the controller with [from]..[to] selected (a caret when
  /// [to] is omitted).
  void load(RichText text, int from, [int? to]) => controller.restore(
    text,
    selection: TextSelection(baseOffset: from, extentOffset: to ?? from),
  );

  group('toggleStyle', () {
    for (final style in [
      EntityStyle.bold,
      EntityStyle.italic,
      EntityStyle.underline,
      EntityStyle.strike,
      EntityStyle.spoiler,
      EntityStyle.code,
    ]) {
      test('${style.name} turns on over the selection', () {
        load(const RichText.plain('hello world'), 0, 5);

        controller.toggleStyle(style);

        expect(
          controller.richText,
          RichText('hello world', [Entity(0, 5, EntityKind.style(style))]),
        );
      });

      test('${style.name} turns off over a selection it covers', () {
        load(
          RichText('hello world', [Entity(0, 5, EntityKind.style(style))]),
          0,
          5,
        );

        controller.toggleStyle(style);

        expect(controller.richText, const RichText.plain('hello world'));
      });
    }

    test('turning off inside a run splits it', () {
      load(RichText('abcdefgh', const [Entity(0, 8, EntityKind.bold)]), 2, 5);

      controller.toggleStyle(EntityStyle.bold);

      expect(
        controller.richText,
        RichText('abcdefgh', const [
          Entity(0, 2, EntityKind.bold),
          Entity(5, 3, EntityKind.bold),
        ]),
      );
    });

    test('a selection half inside a run makes the whole selection bold', () {
      load(RichText('abcdefgh', const [Entity(0, 4, EntityKind.bold)]), 2, 6);

      controller.toggleStyle(EntityStyle.bold);

      expect(
        controller.richText,
        RichText('abcdefgh', const [Entity(0, 6, EntityKind.bold)]),
      );
    });

    test('over a line break styles each line', () {
      load(const RichText.plain('ab\ncd'), 0, 5);

      controller.toggleStyle(EntityStyle.italic);

      expect(
        controller.richText,
        RichText('ab\ncd', const [
          Entity(0, 2, EntityKind.italic),
          Entity(3, 2, EntityKind.italic),
        ]),
      );
    });

    test('turns off over a run that spans lines', () {
      load(
        RichText('ab\ncd', const [
          Entity(0, 2, EntityKind.italic),
          Entity(3, 2, EntityKind.italic),
        ]),
        0,
        5,
      );

      controller.toggleStyle(EntityStyle.italic);

      expect(controller.richText, const RichText.plain('ab\ncd'));
    });

    test('leaves the whitespace at the edges of the selection plain', () {
      load(const RichText.plain(' hi '), 0, 4);

      controller.toggleStyle(EntityStyle.bold);

      expect(
        controller.richText,
        RichText(' hi ', const [Entity(1, 2, EntityKind.bold)]),
      );
    });

    test('keeps the selection and the text', () {
      load(const RichText.plain('hello world'), 6, 11);

      controller.toggleStyle(EntityStyle.bold);

      expect(controller.text, 'hello world');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 6, extentOffset: 11),
      );
    });

    test('tells its listeners, though the value is equal', () {
      load(const RichText.plain('hello'), 0, 5);
      var notified = 0;
      controller.addListener(() => notified++);

      controller.toggleStyle(EntityStyle.bold);

      expect(notified, 1);
    });

    test('code over bold text removes the bold inside the selection', () {
      load(RichText('abcdefgh', const [Entity(0, 8, EntityKind.bold)]), 2, 5);

      controller.toggleStyle(EntityStyle.code);

      expect(
        controller.richText,
        RichText('abcdefgh', const [
          Entity(2, 3, EntityKind.code),
          Entity(0, 2, EntityKind.bold),
          Entity(5, 3, EntityKind.bold),
        ]),
      );
    });

    test('code over a link cuts the link around it', () {
      load(
        RichText('abcdefgh', const [Entity(0, 8, EntityKind.link('u'))]),
        2,
        5,
      );

      controller.toggleStyle(EntityStyle.code);

      expect(
        controller.richText,
        RichText('abcdefgh', const [
          Entity(0, 2, EntityKind.link('u')),
          Entity(2, 3, EntityKind.code),
          Entity(5, 3, EntityKind.link('u')),
        ]),
      );
    });

    test('bold over a selection inside code is refused', () {
      load(RichText('code', const [Entity(0, 4, EntityKind.code)]), 1, 3);

      expect(controller.canApply(EntityKind.bold), isFalse);
      controller.toggleStyle(EntityStyle.bold);

      expect(
        controller.richText,
        RichText('code', const [Entity(0, 4, EntityKind.code)]),
      );
    });

    test('bold over a selection that cuts into code is refused', () {
      load(RichText('a code b', const [Entity(2, 4, EntityKind.code)]), 0, 4);

      expect(controller.canApply(EntityKind.bold), isFalse);
    });

    test('bold over a selection that holds all of a code run is fine', () {
      load(RichText('a code b', const [Entity(2, 4, EntityKind.code)]), 0, 8);

      expect(controller.canApply(EntityKind.bold), isTrue);
      controller.toggleStyle(EntityStyle.bold);

      expect(
        controller.richText,
        RichText('a code b', const [
          Entity(0, 8, EntityKind.bold),
          Entity(2, 4, EntityKind.code),
        ]),
      );
    });

    test('code over a mention is refused, the mention stays whole', () {
      load(RichText('hi @al', const [Entity(3, 3, _mention)]), 0, 5);

      expect(controller.canApply(EntityKind.code), isFalse);
      controller.toggleStyle(EntityStyle.code);

      expect(
        controller.richText,
        RichText('hi @al', const [Entity(3, 3, _mention)]),
      );
    });

    test('a selection ending inside a mention styles the whole mention', () {
      load(RichText('hi @al', const [Entity(3, 3, _mention)]), 0, 5);

      controller.toggleStyle(EntityStyle.bold);

      expect(
        controller.richText,
        RichText('hi @al', const [
          Entity(0, 6, EntityKind.bold),
          Entity(3, 3, _mention),
        ]),
      );
    });

    test('over only whitespace does nothing', () {
      load(const RichText.plain('a  b'), 1, 3);

      expect(controller.canApply(EntityKind.bold), isFalse);
      controller.toggleStyle(EntityStyle.bold);

      expect(controller.richText, const RichText.plain('a  b'));
    });
  });

  group('with a collapsed caret', () {
    setUp(() => load(const RichText.plain('hello world'), 3));

    for (final style in [
      EntityStyle.bold,
      EntityStyle.italic,
      EntityStyle.underline,
      EntityStyle.strike,
      EntityStyle.spoiler,
      EntityStyle.code,
    ]) {
      test('${style.name} does nothing and cannot apply', () {
        expect(controller.canApply(EntityKind.style(style)), isFalse);

        controller.toggleStyle(style);

        expect(controller.richText, const RichText.plain('hello world'));
      });
    }

    test('a typed character after toggleStyle(bold) is not bold', () {
      controller.toggleStyle(EntityStyle.bold);

      controller.type('x');

      expect(controller.text, 'helxlo world');
      expect(controller.richText.entities, isEmpty);
    });
  });

  group('toggleStyle(quote)', () {
    const lines = 'one\ntwo\nthree';

    test('a selection inside one line widens to the line', () {
      load(const RichText.plain(lines), 5, 6);

      controller.toggleStyle(EntityStyle.quote);

      expect(
        controller.richText,
        RichText(lines, const [Entity(4, 3, EntityKind.quote)]),
      );
    });

    test('a selection over several lines widens to all of them', () {
      load(const RichText.plain(lines), 1, 9);

      controller.toggleStyle(EntityStyle.quote);

      expect(
        controller.richText,
        RichText(lines, const [Entity(0, 13, EntityKind.quote)]),
      );
    });

    test('a selection that ends after a line break leaves the next line', () {
      load(const RichText.plain(lines), 0, 4);

      controller.toggleStyle(EntityStyle.quote);

      expect(
        controller.richText,
        RichText(lines, const [Entity(0, 3, EntityKind.quote)]),
      );
    });

    test('a caret quotes its line', () {
      load(const RichText.plain(lines), 9);

      expect(controller.canApply(EntityKind.quote), isTrue);
      controller.toggleStyle(EntityStyle.quote);

      expect(
        controller.richText,
        RichText(lines, const [Entity(8, 5, EntityKind.quote)]),
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 9));
    });

    test('turns off for the lines the selection touches only', () {
      load(RichText(lines, const [Entity(0, 13, EntityKind.quote)]), 5);

      controller.toggleStyle(EntityStyle.quote);

      expect(
        controller.richText,
        RichText(lines, const [
          Entity(0, 3, EntityKind.quote),
          Entity(8, 5, EntityKind.quote),
        ]),
      );
    });

    test('turns off from the first and the last line of a quote', () {
      load(RichText(lines, const [Entity(0, 13, EntityKind.quote)]), 1);
      controller.toggleStyle(EntityStyle.quote);
      expect(
        controller.richText,
        RichText(lines, const [Entity(4, 9, EntityKind.quote)]),
      );

      load(RichText(lines, const [Entity(0, 13, EntityKind.quote)]), 10);
      controller.toggleStyle(EntityStyle.quote);
      expect(
        controller.richText,
        RichText(lines, const [Entity(0, 7, EntityKind.quote)]),
      );
    });

    test('on an empty line does nothing', () {
      load(const RichText.plain('a\n\nb'), 2);

      expect(controller.canApply(EntityKind.quote), isFalse);
      controller.toggleStyle(EntityStyle.quote);

      expect(controller.richText, const RichText.plain('a\n\nb'));
    });

    test('is refused over a code block', () {
      final text = RichText(lines, const [
        Entity(0, 3, EntityKind.codeBlock()),
      ]);
      load(text, 1);

      expect(controller.canApply(EntityKind.quote), isFalse);
      controller.toggleStyle(EntityStyle.quote);

      expect(controller.richText, text);
    });

    test('is refused over a list item rather than dropping the item', () {
      final text = RichText(lines, const [
        Entity(0, 3, EntityKind.list(listKind: EntityListKind.bullet)),
      ]);
      load(text, 1);

      expect(controller.canApply(EntityKind.quote), isFalse);
      controller.toggleStyle(EntityStyle.quote);

      expect(controller.richText, text);
    });
  });

  group('toggleCodeBlock', () {
    const lines = 'one\ntwo\nthree';

    test('a selection inside a line makes the line a block', () {
      load(const RichText.plain(lines), 1, 2);

      controller.toggleCodeBlock();

      expect(
        controller.richText,
        RichText(lines, const [Entity(0, 3, EntityKind.codeBlock())]),
      );
    });

    test('a selection over lines makes all of them one block', () {
      load(const RichText.plain(lines), 5, 10);

      controller.toggleCodeBlock();

      expect(
        controller.richText,
        RichText(lines, const [Entity(4, 9, EntityKind.codeBlock())]),
      );
    });

    test('carries the language', () {
      load(const RichText.plain(lines), 1);

      controller.toggleCodeBlock(language: 'dart');

      expect(
        controller.richText,
        RichText(lines, const [
          Entity(0, 3, EntityKind.codeBlock(language: 'dart')),
        ]),
      );
    });

    test('refuses a language a fence could not carry', () {
      load(const RichText.plain(lines), 1);

      expect(
        controller.canApply(const EntityKind.codeBlock(language: 'not valid')),
        isFalse,
      );
      controller.toggleCodeBlock(language: 'not valid');

      expect(controller.richText, const RichText.plain(lines));
    });

    test('turns off over a block, whatever its language', () {
      load(
        RichText(lines, const [
          Entity(0, 3, EntityKind.codeBlock(language: 'dart')),
        ]),
        1,
      );

      controller.toggleCodeBlock();

      expect(controller.richText, const RichText.plain(lines));
    });

    test('turns off over a block of the same language', () {
      load(
        RichText(lines, const [
          Entity(0, 3, EntityKind.codeBlock(language: 'dart')),
        ]),
        1,
      );

      controller.toggleCodeBlock(language: 'dart');

      expect(controller.richText, const RichText.plain(lines));
    });

    test('another language changes the language', () {
      load(
        RichText(lines, const [
          Entity(0, 3, EntityKind.codeBlock(language: 'dart')),
        ]),
        1,
      );

      controller.toggleCodeBlock(language: 'c++');

      expect(
        controller.richText,
        RichText(lines, const [
          Entity(0, 3, EntityKind.codeBlock(language: 'c++')),
        ]),
      );
    });

    test('takes the styles and links off its lines', () {
      load(
        RichText(lines, const [
          Entity(0, 3, EntityKind.bold),
          Entity(4, 3, EntityKind.link('u')),
          Entity(8, 5, EntityKind.italic),
        ]),
        1,
        6,
      );

      controller.toggleCodeBlock();

      expect(
        controller.richText,
        RichText(lines, const [
          Entity(0, 7, EntityKind.codeBlock()),
          Entity(8, 5, EntityKind.italic),
        ]),
      );
    });

    test('takes its lines out of a quote', () {
      const text = 'a\nb\nc';
      load(RichText(text, const [Entity(0, 5, EntityKind.quote)]), 2);

      controller.toggleCodeBlock();

      expect(
        controller.richText,
        RichText(text, const [
          Entity(0, 1, EntityKind.quote),
          Entity(2, 1, EntityKind.codeBlock()),
          Entity(4, 1, EntityKind.quote),
        ]),
      );
    });

    test('is refused over an atom', () {
      final text = RichText('hi @al', const [Entity(3, 3, _mention)]);
      load(text, 0, 4);

      expect(controller.canApply(const EntityKind.codeBlock()), isFalse);
      controller.toggleCodeBlock();

      expect(controller.richText, text);
    });

    test('a caret on an empty line does nothing', () {
      load(const RichText.plain('a\n\nb'), 2);

      controller.toggleCodeBlock();

      expect(controller.richText, const RichText.plain('a\n\nb'));
    });
  });

  group('applyLink', () {
    const text = 'hello world';

    test('links the selection', () {
      load(const RichText.plain(text), 0, 5);

      controller.applyLink('https://a.example');

      expect(
        controller.richText,
        RichText(text, const [
          Entity(0, 5, EntityKind.link('https://a.example')),
        ]),
      );
    });

    test('replaces the link it overlaps', () {
      load(RichText(text, const [Entity(0, 11, EntityKind.link('old'))]), 0, 5);

      controller.applyLink('new');

      expect(
        controller.richText,
        RichText(text, const [
          Entity(0, 5, EntityKind.link('new')),
          Entity(5, 6, EntityKind.link('old')),
        ]),
      );
    });

    test('extends over the whole selection when it half overlaps a link', () {
      load(RichText(text, const [Entity(0, 5, EntityKind.link('old'))]), 3, 8);

      controller.applyLink('new');

      expect(
        controller.richText,
        RichText(text, const [
          Entity(0, 3, EntityKind.link('old')),
          Entity(3, 5, EntityKind.link('new')),
        ]),
      );
    });

    test('at a caret inserts the URL as linked text', () {
      load(const RichText.plain(text), 5);
      expect(controller.canApply(const EntityKind.link('u')), isTrue);

      controller.applyLink('https://a.example');

      expect(controller.text, 'hellohttps://a.example world');
      expect(
        controller.richText,
        RichText('hellohttps://a.example world', const [
          Entity(5, 17, EntityKind.link('https://a.example')),
        ]),
      );
      expect(controller.selection, const TextSelection.collapsed(offset: 22));
    });

    test('is refused over code', () {
      final code = RichText(text, const [Entity(0, 5, EntityKind.code)]);
      load(code, 0, 5);

      expect(controller.canApply(const EntityKind.link('u')), isFalse);
      controller.applyLink('u');

      expect(controller.richText, code);
    });

    test('is refused over a mention', () {
      final mention = RichText('hi @al', const [Entity(3, 3, _mention)]);
      load(mention, 0, 6);

      expect(controller.canApply(const EntityKind.link('u')), isFalse);
      controller.applyLink('u');

      expect(controller.richText, mention);
    });

    test('is refused at a caret inside code', () {
      final code = RichText(text, const [Entity(0, 11, EntityKind.code)]);
      load(code, 5);

      expect(controller.canApply(const EntityKind.link('u')), isFalse);
      controller.applyLink('u');

      expect(controller.richText, code);
    });

    test('is refused for a URL a link cannot have', () {
      load(const RichText.plain(text), 0, 5);

      for (final url in ['', 'a\nb', 'mention:42', 'hashtag:x']) {
        controller.applyLink(url);
        expect(controller.canApply(EntityKind.link(url)), isFalse);
      }

      expect(controller.richText, const RichText.plain(text));
    });

    test('a link over a detected username replaces it', () {
      load(
        RichText('hi @al', const [Entity(3, 3, EntityKind.username('al'))]),
        0,
        6,
      );

      controller.applyLink('u');

      expect(
        controller.richText,
        RichText('hi @al', const [Entity(0, 6, EntityKind.link('u'))]),
      );
    });
  });

  group('removeLink', () {
    const text = 'hello world';

    test('takes the link off the selection and keeps the text', () {
      load(RichText(text, const [Entity(0, 11, EntityKind.link('u'))]), 0, 11);

      controller.removeLink();

      expect(controller.richText, const RichText.plain(text));
      expect(controller.text, text);
    });

    test('over part of a link keeps the rest of it', () {
      load(RichText(text, const [Entity(0, 11, EntityKind.link('u'))]), 0, 5);

      controller.removeLink();

      expect(
        controller.richText,
        RichText(text, const [Entity(5, 6, EntityKind.link('u'))]),
      );
    });

    test('leaves the other formatting', () {
      load(
        RichText(text, const [
          Entity(0, 5, EntityKind.bold),
          Entity(0, 5, EntityKind.link('u')),
        ]),
        0,
        5,
      );

      controller.removeLink();

      expect(
        controller.richText,
        RichText(text, const [Entity(0, 5, EntityKind.bold)]),
      );
    });

    test('does nothing at a caret', () {
      final linked = RichText(text, const [
        Entity(0, 11, EntityKind.link('u')),
      ]);
      load(linked, 3);

      controller.removeLink();

      expect(controller.richText, linked);
    });
  });

  group('clearFormatting', () {
    const smile = InlineContentRef(
      key: ContentKey.document('smile'),
      alternativeText: '\u{1F642}',
    );
    const text = 'bold @al \u{1F642} link\nquoted\nblock';

    RichText formatted() => RichText(text, [
      const Entity(0, 4, EntityKind.bold),
      const Entity(5, 3, _mention),
      Entity(9, 2, EntityKind.inlineContent(smile.key)),
      const Entity(12, 4, EntityKind.link('u')),
      const Entity(12, 4, EntityKind.italic),
      const Entity(17, 6, EntityKind.quote),
      const Entity(24, 5, EntityKind.codeBlock(language: 'dart')),
    ]);

    test('takes styles and links off the selection, keeps atoms', () {
      load(formatted(), 0, 16);

      controller.clearFormatting();

      expect(
        controller.richText,
        RichText(text, [
          const Entity(5, 3, _mention),
          Entity(9, 2, EntityKind.inlineContent(smile.key)),
          const Entity(17, 6, EntityKind.quote),
          const Entity(24, 5, EntityKind.codeBlock(language: 'dart')),
        ]),
      );
    });

    test('takes the lines of a quote and a block off', () {
      load(formatted(), 17, 29);

      controller.clearFormatting();

      expect(
        controller.richText,
        RichText(text, [
          const Entity(0, 4, EntityKind.bold),
          const Entity(5, 3, _mention),
          Entity(9, 2, EntityKind.inlineContent(smile.key)),
          const Entity(12, 4, EntityKind.link('u')),
          const Entity(12, 4, EntityKind.italic),
        ]),
      );
    });

    test('clears only the part of a style the selection holds', () {
      load(RichText('abcdefgh', const [Entity(0, 8, EntityKind.bold)]), 2, 5);

      controller.clearFormatting();

      expect(
        controller.richText,
        RichText('abcdefgh', const [
          Entity(0, 2, EntityKind.bold),
          Entity(5, 3, EntityKind.bold),
        ]),
      );
    });

    test('keeps a detected username and hashtag', () {
      final detected = RichText('@al #tag', const [
        Entity(0, 3, EntityKind.username('al')),
        Entity(4, 4, EntityKind.hashtag('tag')),
      ]);
      load(detected, 0, 8);

      controller.clearFormatting();

      expect(controller.richText, detected);
      expect(controller.canClearFormatting, isFalse);
    });

    test('does nothing at a caret', () {
      load(formatted(), 1);

      controller.clearFormatting();

      expect(controller.richText, formatted());
      expect(controller.canClearFormatting, isFalse);
    });

    test('canClearFormatting is true over formatting', () {
      load(formatted(), 0, 4);

      expect(controller.canClearFormatting, isTrue);
    });
  });

  group('isActive', () {
    // Each word carries the one kind its name says.
    const text =
        'bold italic under strike spoiler mono linked\n'
        'quoted\n'
        'block\n'
        'bullet\n'
        'number';
    int at(String word) => text.indexOf(word);

    RichText sample() => RichText(text, [
      Entity(at('bold'), 4, EntityKind.bold),
      Entity(at('italic'), 6, EntityKind.italic),
      Entity(at('under'), 5, EntityKind.underline),
      Entity(at('strike'), 6, EntityKind.strike),
      Entity(at('spoiler'), 7, EntityKind.spoiler),
      Entity(at('mono'), 4, EntityKind.code),
      Entity(at('linked'), 6, const EntityKind.link('u')),
      Entity(at('quoted'), 6, EntityKind.quote),
      Entity(at('block'), 5, const EntityKind.codeBlock(language: 'dart')),
      Entity(
        at('bullet'),
        6,
        const EntityKind.list(listKind: EntityListKind.bullet),
      ),
      Entity(
        at('number'),
        6,
        const EntityKind.list(listKind: EntityListKind.ordered, depth: 1),
      ),
    ]);

    final kinds = <String, EntityKind>{
      'bold': EntityKind.bold,
      'italic': EntityKind.italic,
      'underline': EntityKind.underline,
      'strike': EntityKind.strike,
      'spoiler': EntityKind.spoiler,
      'code': EntityKind.code,
      'link': const EntityKind.link('other'),
      'quote': EntityKind.quote,
      'codeBlock': const EntityKind.codeBlock(),
      'bullet': const EntityKind.list(listKind: EntityListKind.bullet),
      'ordered': const EntityKind.list(listKind: EntityListKind.ordered),
      'mention': _mention,
      'username': const EntityKind.username('al'),
      'hashtag': const EntityKind.hashtag('tag'),
    };

    // Selecting a word is active for the kind the word carries and no other.
    const words = {
      'bold': 'bold',
      'italic': 'italic',
      'under': 'underline',
      'strike': 'strike',
      'spoiler': 'spoiler',
      'mono': 'code',
      'linked': 'link',
      'quoted': 'quote',
      'block': 'codeBlock',
      'bullet': 'bullet',
      'number': 'ordered',
    };

    for (final MapEntry(key: word, value: active) in words.entries) {
      test('selecting "$word" is active for $active only', () {
        load(sample(), at(word), at(word) + word.length);

        expect(
          {
            for (final MapEntry(:key, :value) in kinds.entries)
              if (controller.isActive(value)) key,
          },
          {active},
        );
      });
    }

    test('a selection that is only partly in a style is not active', () {
      load(sample(), at('bold'), at('italic') + 6);

      expect(controller.isActive(EntityKind.bold), isFalse);
      expect(controller.isActive(EntityKind.italic), isFalse);
    });

    test('a selection part of the way into a word is active', () {
      load(sample(), at('bold') + 1, at('bold') + 3);

      expect(controller.isActive(EntityKind.bold), isTrue);
    });

    test('the whitespace around the word does not matter', () {
      load(sample(), at('bold'), at('bold') + 5);

      expect(controller.isActive(EntityKind.bold), isTrue);
    });

    test('a caret is active for a line kind on its line, not for a style', () {
      load(sample(), at('quoted') + 2);
      expect(controller.isActive(EntityKind.quote), isTrue);

      load(sample(), at('bold') + 2);
      expect(controller.isActive(EntityKind.bold), isFalse);
      expect(controller.isActive(const EntityKind.link('u')), isFalse);
    });

    test('a selection that touches a link is active for link', () {
      load(sample(), at('mono'), at('linked') + 2);

      expect(controller.isActive(const EntityKind.link('x')), isTrue);
    });

    test('a block of another language is active for the no-language kind', () {
      load(sample(), at('block'), at('block') + 5);

      expect(controller.isActive(const EntityKind.codeBlock()), isTrue);
      expect(
        controller.isActive(const EntityKind.codeBlock(language: 'dart')),
        isTrue,
      );
      expect(
        controller.isActive(const EntityKind.codeBlock(language: 'js')),
        isFalse,
      );
    });

    test('an unselected text has no active kind', () {
      load(const RichText.plain('plain'), 0, 5);

      for (final kind in kinds.values) {
        expect(controller.isActive(kind), isFalse, reason: '$kind');
      }
    });
  });

  group('canApply', () {
    test('is true for every formatting kind over plain text', () {
      load(const RichText.plain('one two'), 0, 7);

      for (final kind in [
        EntityKind.bold,
        EntityKind.italic,
        EntityKind.underline,
        EntityKind.strike,
        EntityKind.spoiler,
        EntityKind.code,
        EntityKind.quote,
        const EntityKind.codeBlock(),
        const EntityKind.link('u'),
      ]) {
        expect(controller.canApply(kind), isTrue, reason: '$kind');
      }
    });

    test('is false for a list kind unless the controller edits lists', () {
      load(const RichText.plain('one two'), 0, 7);
      const bullet = EntityKind.list(listKind: EntityListKind.bullet);

      expect(controller.canApply(bullet), isFalse);

      final listing = ComposerTextController(
        initial: const RichText.plain('one two'),
        lists: true,
      )..selection = const TextSelection(baseOffset: 0, extentOffset: 7);
      addTearDown(listing.dispose);

      expect(listing.canApply(bullet), isTrue);
    });

    test('is false for the kinds that are not formatting', () {
      load(const RichText.plain('one two'), 0, 7);

      expect(controller.canApply(_mention), isFalse);
      expect(controller.canApply(const EntityKind.username('a')), isFalse);
      expect(controller.canApply(const EntityKind.hashtag('a')), isFalse);
    });

    test('is true for an active kind, which a toggle turns off', () {
      load(RichText('one', const [Entity(0, 3, EntityKind.bold)]), 0, 3);

      expect(controller.canApply(EntityKind.bold), isTrue);
    });

    test('a list kind is false where a quote or a block holds the line', () {
      load(RichText('one', const [Entity(0, 3, EntityKind.quote)]), 1);

      expect(
        controller.canApply(
          const EntityKind.list(listKind: EntityListKind.bullet),
        ),
        isFalse,
      );
    });

    test('with no selection acts on the end of the text', () {
      controller.restore(const RichText.plain('one'));
      controller.selection = const TextSelection.collapsed(offset: -1);

      expect(controller.canApply(EntityKind.bold), isFalse);
      expect(controller.canApply(EntityKind.quote), isTrue);
    });
  });

  group('while the input method composes', () {
    void compose(TextRange composing, TextSelection selection) {
      controller.value = TextEditingValue(
        text: 'hello wor',
        selection: selection,
        composing: composing,
      );
    }

    setUp(() => controller.restore(const RichText.plain('hello wo')));

    test('a command away from the composition leaves it alone', () {
      compose(
        const TextRange(start: 6, end: 9),
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );

      controller.toggleStyle(EntityStyle.bold);

      expect(controller.isComposing, isTrue);
      expect(controller.value.composing, const TextRange(start: 6, end: 9));
      expect(controller.text, 'hello wor');
      expect(
        controller.richText,
        RichText('hello wor', const [Entity(0, 5, EntityKind.bold)]),
      );

      controller.commitComposition('hello word');

      expect(
        controller.richText,
        RichText('hello word', const [Entity(0, 5, EntityKind.bold)]),
      );
    });

    test('a command over the composition does nothing', () {
      compose(
        const TextRange(start: 6, end: 9),
        const TextSelection(baseOffset: 4, extentOffset: 8),
      );

      expect(controller.canApply(EntityKind.bold), isFalse);
      controller.toggleStyle(EntityStyle.bold);

      expect(controller.richText, const RichText.plain('hello wor'));
      expect(controller.value.composing, const TextRange(start: 6, end: 9));
    });

    test('a line command on the composing line does nothing', () {
      compose(
        const TextRange(start: 6, end: 9),
        const TextSelection.collapsed(offset: 9),
      );

      expect(controller.canApply(EntityKind.quote), isFalse);
      controller.toggleStyle(EntityStyle.quote);

      expect(controller.richText, const RichText.plain('hello wor'));
    });

    test('a link at a caret is not inserted under the composition', () {
      compose(
        const TextRange(start: 6, end: 9),
        const TextSelection.collapsed(offset: 2),
      );

      controller.applyLink('u');

      expect(controller.text, 'hello wor');
    });

    test('a selection cutting into a mention widens to the whole mention', () {
      controller.restore(RichText('hi @al ok', const [Entity(3, 3, _mention)]));
      controller.value = const TextEditingValue(
        text: 'hi @al okx',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
        composing: TextRange(start: 9, end: 10),
      );

      controller.toggleStyle(EntityStyle.bold);

      expect(
        controller.richText,
        RichText('hi @al okx', const [
          Entity(0, 6, EntityKind.bold),
          Entity(3, 3, _mention),
        ]),
      );
    });
  });
}
