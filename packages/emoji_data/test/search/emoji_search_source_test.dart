import 'dart:async';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

import '../support/synthetic_catalog.dart';

KeywordPack _pack(
  String language,
  Map<String, List<String>> keywords, {
  int version = 0,
}) => KeywordPack(
  language: language,
  version: version,
  keywords: {for (final e in keywords.entries) key(e.key): e.value},
);

void main() {
  late FakeKeywordSource keywords;
  late FakeRecentsStore recents;
  late FakePreferenceStore preferences;
  late FakeGlyphSupport glyphs;

  // 1F600 grinning face, 1F603 smiling face, 1F604 happy face, 1F601 beam,
  // 1F606 laughing, 1F44D thumbs up (toned), 2764-FE0F red heart.
  final english = _pack('en', {
    '1F600': ['grinning face', 'grin', 'happy'],
    '1F603': ['smiling face', 'smile', 'happy'],
    '1F604': ['happy face', 'smile'],
    '1F601': ['beaming face', 'face', 'grin'],
    '1F606': ['squinting face', 'laugh'],
    '1F44D': ['thumbs up', 'like', 'yes'],
    '2764-FE0F': ['red heart', 'love', 'heart'],
  });

  setUp(() {
    keywords = FakeKeywordSource([english]);
    recents = FakeRecentsStore();
    preferences = FakePreferenceStore();
    glyphs = FakeGlyphSupport();
  });

  EmojiSearchSource source({
    List<String> languages = const ['en'],
    int? pageSize,
  }) => EmojiSearchSource(
    catalog: sampleCatalog(),
    keywords: keywords,
    languages: languages,
    recents: recents,
    preferences: preferences,
    glyphSupport: glyphs,
    pageSize: pageSize,
  );

  runSearchSourceContract(
    () async => SearchSourceHarness(
      source: source(pageSize: 2),
      query: 'face',
      otherQuery: 'heart',
      failSearches: ({required failing}) =>
          keywords.failure = failing ? Exception('no pack') : null,
    ),
  );

  group('results', () {
    late EmojiSearchSource search;

    setUp(() => search = source());
    tearDown(() => search.dispose());

    List<ContentKey> found() =>
        (search.results.value.contents as CollectionContents$Loaded).items
            .map((item) => item.key)
            .toList();

    test('describe each hit as a unicode emoji drawn as a glyph', () async {
      await search.search('heart');

      expect(
        (search.results.value.contents as CollectionContents$Loaded)
            .items
            .single,
        CollectionItem.described(
          ContentDescriptor(
            key: key('2764-FE0F'),
            semanticKind: SemanticKind.unicodeEmoji,
            mediaForm: MediaForm.glyph,
          ),
        ),
      );
    });

    test('rank exact before prefix before later-token prefix', () async {
      keywords.publish(
        _pack('en', {
          '1F600': ['green tea'],
          '1F603': ['teapot'],
          '1F604': ['tea'],
        }),
      );

      await search.search('tea');

      // Palette order is 1F600, 1F603, 1F604: only the tier reorders them.
      expect(found(), [key('1F604'), key('1F603'), key('1F600')]);
    });

    test('find a later word of a phrase by its prefix', () async {
      await search.search('squint');
      expect(found(), [key('1F606')]);

      await search.search('up');
      expect(found(), [key('1F44D')]);
    });

    test('find a phrase by the prefix of its first word', () async {
      await search.search('gri');

      expect(found(), [key('1F600'), key('1F601')]);
    });

    test('fold case and spacing in the query', () async {
      await search.search('  HAPPY   Face ');

      expect(found(), [key('1F604')]);
    });

    test('match nothing for a query of punctuation only', () async {
      await search.search('!!');

      expect(found(), isEmpty);
    });

    test(
      'order equally ranked hits by recents frequency, then palette',
      () async {
        await recents.record(key('1F606'), kind: SemanticKind.unicodeEmoji);
        await recents.record(key('1F604'), kind: SemanticKind.unicodeEmoji);
        await recents.record(key('1F604'), kind: SemanticKind.unicodeEmoji);

        await search.search('face');

        // 1F601 is the only exact hit; the others are later-token hits, the
        // recent ones first (1F604 picked twice), the rest in palette order.
        expect(found(), [
          key('1F601'),
          key('1F604'),
          key('1F606'),
          key('1F600'),
          key('1F603'),
        ]);
      },
    );

    test('show the variant the user chose for a base', () async {
      await preferences.setPreferredVariant(key('1F44D'), key('1F44D-1F3FF'));

      await search.search('like');

      expect(found(), [key('1F44D-1F3FF')]);
    });

    test('leave out what the device cannot draw', () async {
      glyphs.learn(missing: {key('1F600')});

      await search.search('grin');

      expect(found(), [key('1F601')]);
    });

    test('list a key found in two ways once', () async {
      await search.search('smile');

      expect(found().toSet(), hasLength(found().length));
    });

    test('are not recorded as use by the search itself', () async {
      await search.search('heart');

      expect(recents.recents(SemanticKind.unicodeEmoji), isEmpty);
    });

    test('keep a key the catalogue does not know, as it is', () async {
      keywords.publish(
        KeywordPack(
          language: 'en',
          version: 1,
          keywords: {
            ...english.keywords,
            key('1FAE8'): const ['shaking face'],
          },
        ),
      );

      await search.search('shaking');

      expect(found(), [key('1FAE8')]);
    });
  });

  group('languages', () {
    test('merge the packs of the set and list a key once', () async {
      keywords.publish(
        _pack('de', {
          '1F600': ['grinsendes gesicht', 'happy'],
          '2764-FE0F': ['rotes herz', 'liebe'],
        }),
      );
      final search = source(languages: const ['de', 'en']);
      addTearDown(search.dispose);

      await search.search('happy');
      final both = (search.results.value.contents as CollectionContents$Loaded)
          .items
          .map((item) => item.key);
      await search.search('rotes');
      final german =
          (search.results.value.contents as CollectionContents$Loaded).items
              .map((item) => item.key);

      expect(both, [key('1F600'), key('1F603'), key('1F604')]);
      expect(german, [key('2764-FE0F')]);
    });

    test('use the pack once when two tags resolve to it', () async {
      final search = source(languages: const ['en', 'en-GB']);
      addTearDown(search.dispose);

      await search.search('heart');

      expect(
        (search.results.value.contents as CollectionContents$Loaded).items,
        hasLength(1),
      );
    });

    test('ignore a language that has no pack', () async {
      final search = source(languages: const ['xx', 'en']);
      addTearDown(search.dispose);

      await search.search('heart');

      expect(
        (search.results.value.contents as CollectionContents$Loaded).items,
        hasLength(1),
      );
    });
  });

  group('a pack arriving', () {
    test('runs the current query again over the new keywords', () async {
      final search = source();
      addTearDown(search.dispose);
      await search.search('heart');
      var publications = 0;
      search.results.addListener(() => publications++);

      keywords.publish(
        _pack('en', {
          '2764-FE0F': ['red heart', 'heart', 'amour'],
          '1F44D': ['thumbs up', 'heart'],
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        (search.results.value.contents as CollectionContents$Loaded).items.map(
          (item) => item.key,
        ),
        [key('1F44D'), key('2764-FE0F')],
      );
      expect(publications, 1);
    });

    test('keeps the results on screen and reports a pack that cannot be read, '
        'instead of swallowing it', () async {
      final search = source();
      addTearDown(search.dispose);
      await search.search('heart');
      final before = search.results.value;
      final reported = <Object>[];

      await runZonedGuarded(() async {
        keywords.failure = Exception('unreadable pack');
        keywords.publish(
          _pack('en', {
            '1F44D': ['heart'],
          }),
        );
        await Future<void>.delayed(Duration.zero);
      }, (error, stack) => reported.add(error));

      expect(search.results.value, same(before));
      expect(reported, [isA<Exception>()]);
    });

    test('leaves an empty query alone', () async {
      final search = source();
      addTearDown(search.dispose);
      var publications = 0;
      search.results.addListener(() => publications++);

      keywords.publish(_pack('de', {}));
      await Future<void>.delayed(Duration.zero);

      expect(publications, 0);
    });
  });

  group('failure', () {
    test('searching the same query again retries a failed one', () async {
      final search = source();
      addTearDown(search.dispose);
      keywords.failure = Exception('no pack');
      await search.search('heart');
      expect(search.results.value.contents, isA<CollectionContents$Failed>());

      keywords.failure = null;
      await search.search('heart');

      expect(search.results.value.contents, isA<CollectionContents$Loaded>());
    });
  });

  group('dispose', () {
    test('stops listening to the stores it was built on', () async {
      final search = source();
      await search.search('like');
      var publications = 0;
      search.results.addListener(() => publications++);

      search.dispose();
      await preferences.setPreferredVariant(key('1F44D'), key('1F44D-1F3FF'));
      glyphs.learn(missing: {key('1F44D')});
      keywords.publish(_pack('en', {}));
      await Future<void>.delayed(Duration.zero);

      expect(publications, 0);
    });
  });
}
