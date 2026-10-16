/// What a screen reader says for an emoji the sources publish: the spoken name
/// of the bundled keyword pack of the active language.
///
/// **Seam:** `EmojiCollectionSource` and `EmojiSearchSource` built with a
/// `KeywordSource`, observed through the `spokenName` of the descriptors they
/// publish. First over small hand-made packs, then over the shipped English and
/// Russian ones.
library;

import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

import '../support/pack_assets.dart';
import '../support/synthetic_catalog.dart';

KeywordPack _pack(String language, Map<String, List<String>> keywords) =>
    KeywordPack(
      language: language,
      version: 0,
      keywords: {for (final e in keywords.entries) key(e.key): e.value},
    );

final _english = _pack('en', {
  '1F600': ['grinning face', 'grin'],
  '1F44D': ['thumbs up', 'like'],
});
final _russian = _pack('ru', {
  '1F600': ['широко улыбается', 'улыбка'],
  '1F44D': ['большой палец вверх', 'лайк'],
});

String? _spoken(CollectionItem item) => item.descriptor?.spokenName;

void main() {
  late FakeRecentsStore recents;
  late FakePreferenceStore preferences;
  late FakeKeywordSource keywords;

  setUp(() {
    recents = FakeRecentsStore();
    preferences = FakePreferenceStore();
    keywords = FakeKeywordSource([_english, _russian]);
  });

  EmojiCollectionSource collections(List<String> languages) =>
      EmojiCollectionSource(
        catalog: sampleCatalog(),
        recents: recents,
        preferences: preferences,
        keywords: keywords,
        languages: languages,
      );

  List<CollectionItem> itemsOf(EmojiCollectionSource source, String group) =>
      (source.collections.value
                  .firstWhere((c) => c.id == CollectionId.category(group))
                  .contents
              as CollectionContents$Loaded)
          .items;

  group('a category', () {
    test('names each emoji in the active language', () async {
      final emoji = collections(['en']);
      addTearDown(emoji.dispose);
      await emoji.load(const CollectionId.category('faces'));

      expect(_spoken(itemsOf(emoji, 'faces').first), 'grinning face');
    });

    test(
      'names it in a non-Latin language when that is the active one',
      () async {
        final emoji = collections(['ru']);
        addTearDown(emoji.dispose);
        await emoji.load(const CollectionId.category('things'));

        expect(_spoken(itemsOf(emoji, 'things').first), 'большой палец вверх');
      },
    );

    test(
      'falls back to the next language for an emoji the first lacks',
      () async {
        keywords = FakeKeywordSource([
          _pack('ru', {
            '1F44D': ['большой палец вверх'],
          }),
          _english,
        ]);
        final emoji = collections(['ru', 'en']);
        addTearDown(emoji.dispose);
        await emoji.load(const CollectionId.category('faces'));

        expect(_spoken(itemsOf(emoji, 'faces').first), 'grinning face');
      },
    );

    test('a tone variant is named as its emoji', () async {
      await preferences.setPreferredVariant(key('1F44D'), key('1F44D-1F3FF'));
      final emoji = collections(['en']);
      addTearDown(emoji.dispose);
      await emoji.load(const CollectionId.category('things'));

      final item = itemsOf(emoji, 'things').first;
      expect(item.key, key('1F44D-1F3FF'));
      expect(_spoken(item), 'thumbs up');
    });

    test('an emoji no pack names has no spoken name, never a guess', () async {
      final emoji = collections(['en']);
      addTearDown(emoji.dispose);
      await emoji.load(const CollectionId.category('faces'));

      expect(_spoken(itemsOf(emoji, 'faces')[1]), isNull);
    });

    test('a language with no pack leaves the names off', () async {
      final emoji = collections(['xx']);
      addTearDown(emoji.dispose);
      await emoji.load(const CollectionId.category('faces'));

      expect(_spoken(itemsOf(emoji, 'faces').first), isNull);
    });

    test('a pack that cannot be read leaves the names off, reports, and '
        'still loads', () async {
      keywords.failure = Exception('unreadable');
      final emoji = collections(['en']);
      addTearDown(emoji.dispose);
      final reported = <Object>[];

      await runZonedGuarded(
        () => emoji.load(const CollectionId.category('faces')),
        (error, stack) => reported.add(error),
      );

      expect(reported, [isA<Exception>()]);
      expect(itemsOf(emoji, 'faces'), hasLength(5));
      expect(_spoken(itemsOf(emoji, 'faces').first), isNull);
    });

    test('follows a newer pack when one arrives', () async {
      final emoji = collections(['en']);
      addTearDown(emoji.dispose);
      await emoji.load(const CollectionId.category('faces'));

      keywords.publish(
        _pack('en', {
          '1F600': ['beaming face'],
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(_spoken(itemsOf(emoji, 'faces').first), 'beaming face');
    });
  });

  group('recents', () {
    test('are named like the grid', () async {
      await recents.record(key('1F600'), kind: SemanticKind.unicodeEmoji);
      final emoji = collections(['ru']);
      addTearDown(emoji.dispose);
      await emoji.load(CollectionId.recent);

      final loaded =
          emoji.collections.value
                  .firstWhere((c) => c.id == CollectionId.recent)
                  .contents
              as CollectionContents$Loaded;
      expect(_spoken(loaded.items.single), 'широко улыбается');
    });
  });

  group('search results', () {
    test('are named in the first language that names them', () async {
      final search = EmojiSearchSource(
        catalog: sampleCatalog(),
        keywords: keywords,
        languages: const ['ru', 'en'],
        recents: recents,
        preferences: preferences,
      );
      addTearDown(search.dispose);

      await search.search('like');

      final loaded = search.results.value.contents as CollectionContents$Loaded;
      expect(loaded.items.map((i) => i.key), [key('1F44D')]);
      expect(_spoken(loaded.items.single), 'большой палец вверх');
    });
  });

  group('the shipped packs', () {
    late EmojiCatalogLoader loader;
    late EmojiCatalog catalog;

    setUpAll(() async {
      loader = EmojiCatalogLoader(readShippedAsset);
      catalog = EmojiCatalog(await loader.structure());
    });

    Future<String?> firstSpoken(String language, ContentKey$Unicode of) async {
      final emoji = EmojiCollectionSource(
        catalog: catalog,
        recents: recents,
        preferences: preferences,
        keywords: BundledKeywordSource(loader),
        languages: [language],
      );
      addTearDown(emoji.dispose);
      final group = catalog.structure.groups.first.id;
      await emoji.load(CollectionId.category(group));
      final items =
          (emoji.collections.value
                      .firstWhere((c) => c.id == CollectionId.category(group))
                      .contents
                  as CollectionContents$Loaded)
              .items;
      return _spoken(items.firstWhere((item) => item.key == of));
    }

    test('English reads the CLDR name', () async {
      expect(await firstSpoken('en', key('1F600')), 'grinning face');
    });

    test('Russian reads the CLDR name, not the glyph', () async {
      expect(await firstSpoken('ru', key('1F600')), 'широко улыбается');
    });
  });
}
