import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

import '../support/pack_assets.dart';

ContentKey$Unicode _key(String hex) =>
    ContentKey.parse('unicode:$hex') as ContentKey$Unicode;

EmojiEntry _thumb() => EmojiEntry(
  base: _key('1F44D'),
  variants: [
    EmojiVariant(
      _key('1F44D-1F3FB'),
      EmojiModifiers(tones: const [SkinTone.light]),
    ),
    EmojiVariant(
      _key('1F44D-1F3FF'),
      EmojiModifiers(tones: const [SkinTone.dark]),
    ),
  ],
);

EmojiCatalogStructure _structure(List<List<EmojiEntry>> subgroups) =>
    EmojiCatalogStructure(
      emojiVersion: '18.0',
      groups: [
        for (var i = 0; i < subgroups.length; i++)
          EmojiCatalogGroup(
            id: 'group-$i',
            subgroups: [EmojiCatalogSubgroup(id: 's', entries: subgroups[i])],
          ),
      ],
    );

// 🙅 as the data has it: the person, each tone, then the man and the woman,
// each alone and with each tone.
EmojiEntry _gesturingNo() {
  const tones = SkinTone.values;
  String tone(SkinTone t) => switch (t) {
    SkinTone.light => '1F3FB',
    SkinTone.mediumLight => '1F3FC',
    SkinTone.medium => '1F3FD',
    SkinTone.mediumDark => '1F3FE',
    SkinTone.dark => '1F3FF',
  };
  return EmojiEntry(
    base: _key('1F645'),
    variants: [
      for (final t in tones)
        EmojiVariant(_key('1F645-${tone(t)}'), EmojiModifiers(tones: [t])),
      for (final (g, sign) in [
        (EmojiGender.man, '2642'),
        (EmojiGender.woman, '2640'),
      ]) ...[
        EmojiVariant(
          _key('1F645-200D-$sign-FE0F'),
          EmojiModifiers(genders: [g]),
        ),
        for (final t in tones)
          EmojiVariant(
            _key('1F645-${tone(t)}-200D-$sign-FE0F'),
            EmojiModifiers(tones: [t], genders: [g]),
          ),
      ],
    ],
  );
}

void main() {
  group('genders, as the reference client lists them', () {
    final catalog = EmojiCatalog(
      _structure([
        [_gesturingNo(), _thumb()],
      ]),
    );

    test('the person, the man and the woman are entries of their own, in '
        'that order, each with its five tones', () {
      expect(
        [for (final entry in catalog.entries) entry.base],
        [
          _key('1F645'),
          _key('1F645-200D-2642-FE0F'),
          _key('1F645-200D-2640-FE0F'),
          _key('1F44D'),
        ],
      );
      for (final entry in catalog.entries.take(3)) {
        expect(entry.variants, hasLength(5), reason: '${entry.base}');
        expect(entry.hasToneVariants, isTrue);
      }
    });

    test('a tone of the man belongs to the man', () {
      final man = catalog.entryOf(_key('1F645-1F3FF-200D-2642-FE0F'))!;

      expect(man.base, _key('1F645-200D-2642-FE0F'));
      expect(catalog.entryOf(_key('1F645-1F3FF'))!.base, _key('1F645'));
    });

    test('every key of the data still belongs to exactly one entry', () {
      final keys = [
        for (final entry in catalog.entries) ...[
          entry.base,
          for (final v in entry.variants) v.key,
        ],
      ];

      expect(keys.toSet(), hasLength(keys.length));
      expect(keys, hasLength(18 + 3));
    });

    test('an entry with no gender is unchanged', () {
      expect(catalog.entryOf(_key('1F44D')), _thumb());
    });

    test('can be kept merged: one entry with every gender and tone', () {
      final merged = EmojiCatalog(
        _structure([
          [_gesturingNo()],
        ]),
        flattenGenders: false,
      );

      expect(merged.entries.single, _gesturingNo());
    });
  });

  group('entryOf', () {
    final catalog = EmojiCatalog(
      _structure([
        [_thumb()],
        [EmojiEntry(base: _key('1F600'))],
      ]),
    );

    test('finds an entry by its base key', () {
      expect(catalog.entryOf(_key('1F44D')), _thumb());
    });

    test('finds an entry by the key of one of its variants', () {
      expect(catalog.entryOf(_key('1F44D-1F3FF')), _thumb());
    });

    test('is null for a key the catalogue does not hold', () {
      expect(catalog.entryOf(_key('1F4A9')), isNull);
      expect(catalog.entryOf(const ContentKey.document('1')), isNull);
    });
  });

  group('order', () {
    final catalog = EmojiCatalog(
      _structure([
        [_thumb()],
        [EmojiEntry(base: _key('1F600'))],
      ]),
    );

    test('numbers entries in palette order, variants after their entry', () {
      expect(catalog.positionOf(_key('1F44D')), 0);
      expect(catalog.positionOf(_key('1F44D-1F3FB')), 0);
      expect(catalog.positionOf(_key('1F600')), 1);
      expect(catalog.positionOf(_key('1F4A9')), isNull);
    });

    test('lists entries of a group in order', () {
      expect(
        [for (final e in catalog.entriesOf('group-1')) e.base],
        [_key('1F600')],
      );
      expect(catalog.entriesOf('missing'), isEmpty);
    });
  });

  test('refuses a structure holding one key in two entries', () {
    expect(
      () => EmojiCatalog(
        _structure([
          [EmojiEntry(base: _key('1F600'))],
          [EmojiEntry(base: _key('1F600'))],
        ]),
      ),
      throwsArgumentError,
    );
  });

  test('indexes the shipped structure without a repeated key', () async {
    final structure = EmojiCatalogStructure.decode(
      await readShippedAsset(EmojiCatalogPackAssets.structure),
    );

    expect(
      EmojiCatalog(structure, flattenGenders: false).entries,
      hasLength(1759),
    );
    // Split by gender: more entries, the same keys.
    int keys(EmojiCatalog catalog) => catalog.entries.fold(
      0,
      (sum, entry) => sum + 1 + entry.variants.length,
    );
    final flat = EmojiCatalog(structure);
    expect(flat.entries.length, greaterThan(1759));
    expect(keys(flat), keys(EmojiCatalog(structure, flattenGenders: false)));
  });
}
