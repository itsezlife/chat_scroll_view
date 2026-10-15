import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

// Code point escapes keep the sequences readable and exact; a glyph in source
// would hide the ZWJ and FE0F that these tests are about.
const _zwj = '‍';
const _fe0f = '️';
const _male = '♂';
const _female = '♀';

const _light = '\u{1F3FB}';
const _mediumLight = '\u{1F3FC}';
const _medium = '\u{1F3FD}';
const _mediumDark = '\u{1F3FE}';
const _dark = '\u{1F3FF}';

ContentKey$Unicode _key(String sequence) => ContentKey$Unicode(sequence);

EmojiVariant _variant(
  String sequence, {
  List<SkinTone> tones = const [],
  List<EmojiGender> genders = const [],
}) => EmojiVariant(
  _key(sequence),
  EmojiModifiers(tones: tones, genders: genders),
);

/// 👍: one base, five one-person tones, no FE0F anywhere.
EmojiEntry _thumbsUp() {
  const base = '\u{1F44D}';
  return EmojiEntry(
    base: _key(base),
    variants: [
      _variant('$base$_light', tones: [SkinTone.light]),
      _variant('$base$_mediumLight', tones: [SkinTone.mediumLight]),
      _variant('$base$_medium', tones: [SkinTone.medium]),
      _variant('$base$_mediumDark', tones: [SkinTone.mediumDark]),
      _variant('$base$_dark', tones: [SkinTone.dark]),
    ],
  );
}

/// ☝️: the base is the FE0F form, and a tone replaces the selector.
EmojiEntry _indexPointingUp() {
  const text = '☝';
  return EmojiEntry(
    base: _key('$text$_fe0f'),
    variants: [
      _variant('$text$_light', tones: [SkinTone.light]),
      _variant('$text$_dark', tones: [SkinTone.dark]),
    ],
  );
}

/// 🏃: gender is a ZWJ suffix and a tone sits before it.
EmojiEntry _runner() {
  const base = '\u{1F3C3}';
  return EmojiEntry(
    base: _key(base),
    variants: [
      _variant('$base$_zwj$_male$_fe0f', genders: const [EmojiGender.man]),
      _variant('$base$_zwj$_female$_fe0f', genders: const [EmojiGender.woman]),
      _variant('$base$_medium', tones: [SkinTone.medium]),
      _variant(
        '$base$_medium$_zwj$_male$_fe0f',
        tones: [SkinTone.medium],
        genders: const [EmojiGender.man],
      ),
      _variant(
        '$base$_medium$_zwj$_female$_fe0f',
        tones: [SkinTone.medium],
        genders: const [EmojiGender.woman],
      ),
    ],
  );
}

/// 🫱‍🫲: a pair of hands, one tone per person, in sequence order.
EmojiEntry _handshake() {
  const right = '\u{1FAF1}';
  const left = '\u{1FAF2}';
  return EmojiEntry(
    base: _key('$right$_zwj$left'),
    variants: [
      _variant('$right$_light$_zwj$left$_light', tones: [SkinTone.light]),
      _variant(
        '$right$_light$_zwj$left$_mediumLight',
        tones: [SkinTone.light, SkinTone.mediumLight],
      ),
      _variant(
        '$right$_mediumLight$_zwj$left$_light',
        tones: [SkinTone.mediumLight, SkinTone.light],
      ),
    ],
  );
}

