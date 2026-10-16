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

void main() {
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

    expect(EmojiCatalog(structure).entries, hasLength(1759));
  });
}
