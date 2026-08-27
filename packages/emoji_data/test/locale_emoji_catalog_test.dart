import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocaleEmojiCatalogProvider', () {
    test('russian locale loads localized keywords and section titles', () async {
      final provider = LocaleEmojiCatalogProvider(
        locale: const Locale('ru'),
        filterUnsupported: false,
      );
      final categories = await provider.loadCategories();

      expect(categories, isNotEmpty);
      expect(categories.first.title, 'Смайлы');

      final allItems = categories
          .expand((c) => c.items)
          .whereType<UnicodeEmojiItem>()
          .toList(growable: false);
      final hits = EmojiCatalogSearch.search('кот', allItems);
      expect(hits, isNotEmpty);
      expect(hits.first, isA<UnicodeEmojiItem>());
    });

    test('unsupported locale falls back to english catalog', () async {
      final provider = LocaleEmojiCatalogProvider(
        locale: const Locale('xx'),
        filterUnsupported: false,
      );
      final categories = await provider.loadCategories();

      expect(categories.first.title, 'Smileys');

      final allItems = categories
          .expand((c) => c.items)
          .whereType<UnicodeEmojiItem>()
          .toList(growable: false);
      final hits = EmojiCatalogSearch.search('cat', allItems);
      expect(hits, isNotEmpty);
    });

    test('supportedEmojiCatalogLocales lists all bundled locales', () {
      expect(
        supportedEmojiCatalogLocales,
        containsAll(<String>['de', 'en', 'es', 'fr', 'hi', 'it', 'ja', 'nl', 'pt', 'ru', 'zh']),
      );
    });
  });
}
