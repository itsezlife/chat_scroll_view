import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_catalog_pack/generator.dart';
import 'package:test/test.dart';

/// Builds an emoji-test file from `hex sequence # name` lines, one subgroup.
EmojiTestFile _file(List<String> lines) => EmojiTestFile.parse(
  [
    '# Version: 18.0',
    '# group: People & Body',
    '# subgroup: person',
    for (final line in lines)
      '${line.split('|').first.padRight(24)}; fully-qualified # x E1.0 '
          '${line.contains('|') ? line.split('|').last : 'name'}',
  ].join('\n'),
);

ContentKey$Unicode _key(String hex) => ContentKey$Unicode(
  String.fromCharCodes([
    for (final part in hex.split(' ')) int.parse(part, radix: 16),
  ]),
);

EmojiCatalogStructure _build(List<String> lines) =>
    buildStructure(_file(lines));

List<EmojiEntry> _entries(EmojiCatalogStructure structure) => [
  for (final group in structure.groups)
    for (final subgroup in group.subgroups) ...subgroup.entries,
];

void main() {
  group('buildStructure', () {
    test('keeps an emoji without variants as a bare entry', () {
      final entries = _entries(_build(['1F600', '1F603']));

      expect(entries.map((e) => e.base), [_key('1F600'), _key('1F603')]);
      expect(entries.every((e) => e.variants.isEmpty), isTrue);
    });

    test('folds skin tones into the toneless entry, in file order', () {
      final entries = _entries(_build(['1F44B', '1F44B 1F3FB', '1F44B 1F3FF']));

      expect(entries, hasLength(1));
      expect(entries.single.variants, [
        EmojiVariant(
          _key('1F44B 1F3FB'),
          EmojiModifiers(tones: const [SkinTone.light]),
        ),
        EmojiVariant(
          _key('1F44B 1F3FF'),
          EmojiModifiers(tones: const [SkinTone.dark]),
        ),
      ]);
    });

    test('matches a toned sequence to a base spelled with FE0F', () {
      final entries = _entries(_build(['270C FE0F', '270C 1F3FD']));

      expect(entries.single.base, _key('270C FE0F'));
      expect(
        entries.single.keyFor(EmojiModifiers(tones: const [SkinTone.medium])),
        _key('270C 1F3FD'),
      );
    });

    test('keeps the tones of a multi-person sequence in person order', () {
      final entries = _entries(
        _build([
          '1FAF1 200D 1FAF2',
          '1FAF1 1F3FB 200D 1FAF2 1F3FF',
          '1FAF1 1F3FF 200D 1FAF2 1F3FB',
        ]),
      );

      expect(entries.single.variants.map((v) => v.modifiers), [
        EmojiModifiers(tones: const [SkinTone.light, SkinTone.dark]),
        EmojiModifiers(tones: const [SkinTone.dark, SkinTone.light]),
      ]);
    });

    test('files a mixed-tone sequence under the entry of the same name', () {
      // The toneless twin of a mixed-tone handshake is not an emoji, so the
      // skeleton finds nothing; the name before the colon does.
      final entries = _entries(
        _build([
          '1F91D|handshake',
          '1FAF1 1F3FB 200D 1FAF2 1F3FC|handshake: light skin tone, '
              'medium-light skin tone',
        ]),
      );

      expect(entries.single.base, _key('1F91D'));
      expect(
        entries.single.keyFor(
          EmojiModifiers(tones: const [SkinTone.light, SkinTone.mediumLight]),
        ),
        _key('1FAF1 1F3FB 200D 1FAF2 1F3FC'),
      );
    });

    test('resolves a mixed-tone group through a gendered entry to its root', () {
      final entries = _entries(
        _build([
          '1F46F|people with bunny ears',
          '1F46F 200D 2642 FE0F|men with bunny ears',
          '1F468 1F3FB 200D 1F430 200D 1F468 1F3FC|men with bunny ears: light '
              'skin tone, medium-light skin tone',
        ]),
      );

      expect(entries, hasLength(1));
      expect(
        entries.single.keyFor(
          EmojiModifiers(
            tones: const [SkinTone.light, SkinTone.mediumLight],
            genders: const [EmojiGender.man],
          ),
        ),
        _key('1F468 1F3FB 200D 1F430 200D 1F468 1F3FC'),
      );
    });

    test('folds a gender suffix into the neutral entry', () {
      final entries = _entries(
        _build([
          '1F3C3',
          '1F3C3 200D 2642 FE0F',
          '1F3C3 200D 2640 FE0F',
          '1F3C3 1F3FB',
          '1F3C3 1F3FB 200D 2640 FE0F',
        ]),
      );

      expect(entries, hasLength(1));
      expect(
        entries.single.keyFor(EmojiModifiers(genders: const [EmojiGender.man])),
        _key('1F3C3 200D 2642 FE0F'),
      );
      expect(
        entries.single.keyFor(
          EmojiModifiers(
            tones: const [SkinTone.light],
            genders: const [EmojiGender.woman],
          ),
        ),
        _key('1F3C3 1F3FB 200D 2640 FE0F'),
      );
    });

    test('folds the woman and man forms of a person into the person', () {
      final entries = _entries(
        _build(['1F9D1 200D 1F4BB', '1F468 200D 1F4BB', '1F469 200D 1F4BB']),
      );

      expect(entries, hasLength(1));
      expect(
        entries.single.keyFor(
          EmojiModifiers(genders: const [EmojiGender.woman]),
        ),
        _key('1F469 200D 1F4BB'),
      );
    });

    test('orders the genders of a couple by person', () {
      final entries = _entries(
        _build([
          '1F9D1 200D 2764 FE0F 200D 1F9D1',
          '1F469 200D 2764 FE0F 200D 1F468',
          '1F468 200D 2764 FE0F 200D 1F469',
        ]),
      );

      expect(
        entries.single.keyFor(
          EmojiModifiers(genders: const [EmojiGender.woman, EmojiGender.man]),
        ),
        _key('1F469 200D 2764 FE0F 200D 1F468'),
      );
      expect(
        entries.single.keyFor(
          EmojiModifiers(genders: const [EmojiGender.man, EmojiGender.woman]),
        ),
        _key('1F468 200D 2764 FE0F 200D 1F469'),
      );
    });

    test(
      'keeps a gendered sequence without a neutral twin as its own entry',
      () {
        final entries = _entries(
          _build(['1F468 200D 1F469 200D 1F466', '1F468']),
        );

        expect(entries.map((e) => e.base), [
          _key('1F468 200D 1F469 200D 1F466'),
          _key('1F468'),
        ]);
      },
    );

    test('files a variant under its parent and drops the emptied subgroup', () {
      final file = EmojiTestFile.parse(
        [
          '# Version: 18.0',
          '# group: People & Body',
          '# subgroup: person',
          '1F9D1                       ; fully-qualified # x E1.0 person',
          '# subgroup: family',
          '1F469                       ; fully-qualified # x E1.0 woman',
        ].join('\n'),
      );

      final structure = buildStructure(file);

      expect(structure.groups.single.subgroups.map((s) => s.id), ['person']);
      expect(structure.groups.single.subgroups.single.entries, hasLength(1));
    });

    test('rejects a toned sequence whose toneless form is missing', () {
      expect(() => _build(['1F44B 1F3FB']), throwsFormatException);
    });

    test('records the emoji version of the source', () {
      expect(_build(['1F600']).emojiVersion, '18.0');
    });
  });
}
