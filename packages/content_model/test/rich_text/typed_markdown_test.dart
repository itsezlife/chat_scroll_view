/// `TypedMarkdown`: the markers a user types (`` `code` ``, `**bold**`, ...)
/// become entities at send, with Telegram Android's rules
/// (`MediaDataController.getEntities`).
///
/// **Seam:** `TypedMarkdown.apply` over [RichText].
library;

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

RichText _apply(String text, [List<Entity> entities = const []]) =>
    TypedMarkdown.apply(RichText(text, entities));

void main() {
  group('inline code', () {
    test('`a` becomes code and loses its backticks', () {
      expect(
        _apply('x `a` y'),
        RichText('x a y', const [Entity(2, 1, EntityKind.code)]),
      );
    });

    test('several spans in one text', () {
      expect(
        _apply('`a` and `bc`'),
        RichText('a and bc', const [
          Entity(0, 1, EntityKind.code),
          Entity(6, 2, EntityKind.code),
        ]),
      );
    });

    test('an empty pair, an unpaired backtick and a pair across a line break '
        'stay text', () {
      for (final text in const ['a `` b', 'a `b', 'a `b\nc` d']) {
        expect(_apply(text), RichText.plain(text), reason: text);
      }
    });

    test('text with no marker comes back as it is', () {
      const text = RichText.plain('nothing here');
      expect(identical(TypedMarkdown.apply(text), text), isTrue);
    });
  });

  group('styles', () {
    for (final (marker, kind) in [
      ('**', EntityKind.bold),
      ('__', EntityKind.italic),
      ('~~', EntityKind.strike),
      ('||', EntityKind.spoiler),
    ]) {
      test('$marker a $marker becomes ${kind.style.name}', () {
        expect(
          _apply('x ${marker}a b$marker y'),
          RichText('x a b y', [Entity(2, 3, kind)]),
        );
      });
    }

    test('a marker pair never crosses a line break', () {
      expect(_apply('**a\nb**'), const RichText.plain('**a\nb**'));
    });

    test('an empty pair and a lone marker stay text', () {
      for (final text in const ['**** a', '**a', '~~ x']) {
        expect(_apply(text), RichText.plain(text), reason: text);
      }
    });

    test('styles nest and keep the entities the text already had', () {
      expect(
        _apply('**a __b__ c** d', const [Entity(14, 1, EntityKind.underline)]),
        RichText('a b c d', const [
          Entity(0, 5, EntityKind.bold),
          Entity(2, 1, EntityKind.italic),
          Entity(6, 1, EntityKind.underline),
        ]),
      );
    });

    test('code is read first, so a marker inside it is text', () {
      expect(
        _apply('`**a**` and **b**'),
        RichText('**a** and b', const [
          Entity(0, 5, EntityKind.code),
          Entity(10, 1, EntityKind.bold),
        ]),
      );
    });
  });

  group('what stays text', () {
    test('a pair that touches a link, a mention or inline content', () {
      expect(
        _apply('**a b**', const [Entity(2, 1, EntityKind.link('https://u'))]),
        RichText('**a b**', const [Entity(2, 1, EntityKind.link('https://u'))]),
      );
      expect(
        _apply('**@x**', const [Entity(2, 2, EntityKind.mention('1'))]),
        RichText('**@x**', const [Entity(2, 2, EntityKind.mention('1'))]),
      );
    });

    test('a pair that touches code the text already has', () {
      expect(
        _apply('`a` **b**', const [Entity(0, 3, EntityKind.code)]),
        RichText('`a` b', const [
          Entity(0, 3, EntityKind.code),
          Entity(4, 1, EntityKind.bold),
        ]),
        reason: 'only the pair clear of the code converts',
      );
    });

    test('code over an entity the text already has', () {
      expect(
        _apply('`a b`', const [Entity(3, 1, EntityKind.bold)]),
        RichText('`a b`', const [Entity(3, 1, EntityKind.bold)]),
      );
    });

    test('a pair that lies inside a longer style converts', () {
      expect(
        _apply('a `b` c', const [Entity(0, 7, EntityKind.bold)]),
        RichText('a b c', const [
          Entity(0, 5, EntityKind.bold),
          Entity(2, 1, EntityKind.code),
        ]),
      );
    });
  });

  group('code block', () {
    test('``` on lines of their own around the code', () {
      expect(
        _apply('```\nvar a;\n```'),
        RichText('var a;', const [Entity(0, 6, EntityKind.codeBlock())]),
      );
    });

    test('a first line that names a language is the language', () {
      expect(
        _apply('```dart\nvar a;\n```'),
        RichText('var a;', const [
          Entity(0, 6, EntityKind.codeBlock(language: 'dart')),
        ]),
      );
    });

    test('a first line that is code, not a name, stays in the block', () {
      expect(
        _apply('```print(1)\nx```'),
        RichText('print(1)\nx', const [Entity(0, 10, EntityKind.codeBlock())]),
      );
    });

    test('inside a line it takes lines of its own', () {
      expect(
        _apply('a ```b``` c'),
        RichText('a\nb\nc', const [Entity(2, 1, EntityKind.codeBlock())]),
      );
    });

    test('markers inside it are text, and so are backticks', () {
      expect(
        _apply('```\n**a** `b`\n```'),
        RichText('**a** `b`', const [Entity(0, 9, EntityKind.codeBlock())]),
      );
    });

    test('an empty block, an unclosed fence and a block over an entity stay '
        'text', () {
      expect(_apply('``` ```'), const RichText.plain('``` ```'));
      expect(_apply('```a'), const RichText.plain('```a'));
      expect(
        _apply('```a b```', const [Entity(5, 1, EntityKind.bold)]),
        RichText('```a b```', const [Entity(5, 1, EntityKind.bold)]),
      );
    });
  });

  test('running it twice changes nothing', () {
    final once = _apply('**a** `b` __c__ ~~d~~ ||e||');
    expect(TypedMarkdown.apply(once), once);
  });
}
