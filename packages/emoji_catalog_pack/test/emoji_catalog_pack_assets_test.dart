import 'dart:io';
import 'dart:isolate';

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

    test('keys the shortcodes by their package asset path', () {
      expect(
        EmojiCatalogPackAssets.shortcodes,
        'packages/emoji_catalog_pack/assets/shortcodes.tsv',
      );
    });

    test('keys a keyword pack by its locale', () {
      expect(
        EmojiCatalogPackAssets.keywordPack('de'),
        'packages/emoji_catalog_pack/assets/keywords/de.tsv',
      );
    });

    test('lists exactly the locales that have a shipped pack', () async {
      final library = await Isolate.resolvePackageUri(
        Uri.parse('package:emoji_catalog_pack/emoji_catalog_pack.dart'),
      );
      final keywords = Directory.fromUri(
        library!.resolve('../assets/keywords/'),
      );

      final shipped = [
        for (final file in keywords.listSync().whereType<File>())
          file.uri.pathSegments.last.replaceAll('.tsv', ''),
      ]..sort();

      expect([...EmojiCatalogPackAssets.locales]..sort(), shipped);
    });

    test('refuses a locale id that could leave the keywords directory', () {
      expect(
        () => EmojiCatalogPackAssets.keywordPack('../structure'),
        throwsArgumentError,
      );
    });
  });
}
