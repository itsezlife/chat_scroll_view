import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DefaultEmojiDataSource', () {
    late DefaultEmojiDataSource source;

    setUp(() async {
      source = DefaultEmojiDataSource(
        catalog: LocaleEmojiCatalogProvider(filterUnsupported: false),
        recentsStore: MemoryEmojiRecentsStore(),
        skinTonePrefs: MemorySkinTonePrefs(),
      );
      await source.load();
    });

    tearDown(() => source.dispose());

    test('load populates categories and notifies', () async {
      expect(source.isReady, isTrue);
      expect(source.categories, isNotEmpty);
      expect(source.categories.first.items, isNotEmpty);
    });

    test('search returns keyword hits', () async {
      final hits = await source.search('cat');
      expect(hits, isNotEmpty);
      expect(hits.first, isA<UnicodeEmojiItem>());
    });

    test('empty search returns no hits', () async {
      final hits = await source.search('   ');
      expect(hits, isEmpty);
    });

    test('recordPick notifies listeners when recents change', () async {
      var notifyCount = 0;
      source.addDataListener(() => notifyCount++);

      await source.recordPick(
        const UnicodeEmojiItem(glyph: '😀', keywords: <String>[], supportsSkinTone: false),
        source: EmojiPickSource.grid,
      );
      expect(notifyCount, 1);
      expect(source.recentGlyphs, ['😀']);

      await source.recordPick(
        const UnicodeEmojiItem(glyph: '🎉', keywords: <String>[], supportsSkinTone: false),
        source: EmojiPickSource.search,
      );
      expect(notifyCount, 1);
      expect(source.recentGlyphs, ['😀']);
    });

    test('clearRecents notifies listeners', () async {
      await source.recordPick(
        const UnicodeEmojiItem(glyph: '😀', keywords: <String>[], supportsSkinTone: false),
        source: EmojiPickSource.grid,
      );
      var notifyCount = 0;
      source.addDataListener(() => notifyCount++);

      await source.clearRecents();
      expect(notifyCount, 1);
      expect(source.recentGlyphs, isEmpty);
    });

    test('setSkinTone notifies listeners', () async {
      var notifyCount = 0;
      source.addDataListener(() => notifyCount++);

      await source.setSkinTone('👍', 3);
      expect(notifyCount, 1);
      expect(source.skinToneFor('👍'), 3);
    });

    test('swapCatalog replaces provider and updates search index', () async {
      expect(source.categories.first.title, 'Smileys');

      var notifyCount = 0;
      source.addDataListener(() => notifyCount++);

      final next = LocaleEmojiCatalogProvider(
        locale: const Locale('ru'),
        filterUnsupported: false,
      );
      await source.swapCatalog(next);

      expect(notifyCount, 1);
      expect(source.categories.first.title, 'Смайлы');

      final hits = await source.search('кот');
      expect(hits, isNotEmpty);
    });
  });
}
