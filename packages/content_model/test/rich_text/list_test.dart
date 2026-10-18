/// A list item: one entity per item, whole lines, never merged.
///
/// **Seam:** [RichText] construction and its JSON.
library;

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

const _bullet = EntityKind.list(listKind: EntityListKind.bullet);
const _ordered = EntityKind.list(listKind: EntityListKind.ordered);
const _nested = EntityKind.list(listKind: EntityListKind.bullet, depth: 1);

void main() {
  group('the value', () {
    test('widens to whole lines, like a quote', () {
      expect(
        RichText('see\nitem one\nend', const [Entity(6, 2, _bullet)]).entities,
        const [Entity(4, 8, _bullet)],
      );
    });

    test('two adjacent items stay two entities', () {
      final text = RichText('one\ntwo', const [
        Entity(0, 3, _bullet),
        Entity(4, 3, _bullet),
      ]);

      expect(text.entities, const [
        Entity(0, 3, _bullet),
        Entity(4, 3, _bullet),
      ]);
    });

    test('an item with a soft break covers every line of it', () {
      final text = RichText('one\ncontinued\nnext', const [
        Entity(0, 13, _bullet),
        Entity(14, 4, _bullet),
      ]);

      expect(text.entities, const [
        Entity(0, 13, _bullet),
        Entity(14, 4, _bullet),
      ]);
    });

    test('items of different kinds and depths are separate', () {
      final text = RichText('a\nb\nc', const [
        Entity(0, 1, _bullet),
        Entity(2, 1, _ordered),
        Entity(4, 1, _nested),
      ]);

      expect(text.entities, hasLength(3));
    });

    test('a depth outside 0 to 3 is rejected', () {
      expect(
        () => RichText('a', [
          Entity(
            0,
            1,
            EntityKind.list(listKind: EntityListKind.bullet, depth: 4),
          ),
        ]),
        throwsA(anyOf(isArgumentError, isA<AssertionError>())),
      );
    });

    test('styles inside an item survive', () {
      final text = RichText('one two', const [
        Entity(0, 7, _bullet),
        Entity(4, 3, EntityKind.bold),
      ]);

      expect(text.entities, const [
        Entity(0, 7, _bullet),
        Entity(4, 3, EntityKind.bold),
      ]);
    });

    test('links, mentions and code inside an item survive', () {
      final text = RichText('a b c', const [
        Entity(0, 5, _bullet),
        Entity(0, 1, EntityKind.link('https://x')),
        Entity(2, 1, EntityKind.mention('7')),
        Entity(4, 1, EntityKind.code),
      ]);

      expect(text.entities, hasLength(4));
    });

    test(
      'an item and a quote on one line cannot both exist: the quote stays',
      () {
        final text = RichText('one\ntwo', const [
          Entity(0, 3, _bullet),
          Entity(0, 3, EntityKind.quote),
        ]);

        expect(text.entities, const [Entity(0, 3, EntityKind.quote)]);
      },
    );

    test('an item sharing one line with a quote is dropped whole', () {
      final text = RichText('a\nb\nc', const [
        Entity(0, 3, _bullet),
        Entity(2, 3, EntityKind.quote),
      ]);

      expect(text.entities, const [Entity(2, 3, EntityKind.quote)]);
    });

    test('an item and a code block cannot both exist: the block stays', () {
      final text = RichText('one\ntwo', const [
        Entity(0, 3, EntityKind.codeBlock()),
        Entity(0, 7, _ordered),
      ]);

      expect(text.entities, const [Entity(0, 3, EntityKind.codeBlock())]);
    });

    test('an item beside a quote on another line is untouched', () {
      final text = RichText('quote\nitem', const [
        Entity(0, 5, EntityKind.quote),
        Entity(6, 4, _bullet),
      ]);

      expect(text.entities, hasLength(2));
    });

    test('of two items on one line the one written first stays', () {
      // Two items that share a line are what remains after a line break
      // between two items is deleted.
      expect(
        RichText('onetwo', const [
          Entity(0, 3, _bullet),
          Entity(3, 3, _ordered),
        ]).entities,
        const [Entity(0, 6, _bullet)],
      );
      expect(
        RichText('onetwo', const [
          Entity(0, 3, _ordered),
          Entity(3, 3, _bullet),
        ]).entities,
        const [Entity(0, 6, _ordered)],
      );
      expect(
        RichText('onetwo', const [
          Entity(3, 3, _bullet),
          Entity(0, 3, _ordered),
        ]).entities,
        const [Entity(0, 6, _ordered)],
      );
    });

    test('equal items on one line are one item', () {
      expect(
        RichText('abc', const [
          Entity(0, 1, _bullet),
          Entity(2, 1, _bullet),
        ]).entities,
        const [Entity(0, 3, _bullet)],
      );
    });

    test('which of two kinds on one range stays does not depend on order', () {
      final a = RichText('abc', const [
        Entity(0, 3, _bullet),
        Entity(0, 3, _ordered),
      ]);
      final b = RichText('abc', const [
        Entity(0, 3, _ordered),
        Entity(0, 3, _bullet),
      ]);

      expect(a, b);
      expect(a.entities, hasLength(1));
    });

    test(
      'editing a line break between two items joins them into the first',
      () {
        final text = RichText('one\ntwo', const [
          Entity(0, 3, _bullet),
          Entity(4, 3, _ordered),
        ]).delete(3, 4);

        expect(text.plain, 'onetwo');
        expect(text.entities, const [Entity(0, 6, _bullet)]);
      },
    );

    test('is a value of its kind and depth', () {
      expect(_bullet, const EntityKind.list(listKind: EntityListKind.bullet));
      expect(_bullet, isNot(_ordered));
      expect(_bullet, isNot(_nested));
      expect(_bullet.isAtomic, isFalse);
    });
  });

  group('JSON', () {
    test('writes the kind and depth', () {
      final json = RichText('a', const [Entity(0, 1, _nested)]).toJson();

      expect(json['entities'], [
        {
          'offset': 0,
          'length': 1,
          'kind': 'list',
          'listKind': 'bullet',
          'depth': 1,
        },
      ]);
    });

    test('round trips every kind and depth', () {
      for (final listKind in EntityListKind.values) {
        for (var depth = 0; depth <= 3; depth++) {
          final text = RichText('a\nb', [
            const Entity(0, 1, _bullet),
            Entity(2, 1, EntityKind.list(listKind: listKind, depth: depth)),
          ]);

          expect(RichText.fromJson(text.toJson()), text);
        }
      }
    });

    test('a kind or depth it cannot read is a format error', () {
      for (final payload in const [
        <String, Object?>{},
        {'listKind': 'bullet'},
        {'listKind': 'roman', 'depth': 0},
        {'listKind': 'bullet', 'depth': 4},
        {'listKind': 'bullet', 'depth': -1},
        {'listKind': 'bullet', 'depth': 'x'},
      ]) {
        expect(
          () => RichText.fromJson({
            'text': 'a',
            'entities': [
              {'offset': 0, 'length': 1, 'kind': 'list', ...payload},
            ],
          }),
          throwsFormatException,
          reason: '$payload',
        );
      }
    });
  });
}
