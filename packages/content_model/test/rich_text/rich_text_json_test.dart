import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  const thumbsUp = ContentKey.unicode('\u{1F44D}');

  final everything = RichText('bold \u{1F44D} link @bob\nquote', const [
    Entity(0, 4, EntityKind.bold),
    Entity(5, 2, EntityKind.inlineContent(thumbsUp)),
    Entity(8, 4, EntityKind.link('https://example.com/a?b=c')),
    Entity(13, 4, EntityKind.mention('bob')),
    Entity(18, 5, EntityKind.quote),
    Entity(18, 5, EntityKind.italic),
  ]);

  group('toJson', () {
    test('writes the text and each entity with its payload', () {
      final json = RichText('a@b', const [
        Entity(0, 1, EntityKind.bold),
        Entity(1, 2, EntityKind.mention('b')),
      ]).toJson();

      expect(json, {
        'text': 'a@b',
        'entities': [
          {'offset': 0, 'length': 1, 'kind': 'bold'},
          {'offset': 1, 'length': 2, 'kind': 'mention', 'id': 'b'},
        ],
      });
    });

    test('omits the entity list for plain text', () {
      expect(const RichText.plain('hi').toJson(), {'text': 'hi'});
    });

    test('survives a trip through JSON text', () {
      final decoded = jsonDecode(jsonEncode(everything.toJson()));

      expect(RichText.fromJson(decoded), everything);
    });
  });

  group('fromJson', () {
    test('reads every kind, payload included', () {
      for (final entity in everything.entities) {
        final single = RichText.fromJson({
          'text': everything.plain,
          'entities': [entity.toJson()],
        });

        expect(single.entities, [entity]);
      }
    });

    test('skips a kind this version does not know', () {
      final text = RichText.fromJson(const {
        'text': 'abc',
        'entities': [
          {'offset': 0, 'length': 1, 'kind': 'hologram'},
          {'offset': 1, 'length': 2, 'kind': 'bold'},
        ],
      });

      expect(text.plain, 'abc');
      expect(text.entities, [const Entity(1, 2, EntityKind.bold)]);
    });

    test('rejects data that is not rich text, naming what is wrong', () {
      const broken = <Object?>[
        null,
        'text',
        <String, Object?>{},
        {'text': 1},
        {'text': 'a', 'entities': 'bold'},
        {
          'text': 'a',
          'entities': ['bold'],
        },
        {
          'text': 'a',
          'entities': [
            {'offset': 0, 'length': 0, 'kind': 'bold'},
          ],
        },
        {
          'text': 'a',
          'entities': [
            {'offset': 0, 'length': 5, 'kind': 'bold'},
          ],
        },
        {
          'text': 'a',
          'entities': [
            {'offset': 0, 'length': 1, 'kind': 'link'},
          ],
        },
        {
          'text': 'a',
          'entities': [
            {'offset': 0, 'length': 1, 'kind': 'inlineContent', 'key': 'x'},
          ],
        },
      ];

      for (final json in broken) {
        expect(() => RichText.fromJson(json), throwsFormatException);
      }
    });

    test('tryFromJson gives null for the same data', () {
      expect(RichText.tryFromJson({'text': 1}), isNull);
      expect(RichText.tryFromJson(null), isNull);
      expect(RichText.tryFromJson({'text': 'a'}), const RichText.plain('a'));
    });

    test('canonicalises what it reads', () {
      final text = RichText.fromJson(const {
        'text': 'ab',
        'entities': [
          {'offset': 1, 'length': 1, 'kind': 'bold'},
          {'offset': 0, 'length': 1, 'kind': 'bold'},
        ],
      });

      expect(text.entities, [const Entity(0, 2, EntityKind.bold)]);
    });
  });
}
