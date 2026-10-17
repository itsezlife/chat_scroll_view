/// The code a panel shows as a hint for an emoji (`:grinning:`): the bundled
/// shortcode of the emoji, the same in every language.
///
/// **Seam:** `EmojiCollectionSource` and `EmojiSearchSource` built with
/// `shortcodes`, observed through the `shortcode` of the descriptors they
/// publish. First over a small hand-made table, then over the shipped one.
library;

import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

import '../support/pack_assets.dart';
import '../support/synthetic_catalog.dart';

final _table = EmojiShortcodes(
  source: 'test',
  codes: {
    key('1F600'): ':grinning:',
    key('1F44D'): ':thumbsup:',
    key('1F9D1-200D-1F4BB'): ':technologist:',
    key('1F469-200D-1F4BB'): ':woman_technologist:',
  },
);

// The faces and the toned hand of the sample, and a technologist whose woman
// form has a tone of her own.
EmojiCatalog _catalog() => catalogOf({
  'faces': [plain('1F600'), plain('1F603')],
  'things': [toned('1F44D')],
  'people': [
    EmojiEntry(
      base: key('1F9D1-200D-1F4BB'),
      variants: [
        EmojiVariant(
          key('1F9D1-1F3FB-200D-1F4BB'),
          EmojiModifiers(tones: const [SkinTone.light]),
        ),
        EmojiVariant(
          key('1F469-200D-1F4BB'),
          EmojiModifiers(genders: const [EmojiGender.woman]),
        ),
        EmojiVariant(
          key('1F469-1F3FB-200D-1F4BB'),
          EmojiModifiers(
            tones: const [SkinTone.light],
            genders: const [EmojiGender.woman],
          ),
        ),
      ],
    ),
  ],
});

KeywordPack _english() => KeywordPack(
  language: 'en',
  version: 0,
  keywords: {
    key('1F600'): const ['grinning face', 'grin'],
    key('1F44D'): const ['thumbs up', 'like'],
  },
);

String? _code(CollectionItem item) => item.descriptor?.shortcode;

