import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:test/test.dart';

const _source =
    '@emoji-catalog-structure\t1\n'
    '@emoji\t18.0\n'
    '@group\tpeople-body\n'
    '@subgroup\thand-fingers-open\n'
    '1F44B\t1F44B-1F3FB/1/\n'
    '@subgroup\tperson\n'
    '1F9D1-200D-1F4BB\t1F469-1F3FB-200D-1F4BB/1/w\n'
    '@group\tflags\n'
    '@subgroup\tcountry-flag\n'
    '1F1E9-1F1EA\n';

ContentKey$Unicode _key(List<int> codePoints) =>
    ContentKey$Unicode(String.fromCharCodes(codePoints));

void main() {
  group('EmojiCatalogStructure.decode', () {
    test('reads groups, subgroups and entries in file order', () {
      final structure = EmojiCatalogStructure.decode(_source);

      expect(structure.emojiVersion, '18.0');
      expect(structure.groups.map((g) => g.id), ['people-body', 'flags']);
      expect(structure.groups.first.subgroups.map((s) => s.id), [
        'hand-fingers-open',
        'person',
      ]);
      expect(structure.entries.map((e) => e.base), [
        _key([0x1F44B]),
        _key([0x1F9D1, 0x200D, 0x1F4BB]),
        _key([0x1F1E9, 0x1F1EA]),
      ]);
    });

    test('reads the tones and genders of a variant', () {
      final entry = EmojiCatalogStructure.decode(_source).entries.elementAt(1);

      expect(
        entry.variants.single.modifiers,
        EmojiModifiers(
          tones: const [SkinTone.light],
          genders: const [EmojiGender.woman],
        ),
      );
      expect(
        entry.variants.single.key,
        _key([0x1F469, 0x1F3FB, 0x200D, 0x1F4BB]),
      );
    });

    test('reads back what encode wrote', () {
      final structure = EmojiCatalogStructure.decode(_source);

      expect(structure.encode(), _source);
    });

    test('rejects a file of another format version', () {
      expect(
        () => EmojiCatalogStructure.decode(
          _source.replaceFirst('structure\t1', 'structure\t2'),
        ),
        throwsFormatException,
      );
    });

    test('rejects an entry outside a subgroup', () {
      expect(
        () => EmojiCatalogStructure.decode(
          '@emoji-catalog-structure\t1\n@emoji\t18.0\n1F600\n',
        ),
        throwsFormatException,
      );
    });

    test('rejects a tone that is not 1 to 5', () {
      expect(
        () => EmojiCatalogStructure.decode(
          _source.replaceFirst('1F44B-1F3FB/1/', '1F44B-1F3FB/6/'),
        ),
        throwsFormatException,
      );
    });

    test('rejects a key that is not hex code points', () {
      expect(
        () => EmojiCatalogStructure.decode(
          _source.replaceFirst('1F44B\t', 'smile\t'),
        ),
        throwsFormatException,
      );
    });

    test('rejects a file with no header', () {
      expect(
        () => EmojiCatalogStructure.decode('@group\tx\n'),
        throwsFormatException,
      );
    });
  });
}
