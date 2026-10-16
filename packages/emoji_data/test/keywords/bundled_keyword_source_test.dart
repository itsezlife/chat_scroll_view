import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:emoji_data/testing.dart';
import 'package:test/test.dart';

import '../support/pack_assets.dart';

String _pack(String locale, String records) =>
    '@emoji-catalog-keywords\t1\n'
    '@locale\t$locale\n'
    '@cldr\t49\n'
    '$records';

ContentKey$Unicode _key(String hex) =>
    ContentKey.parse('unicode:$hex') as ContentKey$Unicode;

void main() {
  late FakeEmojiAssetLoader assets;

  BundledKeywordSource source({List<String>? languages}) =>
      BundledKeywordSource(
        EmojiCatalogLoader(assets.load),
        languages: languages ?? const ['en', 'pt'],
      );

  setUp(() {
    assets = FakeEmojiAssetLoader({
      EmojiCatalogPackAssets.keywordPack('en'): _pack(
        'en',
        '1F600\tGrinning Face\tHappy|smile\n',
      ),
      EmojiCatalogPackAssets.keywordPack('pt'): _pack(
        'pt',
        '1F600\trosto sorridente\tfeliz\n',
      ),
    });
  });

  runKeywordSourceContract(
    () async => KeywordSourceHarness(
      source: source(),
      language: 'en',
      unknownLanguage: 'xx',
    ),
  );

  group('pack', () {
    test(
      'writes the spoken name first, then the keywords, lower-cased',
      () async {
        final pack = await source().pack('en');

        expect(pack!.keywords, {
          _key('1F600'): ['grinning face', 'happy', 'smile'],
        });
      },
    );

    test('is the baseline: version 0', () async {
      expect((await source().pack('en'))!.version, 0);
    });

    test('answers the same pack for the same language', () async {
      final bundled = source();

      expect(await bundled.pack('en'), same(await bundled.pack('en')));
      expect(assets.requested, hasLength(1));
    });

    test('reads nothing until a language is asked for', () async {
      final bundled = source();

      expect(assets.requested, isEmpty);
      await bundled.pack('pt');
      expect(assets.requested, [EmojiCatalogPackAssets.keywordPack('pt')]);
    });

    test(
      'reads a regional tag as its primary subtag, either separator',
      () async {
        expect((await source().pack('pt-BR'))!.language, 'pt');
        expect((await source().pack('pt_BR'))!.language, 'pt');
        expect((await source().pack('PT'))!.language, 'pt');
      },
    );

    test('knows no pack for a language it was not told it has', () async {
      expect(await source(languages: const ['en']).pack('pt'), isNull);
      expect(assets.requested, isEmpty);
    });

    test('fails when a pack it has cannot be read, then recovers', () async {
      final bundled = source();
      assets.failure = Exception('offline');
      await expectLater(bundled.pack('en'), throwsException);

      assets.failure = null;

      expect(await bundled.pack('en'), isNotNull);
    });
  });

  test('ships a pack for every language it lists by default', () async {
    final bundled = BundledKeywordSource(EmojiCatalogLoader(readShippedAsset));

    for (final language in EmojiCatalogPackAssets.locales) {
      final pack = await bundled.pack(language);
      expect(pack, isNotNull, reason: language);
      expect(pack!.keywords, isNotEmpty, reason: language);
    }
  });
}
