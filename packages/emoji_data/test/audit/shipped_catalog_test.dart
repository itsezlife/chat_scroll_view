/// The shipped catalogue seen through the sources a page composes: the audit
/// gaps of the old data layer (variants flagged but unusable, flags not
/// findable by country, glyphs listed in several categories) as tests on the
/// real assets.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

import '../support/pack_assets.dart';
import '../support/synthetic_catalog.dart';

void main() {
  late EmojiCatalogLoader loader;
  late EmojiCatalog catalog;
  late FakeRecentsStore recents;
  late FakePreferenceStore preferences;

  setUpAll(() async {
    loader = EmojiCatalogLoader(readShippedAsset);
    catalog = EmojiCatalog(await loader.structure());
  });

  setUp(() {
    recents = FakeRecentsStore();
    preferences = FakePreferenceStore();
  });

  EmojiCollectionSource collections() => EmojiCollectionSource(
    catalog: catalog,
    recents: recents,
    preferences: preferences,
  );

  EmojiSearchSource search({
    KeywordSource? keywords,
    List<String> languages = const ['en'],
  }) => EmojiSearchSource(
    catalog: catalog,
    keywords: keywords ?? BundledKeywordSource(loader),
    languages: languages,
    recents: recents,
    preferences: preferences,
  );

  Future<List<ContentKey>> found(EmojiSearchSource source, String query) async {
    await source.search(query);
    return [
      for (final item
          in (source.results.value.contents as CollectionContents$Loaded).items)
        item.key,
    ];
  }

  group('variants (picker and grid agree)', () {
    test('every key of an entry resolves to that entry', () {
      for (final entry in catalog.entries) {
        expect(catalog.entryOf(entry.base), same(entry));
        for (final variant in entry.variants) {
          expect(catalog.entryOf(variant.key), same(entry));
        }
      }
    });

    test('the entries the old tone table missed have tone variants', () {
      for (final hex in [
        '1FAF6', // 🫶
        '1F590-FE0F', // 🖐️
        '270C-FE0F', // ✌️
        '261D-FE0F', // ☝️
        '270D-FE0F', // ✍️
      ]) {
        final entry = catalog.entryOf(ContentKey.parse('unicode:$hex'));
        expect(entry?.hasToneVariants, isTrue, reason: hex);
      }
    });

    test(
      'a chosen tone is what the grid shows, for every tone entry',
      () async {
        final toned = [
          for (final entry in catalog.entries)
            if (entry.hasToneVariants) entry,
        ];
        expect(toned.length, greaterThan(150));
        final source = collections();
        addTearDown(source.dispose);
        for (final entry in toned) {
          final last = entry.variants.lastWhere(
            (variant) => variant.modifiers.tones.isNotEmpty,
          );
          await source.chooseVariant(entry, last.key);
        }
        for (final collection in source.collections.value) {
          await source.load(collection.id);
        }

        final shown = {
          for (final collection in source.collections.value)
            if (collection.contents case final CollectionContents$Loaded loaded)
              for (final item in loaded.items) item.key,
        };
        for (final entry in toned) {
          expect(shown, contains(source.shownKeyOf(entry)));
          expect(shown, isNot(contains(entry.base)), reason: '${entry.base}');
        }
      },
    );
  });

  group('categories', () {
    test('hold each entry in exactly one category', () async {
      final source = collections();
      addTearDown(source.dispose);
      for (final collection in source.collections.value) {
        await source.load(collection.id);
      }

      final keys = [
        for (final collection in source.collections.value)
          if (collection.id != CollectionId.recent)
            for (final item
                in (collection.contents as CollectionContents$Loaded).items)
              item.key,
      ];

      expect(keys.toSet(), hasLength(keys.length));
      expect(keys, hasLength(catalog.entries.length));
    });
  });

  group('the reference sections', () {
    test('cover every entry of the shipped catalogue exactly once', () async {
      final source = collections();
      addTearDown(source.dispose);
      final ids = [
        for (final c in source.collections.value)
          if (c.id case CollectionId$Category(:final id)) id,
      ];
      expect(ids, [
        'people',
        'nature',
        'food',
        'activity',
        'travel',
        'objects',
        'symbols',
      ]);

      var shown = 0;
      for (final id in ids) {
        await source.load(CollectionId.category(id));
      }
      for (final c in source.collections.value) {
        if (c.contents case CollectionContents$Loaded(:final items)) {
          shown += items.length;
        }
      }

      expect(shown, catalog.entries.length);
    });
  });

  group('search', () {
    test('only ever lists what the grid shows, whatever the query', () async {
      // A query that is one letter matches the keywords of many variants (a
      // tone, a gender); the page bakes only what the grid shows, so a result
      // of its own for a variant would be drawn as a circle.
      final grid = {for (final entry in catalog.entries) entry.base};
      for (final query in ['g', 'man', 'woman', 'person', 'hand']) {
        final keys = await found(search(), query);

        expect(keys, isNotEmpty, reason: query);
        for (final key in keys) {
          expect(grid, contains(key), reason: '$query: $key is a variant');
        }
      }
    });

    test('finds a flag by its country name, in each language', () async {
      final source = search(languages: const ['en', 'de', 'ru']);
      addTearDown(source.dispose);

      expect(await found(source, 'uzbekistan'), [key('1F1FA-1F1FF')]);
      expect(await found(source, 'Usbekistan'), [key('1F1FA-1F1FF')]);
      expect(await found(source, 'узбекистан'), [key('1F1FA-1F1FF')]);
    });

    test(
      'finds a flag by the country in another language only when asked',
      () async {
        final source = search();
        addTearDown(source.dispose);

        expect(await found(source, 'usbekistan'), isEmpty);
      },
    );

    test(
      'answers from the bundled pack alone, reading only that pack',
      () async {
        final reads = <String>[];
        final bundled = BundledKeywordSource(
          EmojiCatalogLoader((assetKey) {
            reads.add(assetKey);
            return readShippedAsset(assetKey);
          }),
        );
        final source = search(keywords: bundled);
        addTearDown(source.dispose);

        final results = await found(source, 'thumbs up');

        expect(results, contains(key('1F44D')));
        expect(reads, hasLength(1));
        expect(reads.single, endsWith('keywords/en.tsv'));
      },
    );

    test('lets a host pack replace and extend the bundled keywords', () async {
      final host = FakeKeywordSource();
      final source = search(
        keywords: LayeredKeywordSource(
          base: BundledKeywordSource(loader),
          overlay: host,
        ),
      );
      addTearDown(source.dispose);
      expect(await found(source, 'zzzword'), isEmpty);
      expect(await found(source, 'thumbs up'), contains(key('1F44D')));

      host.publish(
        KeywordPack(
          language: 'en',
          version: 5,
          keywords: {
            key('1F44D'): const ['zzzword'],
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // The open query ran again over the host's keywords.
      expect(await found(source, 'zzzword'), [key('1F44D')]);
      // The host's list replaced the bundled one for that key only.
      expect(await found(source, 'thumbs up'), isNot(contains(key('1F44D'))));
      expect(await found(source, 'grinning face'), contains(key('1F600')));
    });

    test('shows the chosen tone of a hit', () async {
      final source = search();
      addTearDown(source.dispose);
      await preferences.setPreferredVariant(key('1F44D'), key('1F44D-1F3FD'));

      expect(await found(source, 'thumbs up'), contains(key('1F44D-1F3FD')));
    });
  });
}
