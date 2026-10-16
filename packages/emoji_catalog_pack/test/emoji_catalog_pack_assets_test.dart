import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:test/test.dart';

void main() {
  group('EmojiCatalogPackAssets', () {
    test('keys the structure by its package asset path', () {
      expect(
        EmojiCatalogPackAssets.structure,
        'packages/emoji_catalog_pack/assets/structure.tsv',
      );
    });

    test('keys a keyword pack by its locale', () {
      expect(
        EmojiCatalogPackAssets.keywordPack('de'),
        'packages/emoji_catalog_pack/assets/keywords/de.tsv',
      );
    });

    test('refuses a locale id that could leave the keywords directory', () {
      expect(
        () => EmojiCatalogPackAssets.keywordPack('../structure'),
        throwsArgumentError,
      );
    });
  });
}