void main() {
  late FakeRecentsStore recents;
  late FakePreferenceStore preferences;
  late int reads;
  late Future<EmojiShortcodes> Function() shortcodes;

  setUp(() {
    recents = FakeRecentsStore();
    preferences = FakePreferenceStore();
    reads = 0;
    shortcodes = () async {
      reads++;
      return _table;
    };
  });

  EmojiCollectionSource collections({KeywordSource? keywords}) =>
      EmojiCollectionSource(
        catalog: _catalog(),
        recents: recents,
        preferences: preferences,
        keywords: keywords,
        languages: keywords == null ? const [] : const ['en'],
        shortcodes: () => shortcodes(),
      );

  List<CollectionItem> itemsOf(EmojiCollectionSource source, CollectionId id) =>
      (source.collections.value.firstWhere((c) => c.id == id).contents
              as CollectionContents$Loaded)
          .items;

  Future<List<CollectionItem>> loaded(
    EmojiCollectionSource source,
    String category,
  ) async {
    final id = CollectionId.category(category);
    await source.load(id);
    return itemsOf(source, id);
  }

  group('a category', () {
    test('gives each emoji its code', () async {
      final emoji = collections();
      addTearDown(emoji.dispose);

      expect(_code((await loaded(emoji, 'faces')).first), ':grinning:');
    });

    test('gives an emoji the table has no code for none', () async {
      final emoji = collections();
      addTearDown(emoji.dispose);

      expect(_code((await loaded(emoji, 'faces'))[1]), isNull);
    });

    test("gives a tone variant its emoji's code", () async {
      await preferences.setPreferredVariant(key('1F44D'), key('1F44D-1F3FF'));
      final emoji = collections();
      addTearDown(emoji.dispose);

      final item = (await loaded(emoji, 'things')).single;
      expect(item.key, key('1F44D-1F3FF'));
      expect(_code(item), ':thumbsup:');
    });

    test('gives a gender form its own code, in every tone', () async {
      await preferences.setPreferredVariant(
        key('1F469-200D-1F4BB'),
        key('1F469-1F3FB-200D-1F4BB'),
      );
      final emoji = collections();
      addTearDown(emoji.dispose);

      final items = await loaded(emoji, 'people');
      expect(
        [for (final item in items) item.key],
        [key('1F9D1-200D-1F4BB'), key('1F469-1F3FB-200D-1F4BB')],
      );
      expect(
        [for (final item in items) _code(item)],
        [':technologist:', ':woman_technologist:'],
      );
    });

    test('carries the code next to the spoken name', () async {
      final emoji = collections(keywords: FakeKeywordSource([_english()]));
      addTearDown(emoji.dispose);

      final item = (await loaded(emoji, 'faces')).first;
      expect(item.descriptor?.spokenName, 'grinning face');
      expect(_code(item), ':grinning:');
    });

    test('reads the shortcodes once for every collection', () async {
      final emoji = collections();
      addTearDown(emoji.dispose);

      await loaded(emoji, 'faces');
      await loaded(emoji, 'things');
      await emoji.load(CollectionId.recent);

      expect(reads, 1);
    });

    test('shortcodes that cannot be read leave the codes off, report, and '
        'still load', () async {
      shortcodes = () async => throw Exception('unreadable');
      final emoji = collections(keywords: FakeKeywordSource([_english()]));
      addTearDown(emoji.dispose);
      final reported = <Object>[];

      final items = await runZonedGuarded(
        () => loaded(emoji, 'faces'),
        (error, stack) => reported.add(error),
      );

      expect(reported, [isA<Exception>()]);
      expect(items, hasLength(2));
      expect(_code(items!.first), isNull);
      expect(items.first.descriptor?.spokenName, 'grinning face');
    });

    test('has no codes without shortcodes', () async {
      final emoji = EmojiCollectionSource(
        catalog: _catalog(),
        recents: recents,
        preferences: preferences,
      );
      addTearDown(emoji.dispose);

      expect(_code((await loaded(emoji, 'faces')).first), isNull);
    });
  });

  group('recents', () {
    test("give a tone variant its emoji's code, like the grid", () async {
      await recents.record(key('1F44D-1F3FB'), kind: SemanticKind.unicodeEmoji);
      final emoji = collections();
      addTearDown(emoji.dispose);
      await emoji.load(CollectionId.recent);

      expect(_code(itemsOf(emoji, CollectionId.recent).single), ':thumbsup:');
    });
  });

  group('search results', () {
    EmojiSearchSource search() => EmojiSearchSource(
      catalog: _catalog(),
      keywords: FakeKeywordSource([_english()]),
      languages: const ['en'],
      recents: recents,
      preferences: preferences,
      shortcodes: () => shortcodes(),
    );

    List<CollectionItem> found(EmojiSearchSource source) =>
        (source.results.value.contents as CollectionContents$Loaded).items;

    test('carry the code of the variant the grid shows', () async {
      await preferences.setPreferredVariant(key('1F44D'), key('1F44D-1F3FF'));
      final source = search();
      addTearDown(source.dispose);

      await source.search('like');

      expect(found(source).single.key, key('1F44D-1F3FF'));
      expect(_code(found(source).single), ':thumbsup:');
    });

    test('read the shortcodes once for every query', () async {
      final source = search();
      addTearDown(source.dispose);

      await source.search('grin');
      await source.search('like');

      expect(_code(found(source).single), ':thumbsup:');
      expect(reads, 1);
    });

    test('shortcodes that cannot be read leave the codes off, report, and '
        'still answer', () async {
      shortcodes = () async => throw Exception('unreadable');
      final source = search();
      addTearDown(source.dispose);
      final reported = <Object>[];

      await runZonedGuarded(
        () => source.search('grin'),
        (error, stack) => reported.add(error),
      );

      expect(reported, [isA<Exception>()]);
      expect(found(source).single.key, key('1F600'));
      expect(_code(found(source).single), isNull);
    });
  });

  group('the shipped shortcodes', () {
    late EmojiCatalogLoader loader;
    late EmojiCatalog catalog;

    setUpAll(() async {
      loader = EmojiCatalogLoader(readShippedAsset);
      catalog = EmojiCatalog(await loader.structure());
    });

    Future<String?> codeShown(ContentKey$Unicode of) async {
      final emoji = EmojiCollectionSource(
        catalog: catalog,
        recents: recents,
        preferences: preferences,
        shortcodes: loader.shortcodes,
      );
      addTearDown(emoji.dispose);
      for (final collection in emoji.collections.value.skip(1)) {
        await emoji.load(collection.id);
        for (final item in itemsOf(emoji, collection.id)) {
          if (item.key == of) return _code(item);
        }
      }
      fail('$of is not shown');
    }

    test('give the grinning face the code the desktop client shows', () async {
      expect(await codeShown(key('1F600')), ':grinning:');
    });

    test('give a toned woman technologist her own toneless code', () async {
      await preferences.setPreferredVariant(
        key('1F469-200D-1F4BB'),
        key('1F469-1F3FD-200D-1F4BB'),
      );

      expect(
        await codeShown(key('1F469-1F3FD-200D-1F4BB')),
        ':woman_technologist:',
      );
    });
  });
}