void main() {
  group('EmojiModifiers', () {
    test('none has no tone and no gender', () {
      expect(EmojiModifiers.none.tones, isEmpty);
      expect(EmojiModifiers.none.genders, isEmpty);
      expect(EmojiModifiers(), EmojiModifiers.none);
    });

    test('is a value of its ordered tones and genders', () {
      final a = EmojiModifiers(
        tones: const [SkinTone.light, SkinTone.dark],
        genders: const [EmojiGender.woman],
      );
      final b = EmojiModifiers(
        tones: const [SkinTone.light, SkinTone.dark],
        genders: const [EmojiGender.woman],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test(
      'tone order is significant: one tone per person, in sequence order',
      () {
        expect(
          EmojiModifiers(tones: const [SkinTone.light, SkinTone.dark]),
          isNot(EmojiModifiers(tones: const [SkinTone.dark, SkinTone.light])),
        );
      },
    );

    test('one tone for two people differs from two equal tones', () {
      expect(
        EmojiModifiers(tones: const [SkinTone.light]),
        isNot(EmojiModifiers(tones: const [SkinTone.light, SkinTone.light])),
      );
    });

    test('tone and gender each distinguish', () {
      expect(
        EmojiModifiers(tones: const [SkinTone.light]),
        isNot(EmojiModifiers(tones: const [SkinTone.dark])),
      );
      expect(
        EmojiModifiers(genders: const [EmojiGender.man]),
        isNot(EmojiModifiers(genders: const [EmojiGender.woman])),
      );
      expect(
        EmojiModifiers(genders: const [EmojiGender.man]),
        isNot(EmojiModifiers.none),
      );
    });

    test('copies its tones, so the source list cannot change it', () {
      final source = [SkinTone.light];
      final modifiers = EmojiModifiers(tones: source);

      source.add(SkinTone.dark);

      expect(modifiers.tones, [SkinTone.light]);
    });

    test('tones cannot be modified', () {
      final modifiers = EmojiModifiers(tones: const [SkinTone.light]);

      expect(() => modifiers.tones.add(SkinTone.dark), throwsUnsupportedError);
      expect(
        () => EmojiModifiers.none.tones.add(SkinTone.dark),
        throwsUnsupportedError,
      );
    });
  });

  group('per-person gender', () {
    test('a pair carries one gender per person, in sequence order', () {
      expect(
        EmojiModifiers(genders: const [EmojiGender.woman, EmojiGender.man]),
        isNot(
          EmojiModifiers(genders: const [EmojiGender.man, EmojiGender.woman]),
        ),
      );
      expect(
        EmojiModifiers(genders: const [EmojiGender.man]),
        isNot(
          EmojiModifiers(genders: const [EmojiGender.man, EmojiGender.man]),
        ),
      );
    });

    test('a couple entry resolves each gender pairing to its own key', () {
      const heart = '\u200D\u2764\uFE0F\u200D';
      final entry = EmojiEntry(
        base: _key('\u{1F491}'),
        variants: [
          _variant(
            '\u{1F469}$heart\u{1F468}',
            genders: const [EmojiGender.woman, EmojiGender.man],
          ),
          _variant(
            '\u{1F468}$heart\u{1F468}',
            genders: const [EmojiGender.man, EmojiGender.man],
          ),
        ],
      );

      expect(
        entry
            .keyFor(
              EmojiModifiers(genders: const [EmojiGender.man, EmojiGender.man]),
            )!
            .sequence,
        '\u{1F468}$heart\u{1F468}',
      );
      expect(
        entry.keyFor(
          EmojiModifiers(genders: const [EmojiGender.man, EmojiGender.woman]),
        ),
        isNull,
      );
    });

    test('genders cannot be modified', () {
      expect(
        () => EmojiModifiers(
          genders: const [EmojiGender.man],
        ).genders.add(EmojiGender.woman),
        throwsUnsupportedError,
      );
    });
  });

  group('EmojiVariant', () {
    test('is a value of its key and modifiers', () {
      expect(
        _variant('a$_light', tones: [SkinTone.light]),
        _variant('a$_light', tones: [SkinTone.light]),
      );
      expect(
        _variant('a$_light', tones: [SkinTone.light]).hashCode,
        _variant('a$_light', tones: [SkinTone.light]).hashCode,
      );
      expect(
        _variant('a$_light', tones: [SkinTone.light]),
        isNot(_variant('a$_dark', tones: [SkinTone.light])),
      );
      expect(
        _variant('a$_light', tones: [SkinTone.light]),
        isNot(_variant('a$_light', tones: [SkinTone.dark])),
      );
    });
  });

  group('one-person tone', () {
    test('every tone is its own unicode key resolved by its modifiers', () {
      final entry = _thumbsUp();

      for (final tone in SkinTone.values) {
        final key = entry.keyFor(EmojiModifiers(tones: [tone]));
        expect(key, isNotNull, reason: '$tone');
        expect(entry.modifiersOf(key!), EmojiModifiers(tones: [tone]));
      }
    });

    test('no modifiers resolve to the base itself', () {
      final entry = _thumbsUp();

      expect(entry.keyFor(EmojiModifiers.none), entry.base);
      expect(entry.modifiersOf(entry.base), EmojiModifiers.none);
    });

    test('a tone the entry does not carry resolves to nothing', () {
      final entry = _indexPointingUp();

      expect(
        entry.keyFor(EmojiModifiers(tones: const [SkinTone.medium])),
        isNull,
      );
    });

    test('there is no integer tone index to store: the choice is a key', () {
      final entry = _thumbsUp();
      final chosen = entry.keyFor(
        EmojiModifiers(tones: const [SkinTone.mediumDark]),
      );

      // The stored preference is the variant's own stable string.
      expect(ContentKey.parse(chosen!.encoded), _key('\u{1F44D}$_mediumDark'));
    });

    test('lists its variants in the order the data gave them', () {
      final tones = [
        for (final variant in _thumbsUp().variants) variant.modifiers.tones,
      ];

      expect(tones, [
        [SkinTone.light],
        [SkinTone.mediumLight],
        [SkinTone.medium],
        [SkinTone.mediumDark],
        [SkinTone.dark],
      ]);
    });
  });

  group('FE0F forms', () {
    test('a tone replaces the selector, and each spelling is its own key', () {
      final entry = _indexPointingUp();

      expect(entry.base.sequence, '☝$_fe0f');
      expect(
        entry.keyFor(EmojiModifiers(tones: const [SkinTone.light]))!.sequence,
        '☝$_light',
      );
    });

    test('the unqualified spelling of a base is not silently folded in', () {
      final entry = _indexPointingUp();
      final unqualified = _key('☝');

      expect(entry.modifiersOf(unqualified), isNull);
      expect(entry.modifiersOf(entry.base), EmojiModifiers.none);
    });

    test('capability to take a tone comes from the variants alone', () {
      // Two sources of truth for "supports a skin tone" (a catalog flag and a
      // table of bases) disagreed for FE0F spellings. Here the capability is
      // derived from the variants the entry holds, and nothing else exists to
      // disagree with.
      expect(_indexPointingUp().hasToneVariants, isTrue);
      expect(_thumbsUp().hasToneVariants, isTrue);
      expect(EmojiEntry(base: _key('\u{1F600}')).hasToneVariants, isFalse);
      expect(
        EmojiEntry(
          base: _key('\u{1F3C3}'),
          variants: [
            _variant(
              '\u{1F3C3}$_zwj$_male$_fe0f',
              genders: const [EmojiGender.man],
            ),
          ],
        ).hasToneVariants,
        isFalse,
      );
    });
  });

  group('gender and tone together', () {
    test('gender is a modifier of its own, with or without a tone', () {
      final entry = _runner();

      expect(
        entry
            .keyFor(EmojiModifiers(genders: const [EmojiGender.man]))!
            .sequence,
        '\u{1F3C3}$_zwj$_male$_fe0f',
      );
      expect(
        entry
            .keyFor(
              EmojiModifiers(
                tones: const [SkinTone.medium],
                genders: const [EmojiGender.woman],
              ),
            )!
            .sequence,
        '\u{1F3C3}$_medium$_zwj$_female$_fe0f',
      );
    });

    test(
      'a tone with no gender and a gender with no tone are different keys',
      () {
        final entry = _runner();

        expect(
          entry.keyFor(EmojiModifiers(tones: const [SkinTone.medium])),
          isNot(entry.keyFor(EmojiModifiers(genders: const [EmojiGender.man]))),
        );
      },
    );

    test('every gender and tone combination of an entry round-trips', () {
      final entry = _runner();

      for (final variant in entry.variants) {
        expect(entry.keyFor(variant.modifiers), variant.key);
        expect(entry.modifiersOf(variant.key), variant.modifiers);
      }
    });
  });

  group('two-person tone sequences', () {
    test('a pair carries one tone per person, in sequence order', () {
      final entry = _handshake();
      final key = entry.keyFor(
        EmojiModifiers(tones: const [SkinTone.light, SkinTone.mediumLight]),
      );

      expect(key!.sequence, '\u{1FAF1}$_light$_zwj\u{1FAF2}$_mediumLight');
    });

    test('the reverse order is a different variant', () {
      final entry = _handshake();

      expect(
        entry.keyFor(
          EmojiModifiers(tones: const [SkinTone.light, SkinTone.mediumLight]),
        ),
        isNot(
          entry.keyFor(
            EmojiModifiers(tones: const [SkinTone.mediumLight, SkinTone.light]),
          ),
        ),
      );
    });

    test(
      'one shared tone is distinct from the same tone given to each person',
      () {
        final entry = _handshake();

        expect(
          entry.keyFor(EmojiModifiers(tones: const [SkinTone.light])),
          isNotNull,
        );
        expect(
          entry.keyFor(
            EmojiModifiers(tones: const [SkinTone.light, SkinTone.light]),
          ),
          isNull,
        );
      },
    );

    test('a tone pair the entry does not hold resolves to nothing', () {
      expect(
        _handshake().keyFor(
          EmojiModifiers(tones: const [SkinTone.dark, SkinTone.light]),
        ),
        isNull,
      );
    });
  });

  group('lookup by key', () {
    test('a key that is neither the base nor a variant has no modifiers', () {
      expect(_thumbsUp().modifiersOf(_key('\u{1F600}')), isNull);
      expect(_thumbsUp().modifiersOf(const ContentKey.document('1')), isNull);
    });
  });

  group('EmojiEntry', () {
    test('without variants is just its base', () {
      final entry = EmojiEntry(base: _key('\u{1F600}'));

      expect(entry.variants, isEmpty);
      expect(entry.keyFor(EmojiModifiers.none), entry.base);
    });

    test('is a value of its base and ordered variants', () {
      expect(_thumbsUp(), _thumbsUp());
      expect(_thumbsUp().hashCode, _thumbsUp().hashCode);
      expect(_thumbsUp(), isNot(_runner()));
      expect(_thumbsUp(), isNot(EmojiEntry(base: _thumbsUp().base)));
      expect(
        EmojiEntry(
          base: _key('a'),
          variants: [
            _variant('a1', tones: [SkinTone.light]),
            _variant('a2', tones: [SkinTone.dark]),
          ],
        ),
        isNot(
          EmojiEntry(
            base: _key('a'),
            variants: [
              _variant('a2', tones: [SkinTone.dark]),
              _variant('a1', tones: [SkinTone.light]),
            ],
          ),
        ),
      );
    });

    test('copies its variants, so the source list cannot change it', () {
      final source = [
        _variant('a1', tones: [SkinTone.light]),
      ];
      final entry = EmojiEntry(base: _key('a'), variants: source);

      source.add(_variant('a2', tones: [SkinTone.dark]));

      expect(entry.variants, hasLength(1));
    });

    test('variants cannot be modified', () {
      final entry = _thumbsUp();

      expect(
        () => entry.variants.add(_variant('x', tones: [SkinTone.light])),
        throwsUnsupportedError,
      );
      expect(entry.variants.clear, throwsUnsupportedError);
    });

    test('rejects two variants with the same modifiers', () {
      expect(
        () => EmojiEntry(
          base: _key('a'),
          variants: [
            _variant('a1', tones: [SkinTone.light]),
            _variant('a2', tones: [SkinTone.light]),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects two variants with the same key', () {
      expect(
        () => EmojiEntry(
          base: _key('a'),
          variants: [
            _variant('a1', tones: [SkinTone.light]),
            _variant('a1', tones: [SkinTone.dark]),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a variant that is the base or claims no modifiers', () {
      expect(
        () => EmojiEntry(
          base: _key('a'),
          variants: [
            _variant('a', tones: [SkinTone.light]),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => EmojiEntry(base: _key('a'), variants: [_variant('a1')]),
        throwsArgumentError,
      );
    });
  });
}
