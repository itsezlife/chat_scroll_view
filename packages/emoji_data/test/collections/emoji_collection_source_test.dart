import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

import '../support/synthetic_catalog.dart';

void main() {
  late FakeRecentsStore recents;
  late FakePreferenceStore preferences;
  late FakeGlyphSupport glyphs;

  setUp(() {
    recents = FakeRecentsStore();
    preferences = FakePreferenceStore();
    glyphs = FakeGlyphSupport();
  });

  EmojiCollectionSource source({int? pageSize, bool withGlyphs = true}) =>
      EmojiCollectionSource(
        catalog: sampleCatalog(),
        recents: recents,
        preferences: preferences,
        glyphSupport: withGlyphs ? glyphs : null,
        pageSize: pageSize,
      );

  runCollectionSourceContract(
    () async => CollectionSourceHarness(
      source: source(pageSize: 2),
      pagedId: const CollectionId.category('faces'),
      missingId: const CollectionId.category('nope'),
    ),
  );

  group('collections', () {
    test('lists recents first, then one category per group, untitled', () {
      final listed = source().collections.value;

      expect(
        [for (final c in listed) c.id],
        [
          CollectionId.recent,
          const CollectionId.category('faces'),
          const CollectionId.category('things'),
        ],
      );
      expect([
        for (final c in listed) c.metadata,
      ], everyElement(CollectionMetadata.empty));
      expect([
        for (final c in listed) c.contents,
      ], everyElement(CollectionContents.idle));
    });
  });

  group('a category', () {
    late EmojiCollectionSource emoji;

    setUp(() => emoji = source());
    tearDown(() => emoji.dispose());

    CollectionContents$Loaded contents(String id) =>
        emoji.collections.value
                .firstWhere((c) => c.id == CollectionId.category(id))
                .contents
            as CollectionContents$Loaded;

    test('holds the base key of each entry, in palette order', () async {
      await emoji.load(const CollectionId.category('things'));

      expect(
        [for (final item in contents('things').items) item.key],
        [key('1F44D'), key('2764-FE0F')],
      );
    });

    test('describes each item as a unicode emoji drawn as a glyph', () async {
      await emoji.load(const CollectionId.category('faces'));

      expect(
        contents('faces').items.first,
        CollectionItem.described(
          ContentDescriptor(
            key: key('1F600'),
            semanticKind: SemanticKind.unicodeEmoji,
            mediaForm: MediaForm.glyph,
          ),
        ),
      );
    });

    test('is one page without a token unless a page size was set', () async {
      await emoji.load(const CollectionId.category('faces'));

      expect(contents('faces').items, hasLength(5));
      expect(contents('faces').nextPageToken, isNull);
    });

    test('pages by the page size and ends on the last page', () async {
      final paged = source(pageSize: 2);
      addTearDown(paged.dispose);
      const faces = CollectionId.category('faces');

      await paged.load(faces);
      await paged.loadMore(faces);
      await paged.loadMore(faces);

      final loaded =
          paged.collections.value.firstWhere((c) => c.id == faces).contents
              as CollectionContents$Loaded;
      expect(loaded.items, hasLength(5));
      expect(loaded.nextPageToken, isNull);
    });
  });

  group('variants', () {
    late EmojiCollectionSource emoji;
    const things = CollectionId.category('things');

    setUp(() => emoji = source());
    tearDown(() => emoji.dispose());

    ContentKey firstThing() =>
        (emoji.collections.value.firstWhere((c) => c.id == things).contents
                as CollectionContents$Loaded)
            .items
            .first
            .key;

    test('shows the variant the user chose for a base', () async {
      await preferences.setPreferredVariant(key('1F44D'), key('1F44D-1F3FF'));

      await emoji.load(things);

      expect(firstThing(), key('1F44D-1F3FF'));
    });

    test('shows the base when the stored choice is no variant of it', () async {
      await preferences.setPreferredVariant(key('1F44D'), key('1F44E-1F3FB'));

      await emoji.load(things);

      expect(firstThing(), key('1F44D'));
    });

    test('republishes once when a choice changes a loaded category', () async {
      await emoji.load(things);
      var publications = 0;
      emoji.collections.addListener(() => publications++);

      await emoji.chooseVariant(toned('1F44D'), key('1F44D-1F3FB'));

      expect(publications, 1);
      expect(firstThing(), key('1F44D-1F3FB'));
    });

    test('stays silent when a choice changes nothing that is loaded', () async {
      var publications = 0;
      emoji.collections.addListener(() => publications++);

      await emoji.chooseVariant(toned('1F44D'), key('1F44D-1F3FB'));

      expect(publications, 0);
    });

    test('remembers the base as the choice when it is chosen itself', () async {
      await emoji.chooseVariant(toned('1F44D'), key('1F44D-1F3FB'));

      await emoji.chooseVariant(toned('1F44D'), key('1F44D'));

      expect(preferences.preferredVariant(key('1F44D')), key('1F44D'));
      expect(emoji.shownKeyOf(toned('1F44D')), key('1F44D'));
    });

    test('refuses a key that is not a variant of the entry', () {
      expect(
        () => emoji.chooseVariant(toned('1F44D'), key('1F44E-1F3FB')),
        throwsArgumentError,
      );
    });

    test('answers the entry of a base or of a shown variant', () {
      expect(emoji.entryOf(key('1F44D-1F3FB'))?.base, key('1F44D'));
      expect(emoji.entryOf(key('1F44D'))?.hasToneVariants, isTrue);
      expect(emoji.entryOf(key('2764-FE0F'))?.hasToneVariants, isFalse);
      expect(emoji.entryOf(key('1F4A9')), isNull);
    });

    test('answers the key shown for an entry', () async {
      expect(emoji.shownKeyOf(toned('1F44D')), key('1F44D'));

      await emoji.chooseVariant(toned('1F44D'), key('1F44D-1F3FF'));

      expect(emoji.shownKeyOf(toned('1F44D')), key('1F44D-1F3FF'));
    });
  });

  group('recents', () {
    late EmojiCollectionSource emoji;

    setUp(() => emoji = source());
    tearDown(() => emoji.dispose());

    List<ContentKey> recentKeys() =>
        (emoji.collections.value.first.contents as CollectionContents$Loaded)
            .items
            .map((item) => item.key)
            .toList();

    test('loads empty when nothing was picked', () async {
      await emoji.load(CollectionId.recent);

      expect(recentKeys(), isEmpty);
    });

    test('lists what the store holds, best first, as picked', () async {
      await recents.record(key('1F44D-1F3FF'), kind: SemanticKind.unicodeEmoji);
      await recents.record(key('1F600'), kind: SemanticKind.unicodeEmoji);
      await recents.record(key('1F600'), kind: SemanticKind.unicodeEmoji);

      await emoji.load(CollectionId.recent);

      expect(recentKeys(), [key('1F600'), key('1F44D-1F3FF')]);
    });

    test('follows the store once loaded, one publication per pick', () async {
      await emoji.load(CollectionId.recent);
      var publications = 0;
      emoji.collections.addListener(() => publications++);

      await recents.record(key('1F600'), kind: SemanticKind.unicodeEmoji);

      expect(publications, 1);
      expect(recentKeys(), [key('1F600')]);
    });

    test('does not publish picks before it is loaded', () async {
      var publications = 0;
      emoji.collections.addListener(() => publications++);

      await recents.record(key('1F600'), kind: SemanticKind.unicodeEmoji);

      expect(publications, 0);
    });

    test('ignores emoji recorded under another kind', () async {
      await recents.record(key('1F600'), kind: SemanticKind.sticker);

      await emoji.load(CollectionId.recent);

      expect(recentKeys(), isEmpty);
    });
  });

  group('glyph support', () {
    late EmojiCollectionSource emoji;
    const faces = CollectionId.category('faces');
    const things = CollectionId.category('things');

    setUp(() => emoji = source());
    tearDown(() => emoji.dispose());

    List<ContentKey> keysOf(CollectionId id) =>
        (emoji.collections.value.firstWhere((c) => c.id == id).contents
                as CollectionContents$Loaded)
            .items
            .map((item) => item.key)
            .toList();

    test('hides the emoji the device cannot draw', () async {
      glyphs.learn(missing: {key('1F603')});

      await emoji.load(faces);

      expect(keysOf(faces), isNot(contains(key('1F603'))));
      expect(keysOf(faces), hasLength(4));
    });

    test('shows everything when no support source is supplied', () async {
      final all = source(withGlyphs: false);
      addTearDown(all.dispose);

      await all.load(faces);

      final loaded =
          all.collections.value.firstWhere((c) => c.id == faces).contents
              as CollectionContents$Loaded;
      expect(loaded.items, hasLength(5));
    });

    test('hides an emoji learned missing later, in one publication', () async {
      await emoji.load(faces);
      await emoji.load(things);
      var publications = 0;
      emoji.collections.addListener(() => publications++);

      glyphs.learn(missing: {key('1F603'), key('2764-FE0F')});

      expect(publications, 1);
      expect(keysOf(faces), hasLength(4));
      expect(keysOf(things), [key('1F44D')]);
    });

    test('falls back to the base when the chosen variant is missing', () async {
      await preferences.setPreferredVariant(key('1F44D'), key('1F44D-1F3FF'));
      glyphs.learn(missing: {key('1F44D-1F3FF')});

      await emoji.load(things);

      expect(keysOf(things).first, key('1F44D'));
    });

    test('hides an entry whose base is missing, variants and all', () async {
      glyphs.learn(missing: {key('1F44D')});

      await emoji.load(things);

      expect(keysOf(things), [key('2764-FE0F')]);
    });

    test('keeps the loaded count of pages when emoji are hidden', () async {
      final paged = source(pageSize: 2);
      addTearDown(paged.dispose);
      await paged.load(faces);

      glyphs.learn(missing: {key('1F600')});

      final loaded =
          paged.collections.value.firstWhere((c) => c.id == faces).contents
              as CollectionContents$Loaded;
      expect(loaded.items.map((i) => i.key), [key('1F603'), key('1F604')]);
      expect(loaded.nextPageToken, isNotNull);
    });

    test('hides recents the device cannot draw', () async {
      await recents.record(key('1F600'), kind: SemanticKind.unicodeEmoji);
      glyphs.learn(missing: {key('1F600')});

      await emoji.load(CollectionId.recent);

      expect(keysOf(CollectionId.recent), isEmpty);
    });
  });

  group('dispose', () {
    test('stops listening to the stores it was built on', () async {
      final emoji = source();
      await emoji.load(CollectionId.recent);
      var publications = 0;
      emoji.collections.addListener(() => publications++);

      emoji.dispose();
      await recents.record(key('1F600'), kind: SemanticKind.unicodeEmoji);
      glyphs.learn(missing: {key('1F600')});

      expect(publications, 0);
    });
  });
}
