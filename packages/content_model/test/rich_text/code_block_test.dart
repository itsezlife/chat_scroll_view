/// A code block: whole lines of code, with an optional language.
///
/// **Seam:** [RichText] construction, its JSON and `RichTextMarkdown`.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:test/test.dart';

const _dart = EntityKind.codeBlock(language: 'dart');
const _plainBlock = EntityKind.codeBlock();

void main() {
  group('the value', () {
    test('covers whole lines', () {
      expect(
        RichText('see\nmain() {}\nend', const [Entity(6, 3, _dart)]).entities,
        const [Entity(4, 9, _dart)],
      );
    });

    test('holds no other entity', () {
      expect(
        () => RichText('a()', const [
          Entity(0, 3, _dart),
          Entity(0, 1, EntityKind.bold),
        ]),
        throwsArgumentError,
      );
    });

    test('does not overlap a quote', () {
      expect(
        () => RichText('a()', const [
          Entity(0, 3, _dart),
          Entity(0, 3, EntityKind.quote),
        ]),
        throwsArgumentError,
      );
    });

    test('joins blocks that overlap; blocks on neighbouring lines stay two, '
        'as quotes do', () {
      expect(
        RichText('ab', const [
          Entity(0, 1, _dart),
          Entity(1, 1, _dart),
        ]).entities,
        const [Entity(0, 2, _dart)],
      );
      expect(
        RichText('a\nb', const [
          Entity(0, 1, _dart),
          Entity(2, 1, _dart),
        ]).entities,
        const [Entity(0, 1, _dart), Entity(2, 1, _dart)],
      );
      final two = RichText('a\nb', const [
        Entity(0, 1, _dart),
        Entity(2, 1, _plainBlock),
      ]);
      expect(RichTextMarkdown.decode(RichTextMarkdown.encode(two)), two);
    });

    test('takes a language of letters, digits and + # . _ -', () {
      for (final language in ['dart', 'c++', 'c#', 'objective-c', 'x.y_z']) {
        expect(
          () => RichText('a', [
            Entity(0, 1, EntityKind.codeBlock(language: language)),
          ]),
          returnsNormally,
          reason: language,
        );
      }
      for (final language in ['', 'two words', 'a\nb', '`']) {
        expect(
          () => RichText('a', [
            Entity(0, 1, EntityKind.codeBlock(language: language)),
          ]),
          throwsArgumentError,
          reason: language,
        );
      }
    });
  });

  test('reads back from JSON, language or not', () {
    final text = RichText('a\nb\nc', const [
      Entity(0, 1, _dart),
      Entity(4, 1, _plainBlock),
    ]);

    expect(RichText.fromJson(text.toJson()), text);
    expect(
      text.toJson()['entities'],
      contains(
        allOf(
          containsPair('kind', 'codeBlock'),
          containsPair('language', 'dart'),
        ),
      ),
    );
  });

  group('markdown', () {
    test('is a fence with the language as its info string', () {
      final text = RichText('before\nmain() {}\n  x;\nafter', const [
        Entity(7, 14, _dart),
      ]);

      expect(
        RichTextMarkdown.encode(text),
        'before\n```dart\nmain() {}\n  x;\n```\nafter',
      );
      expect(RichTextMarkdown.decode(RichTextMarkdown.encode(text)), text);
    });

    test('keeps code that holds backticks and markup as it is', () {
      final text = RichText('```\n**not bold** `x`', const [
        Entity(0, 20, _plainBlock),
      ]);

      expect(RichTextMarkdown.encode(text), startsWith('````\n'));
      expect(RichTextMarkdown.decode(RichTextMarkdown.encode(text)), text);
    });

    test('reads a fence another writer made, unclosed included', () {
      expect(
        RichTextMarkdown.decode('a\n~~~\nb'),
        isNot(RichText('a\nb', const [Entity(2, 1, _plainBlock)])),
        reason: 'only backtick fences are code blocks here',
      );
      expect(
        RichTextMarkdown.decode('```python\nprint(1)'),
        RichText('print(1)', const [
          Entity(0, 8, EntityKind.codeBlock(language: 'python')),
        ]),
      );
    });
  });
}
