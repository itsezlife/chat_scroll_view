/// `Username` and `Hashtag`: detected link-class text kinds.
///
/// **Seam:** [RichText] construction and its JSON.
library;

import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

const _alice = EntityKind.username('alice');
const _tag = EntityKind.hashtag('dart');

void main() {
  group('the value', () {
    test('is plain text: not atomic, may carry styles', () {
      expect(_alice.isAtomic, isFalse);
      expect(_tag.isAtomic, isFalse);

      final text = RichText('hi @alice!', const [
        Entity(3, 6, _alice),
        Entity(3, 3, EntityKind.bold),
      ]);

      expect(text.entities, const [
        Entity(3, 6, _alice),
        Entity(3, 3, EntityKind.bold),
      ]);
    });

    test('compares by payload', () {
      expect(const EntityKind.username('a'), const EntityKind.username('a'));
      expect(
        const EntityKind.username('a'),
        isNot(const EntityKind.username('b')),
      );
      expect(
        const EntityKind.hashtag('a'),
        isNot(const EntityKind.username('a')),
      );
    });

    test('needs a payload without a line break', () {
      for (final kind in const [
        EntityKind.username(''),
        EntityKind.username('a\nb'),
        EntityKind.hashtag(''),
        EntityKind.hashtag('a\rb'),
      ]) {
        expect(
          () => RichText('@abc', [Entity(0, 4, kind)]),
          throwsArgumentError,
          reason: '$kind',
        );
      }
    });

    test('splits at a line break, as a link does', () {
      expect(RichText('@a\n@b', const [Entity(0, 5, _alice)]).entities, const [
        Entity(0, 2, _alice),
        Entity(3, 2, _alice),
      ]);
    });

    test('touching equal kinds are one entity, as links are', () {
      expect(
        RichText('@a@b', const [
          Entity(0, 2, _alice),
          Entity(2, 2, _alice),
        ]).entities,
        const [Entity(0, 4, _alice)],
      );
    });

    test('a link cannot target the username or hashtag scheme', () {
      for (final url in const ['username:alice', 'hashtag:dart']) {
        expect(
          () => RichText('abc', [Entity(0, 3, EntityKind.link(url))]),
          throwsArgumentError,
          reason: url,
        );
      }
    });
  });

  group('overlap with a neighbouring kind: the username or hashtag yields', () {
    // One test per neighbouring kind. The other kinds are authored or
    // verified; these two are guesses made by detection.
    void yields(
      String name,
      RichText Function(EntityKind detected) build,
      List<Entity> expected,
    ) {
      for (final detected in const [_alice, _tag]) {
        test('$name ($detected)', () {
          expect(build(detected).entities, expected);
        });
      }
    }

    yields(
      'a link',
      (detected) => RichText('xx @abc xx', [
        const Entity(0, 6, EntityKind.link('https://x')),
        Entity(3, 4, detected),
      ]),
      const [Entity(0, 6, EntityKind.link('https://x'))],
    );
    yields(
      'a mention',
      (detected) => RichText('xx @abc xx', [
        const Entity(0, 5, EntityKind.mention('7')),
        Entity(3, 4, detected),
      ]),
      const [Entity(0, 5, EntityKind.mention('7'))],
    );
    yields(
      'inline content',
      (detected) => RichText('xx @abc xx', [
        const Entity(4, 3, EntityKind.inlineContent(ContentKey.document('d'))),
        Entity(3, 4, detected),
      ]),
      const [Entity(4, 3, EntityKind.inlineContent(ContentKey.document('d')))],
    );
    yields(
      'code',
      (detected) => RichText('xx @abc xx', [
        const Entity(5, 2, EntityKind.code),
        Entity(3, 4, detected),
      ]),
      const [Entity(5, 2, EntityKind.code)],
    );
    yields(
      'a code block',
      (detected) => RichText('@abc', [
        const Entity(0, 4, EntityKind.codeBlock()),
        Entity(0, 4, detected),
      ]),
      const [Entity(0, 4, EntityKind.codeBlock())],
    );

    test('another username or hashtag: the later one yields', () {
      expect(
        RichText('@abcdef', const [
          Entity(4, 3, _tag),
          Entity(0, 5, _alice),
        ]).entities,
        const [Entity(0, 5, _alice)],
      );
      expect(
        RichText('#abcdef', const [
          Entity(0, 3, _alice),
          Entity(0, 5, EntityKind.username('other')),
        ]).entities,
        // Same start: the longer is first in order, so it stays.
        const [Entity(0, 5, EntityKind.username('other'))],
      );
    });

    test('touching neighbours do not overlap', () {
      final text = RichText('@a#b[x]', const [
        Entity(0, 2, _alice),
        Entity(2, 2, _tag),
        Entity(4, 3, EntityKind.link('u')),
      ]);

      expect(text.entities, hasLength(3));
    });

    test('a style or quote around it is fine', () {
      final text = RichText('@abc', const [
        Entity(0, 4, _alice),
        Entity(0, 4, EntityKind.quote),
        Entity(1, 3, EntityKind.italic),
      ]);

      expect(text.entities, hasLength(3));
    });
  });

  group('JSON', () {
    test('writes the payload under its own key', () {
      final json = RichText('@a #b', const [
        Entity(0, 2, EntityKind.username('a')),
        Entity(3, 2, EntityKind.hashtag('b')),
      ]).toJson();

      expect(json['entities'], [
        {'offset': 0, 'length': 2, 'kind': 'username', 'name': 'a'},
        {'offset': 3, 'length': 2, 'kind': 'hashtag', 'tag': 'b'},
      ]);
    });

    test('round trips', () {
      final text = RichText('@a #b', const [
        Entity(0, 2, EntityKind.username('a')),
        Entity(3, 2, EntityKind.hashtag('b')),
      ]);

      expect(RichText.fromJson(text.toJson()), text);
    });

    test('a missing or empty payload is a format error', () {
      for (final entity in const [
        {'offset': 0, 'length': 2, 'kind': 'username'},
        {'offset': 0, 'length': 2, 'kind': 'username', 'name': ''},
        {'offset': 0, 'length': 2, 'kind': 'hashtag', 'tag': 3},
      ]) {
        expect(
          () => RichText.fromJson({
            'text': 'ab',
            'entities': [entity],
          }),
          throwsFormatException,
          reason: '$entity',
        );
      }
    });

    test('a reader that does not know the kinds skips them', () {
      // The shape every reader before these kinds saw: an entity whose kind
      // is a name it does not know loads without that formatting.
      final text = RichText.fromJson(const {
        'text': 'ab',
        'entities': [
          {'offset': 0, 'length': 2, 'kind': 'kindFromTheFuture', 'x': 1},
        ],
      });

      expect(text, const RichText.plain('ab'));
    });
  });
}
