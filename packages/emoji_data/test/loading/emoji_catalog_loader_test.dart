import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:emoji_data/testing.dart';
import 'package:test/test.dart';

import '../support/pack_assets.dart';

const _structureText =
    '@emoji-catalog-structure\t1\n'
    '@emoji\t18.0\n'
    '@group\tsmileys-emotion\n'
    '@subgroup\tface-smiling\n'
    '1F600\n';

const _packText =
    '@emoji-catalog-keywords\t1\n'
    '@locale\tde\n'
    '@cldr\t49\n'
    '1F600\tgrinsendes Gesicht\tlachen|froh\n';

void main() {
  late FakeEmojiAssetLoader assets;
  late EmojiCatalogLoader loader;

  setUp(() {
    assets = FakeEmojiAssetLoader({
      EmojiCatalogPackAssets.structure: _structureText,
      EmojiCatalogPackAssets.keywordPack('de'): _packText,
    });
    loader = EmojiCatalogLoader(assets.load);
  });

  group('structure', () {
    test('reads and decodes the structure asset', () async {
      final structure = await loader.structure();

      expect(structure.emojiVersion, '18.0');
      expect(structure.entries, hasLength(1));
      expect(assets.requested, [EmojiCatalogPackAssets.structure]);
    });

    test('reads the asset once however often it is asked for', () async {
      final first = await loader.structure();
      final second = await loader.structure();

      expect(second, same(first));
      expect(assets.requested, hasLength(1));
    });

    test('shares one read between callers asking at the same time', () async {
      final both = await Future.wait([loader.structure(), loader.structure()]);

      expect(both.first, same(both.last));
      expect(assets.requested, hasLength(1));
    });

    test(
      'fails when the asset cannot be read, and reads it again later',
      () async {
        assets.failure = Exception('offline');
        await expectLater(loader.structure(), throwsException);

        assets.failure = null;

        expect((await loader.structure()).emojiVersion, '18.0');
      },
    );

    test('fails with a FormatException on a damaged asset', () async {
      assets.put(EmojiCatalogPackAssets.structure, 'not a structure');

      await expectLater(loader.structure(), throwsFormatException);
    });
  });

  group('keywordPack', () {
    test('reads only the pack of the locale asked for', () async {
      final pack = await loader.keywordPack('de');

      expect(pack.locale, 'de');
      expect(pack.records.single.spokenName, 'grinsendes Gesicht');
      expect(assets.requested, [EmojiCatalogPackAssets.keywordPack('de')]);
    });

    test('reads a locale once', () async {
      final first = await loader.keywordPack('de');
      final second = await loader.keywordPack('de');

      expect(second, same(first));
      expect(assets.requested, hasLength(1));
    });

    test(
      'fails when the pack cannot be read, and reads it again later',
      () async {
        assets.failure = Exception('offline');
        await expectLater(loader.keywordPack('de'), throwsException);

        assets.failure = null;

        expect((await loader.keywordPack('de')).locale, 'de');
      },
    );
  });

  test('loads the shipped assets', () async {
    final real = EmojiCatalogLoader(readShippedAsset);

    final structure = await real.structure();
    final pack = await real.keywordPack('en');

    expect(structure.entries, isNotEmpty);
    expect(pack.records, isNotEmpty);
  });
}
