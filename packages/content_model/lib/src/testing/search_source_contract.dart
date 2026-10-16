import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [SearchSource] under test, with the queries the contract needs and
/// cannot invent.
final class SearchSourceHarness {
  /// Creates a harness around [source].
  const SearchSourceHarness({
    required this.source,
    required this.query,
    required this.otherQuery,
    this.failSearches,
    this.failPages,
  });

  /// The source under test, fresh: nothing searched yet.
  final SearchSource source;

  /// A query whose results span at least two pages and whose first page is
  /// not empty. Not blank.
  final String query;

  /// A second query, different from [query], with at least one result.
  final String otherQuery;

  /// Makes first pages fail (`failing: true`) or succeed again. When null,
  /// the failure tests are skipped.
  final void Function({required bool failing})? failSearches;

  /// Makes loading a later page fail or succeed again. When null, the failure
  /// tests are skipped.
  final void Function({required bool failing})? failPages;
}

/// The behaviour every [SearchSource] must have, as a test suite to run against
/// an implementation.
abstract final class SearchSourceContract {
  /// Runs the [SearchSource] contract against the harnesses [create] returns,
  /// one per test.
  static void run(Future<SearchSourceHarness> Function() create) {
    group('SearchSource contract', () {
      late SearchSourceHarness harness;
      late SearchSource source;
      late List<Collection> published;

      CollectionContents$Loaded loaded() =>
          source.results.value.contents as CollectionContents$Loaded;

      setUp(() async {
        harness = await create();
        source = harness.source;
        published = [];
        source.results.addListener(() => published.add(source.results.value));
      });

      tearDown(() => source.dispose());

      group('before the first search', () {
        test('describes the empty query, idle', () {
          expect(
            source.results.value,
            const Collection(id: CollectionId.query('')),
          );
        });
      });

      group('search', () {
        test('describes the query it was given', () async {
          await source.search(harness.query);

          expect(source.results.value.id, CollectionId.query(harness.query));
        });

        test(
          'goes from loading to loaded, publishing once per change',
          () async {
            await source.search(harness.query);

            expect(
              [for (final c in published) c.contents],
              [CollectionContents.loading, isA<CollectionContents$Loaded>()],
            );
          },
        );

        test('has published the outcome when the future completes', () async {
          await source.search(harness.query);

          expect(loaded().items, isNotEmpty);
          expect(loaded().nextPageToken, isNotNull);
        });

        test('lists no key twice', () async {
          await source.search(harness.query);

          final keys = [for (final item in loaded().items) item.key];
          expect(keys.toSet(), hasLength(keys.length));
        });

        test('changes nothing when the query repeats', () async {
          await source.search(harness.query);
          published.clear();

          await source.search(harness.query);

          expect(published, isEmpty);
        });

        test('replaces the results with those of a new query', () async {
          await source.search(harness.query);

          await source.search(harness.otherQuery);

          expect(
            source.results.value.id,
            CollectionId.query(harness.otherQuery),
          );
          expect(loaded().items, isNotEmpty);
        });

        test('clears an empty query to idle without searching', () async {
          await source.search(harness.query);
          published.clear();

          await source.search('');

          expect(
            source.results.value,
            const Collection(id: CollectionId.query('')),
          );
          expect(published, hasLength(1));
        });

        test('clears a blank query to idle', () async {
          await source.search(harness.query);

          await source.search('   ');

          expect(source.results.value.id, const CollectionId.query('   '));
          expect(source.results.value.contents, CollectionContents.idle);
        });

        test(
          'never publishes the results of a query it has left behind',
          () async {
            final stale = source.search(harness.query);
            published.clear();

            final current = source.search(harness.otherQuery);
            await Future.wait([stale, current]);

            expect(published, isNotEmpty);
            for (final collection in published) {
              expect(collection.id, CollectionId.query(harness.otherQuery));
            }
            expect(
              source.results.value.id,
              CollectionId.query(harness.otherQuery),
            );
            expect(
              source.results.value.contents,
              isA<CollectionContents$Loaded>(),
            );
          },
        );

        test(
          'drops a search still in flight when the query is cleared',
          () async {
            final stale = source.search(harness.query);

            await source.search('');
            await stale;

            expect(
              source.results.value,
              const Collection(id: CollectionId.query('')),
            );
          },
        );
      });

      group('loadMore', () {
        test('appends the next page after the items already there', () async {
          await source.search(harness.query);
          final first = loaded();

          await source.loadMore();

          expect(loaded().items.length, greaterThan(first.items.length));
          expect(loaded().items.take(first.items.length), first.items);
        });

        test('keeps no key twice once a page is added', () async {
          await source.search(harness.query);
          await source.loadMore();

          final keys = [for (final item in loaded().items) item.key];
          expect(keys.toSet(), hasLength(keys.length));
        });

        test('changes nothing once the last page is in', () async {
          await source.search(harness.query);
          for (
            var guard = 0;
            guard < 100 && loaded().nextPageToken != null;
            guard++
          ) {
            await source.loadMore();
          }
          final last = source.results.value;
          published.clear();

          await source.loadMore();

          expect(published, isEmpty);
          expect(source.results.value, last);
        });

        test('changes nothing before any search', () async {
          await source.loadMore();

          expect(published, isEmpty);
        });

        test('fetches a page once when asked twice at the same time', () async {
          await source.search(harness.query);
          published.clear();

          await Future.wait([source.loadMore(), source.loadMore()]);

          expect(published, hasLength(1));
        });
      });

      group('failure', () {
        test('is a failed state, never an error from search', () async {
          final failSearches = harness.failSearches;
          if (failSearches == null) {
            markTestSkipped('this source cannot be made to fail searches');
            return;
          }
          failSearches(failing: true);

          await source.search(harness.query);

          expect(
            source.results.value.contents,
            isA<CollectionContents$Failed>(),
          );
        });

        test('leaves loaded results loaded when a page fails', () async {
          final failPages = harness.failPages;
          if (failPages == null) {
            markTestSkipped('this source cannot be made to fail pages');
            return;
          }
          await source.search(harness.query);
          final before = source.results.value;
          failPages(failing: true);

          await source.loadMore();

          expect(source.results.value, before);
        });

        test('lets a failed page be fetched again', () async {
          final failPages = harness.failPages;
          if (failPages == null) {
            markTestSkipped('this source cannot be made to fail pages');
            return;
          }
          await source.search(harness.query);
          final before = loaded();
          failPages(failing: true);
          await source.loadMore();
          failPages(failing: false);

          await source.loadMore();

          expect(loaded().items.length, greaterThan(before.items.length));
        });
      });

      group('after dispose', () {
        test('is silent and ignores commands', () async {
          source.dispose();

          await source.search(harness.query);
          await source.loadMore();

          expect(published, isEmpty);
          expect(source.results.value.contents, CollectionContents.idle);
        });

        test('drops a search still in flight', () async {
          final pending = source.search(harness.query);
          published.clear();

          source.dispose();
          await pending;

          expect(published, isEmpty);
          expect(
            source.results.value.contents,
            isNot(isA<CollectionContents$Loaded>()),
          );
        });

        test('can be disposed twice', () {
          source.dispose();

          expect(source.dispose, returnsNormally);
        });
      });
    });
  }
}
