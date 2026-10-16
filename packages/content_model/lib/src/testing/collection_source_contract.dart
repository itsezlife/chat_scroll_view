import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// A [CollectionSource] under test, with the facts about its content that the
/// contract needs and cannot invent.
final class CollectionSourceHarness {
  /// Creates a harness around [source].
  const CollectionSourceHarness({
    required this.source,
    required this.pagedId,
    required this.missingId,
    this.failLoads,
    this.failPages,
  });

  /// The source under test, fresh: nothing loaded yet.
  final CollectionSource source;

  /// A collection the source lists, idle, whose contents span at least two
  /// pages and whose first page is not empty.
  final CollectionId pagedId;

  /// An id the source does not list.
  final CollectionId missingId;

  /// Makes first loads fail (`failing: true`) or succeed again, for a source
  /// whose backend can be made to. When null, the failure tests are skipped.
  final void Function({required bool failing})? failLoads;

  /// Makes loading a later page fail or succeed again. When null, the failure
  /// tests are skipped.
  final void Function({required bool failing})? failPages;
}

/// Runs the [CollectionSource] contract against the harnesses [create]
/// returns, one per test.
void runCollectionSourceContract(
  Future<CollectionSourceHarness> Function() create,
) {
  group('CollectionSource contract', () {
    late CollectionSourceHarness harness;
    late CollectionSource source;
    late List<List<Collection>> published;

    Collection? find(CollectionId id, [List<Collection>? from]) {
      for (final collection in from ?? source.collections.value) {
        if (collection.id == id) return collection;
      }
      return null;
    }

    CollectionContents contentsOf(CollectionId id) => find(id)!.contents;

    Future<void> loadAll(CollectionId id) async {
      await source.load(id);
      for (var guard = 0; guard < 100; guard++) {
        final contents = contentsOf(id);
        if (contents is! CollectionContents$Loaded ||
            contents.nextPageToken == null) {
          return;
        }
        await source.loadMore(id);
      }
    }

    setUp(() async {
      harness = await create();
      source = harness.source;
      published = [];
      source.collections.addListener(
        () => published.add(source.collections.value),
      );
    });

    tearDown(() => source.dispose());

    group('collections', () {
      test('lists the paged collection, idle', () {
        expect(find(harness.pagedId), isNotNull);
        expect(contentsOf(harness.pagedId), CollectionContents.idle);
      });

      test('lists no id twice', () {
        final ids = [for (final c in source.collections.value) c.id];

        expect(ids.toSet(), hasLength(ids.length));
      });

      test('does not list the missing id', () {
        expect(find(harness.missingId), isNull);
      });

      test('publishes an unmodifiable list', () {
        expect(
          () => source.collections.value.add(
            const Collection(id: CollectionId.recent),
          ),
          throwsUnsupportedError,
        );
      });

      test('keeps the order of the list while contents load', () async {
        final before = [for (final c in source.collections.value) c.id];

        await loadAll(harness.pagedId);

        expect([for (final c in source.collections.value) c.id], before);
      });

      test('leaves a snapshot taken earlier as it was', () async {
        final before = source.collections.value;

        await source.load(harness.pagedId);

        expect(
          find(harness.pagedId, before)!.contents,
          CollectionContents.idle,
        );
      });
    });

    group('load', () {
      test('goes from idle through loading to loaded', () async {
        await source.load(harness.pagedId);

        expect(
          [for (final list in published) find(harness.pagedId, list)!.contents],
          [CollectionContents.loading, isA<CollectionContents$Loaded>()],
        );
      });

      test('has published the outcome when the future completes', () async {
        await source.load(harness.pagedId);

        final contents = contentsOf(harness.pagedId);
        expect(contents, isA<CollectionContents$Loaded>());
        final loaded = contents as CollectionContents$Loaded;
        expect(loaded.items, isNotEmpty);
        expect(loaded.nextPageToken, isNotNull);
      });

      test('publishes once per change', () async {
        await source.load(harness.pagedId);

        expect(published, hasLength(2));
      });

      test('changes nothing on a collection that is loaded', () async {
        await source.load(harness.pagedId);
        final before = published.length;

        await source.load(harness.pagedId);

        expect(published, hasLength(before));
      });

      test('loads once when asked twice at the same time', () async {
        await Future.wait([
          source.load(harness.pagedId),
          source.load(harness.pagedId),
        ]);

        expect(published, hasLength(2));
        expect(contentsOf(harness.pagedId), isA<CollectionContents$Loaded>());
      });

      test('changes nothing for an id the source does not list', () async {
        await source.load(harness.missingId);

        expect(published, isEmpty);
        expect(find(harness.missingId), isNull);
      });
    });

    group('loadMore', () {
      test('appends the next page after the items already there', () async {
        await source.load(harness.pagedId);
        final first = contentsOf(harness.pagedId) as CollectionContents$Loaded;

        await source.loadMore(harness.pagedId);

        final both = contentsOf(harness.pagedId) as CollectionContents$Loaded;
        expect(both.items.length, greaterThan(first.items.length));
        expect(both.items.take(first.items.length), first.items);
        expect(both.nextPageToken, isNot(first.nextPageToken));
      });

      test('stays loaded while the page is fetched', () async {
        await source.load(harness.pagedId);
        published.clear();

        await source.loadMore(harness.pagedId);

        for (final list in published) {
          expect(
            find(harness.pagedId, list)!.contents,
            isA<CollectionContents$Loaded>(),
          );
        }
      });

      test('changes nothing once the last page is in', () async {
        await loadAll(harness.pagedId);
        final last = contentsOf(harness.pagedId) as CollectionContents$Loaded;
        expect(last.nextPageToken, isNull);
        published.clear();

        await source.loadMore(harness.pagedId);

        expect(published, isEmpty);
        expect(contentsOf(harness.pagedId), last);
      });

      test('changes nothing on a collection that is not loaded', () async {
        await source.loadMore(harness.pagedId);

        expect(published, isEmpty);
        expect(contentsOf(harness.pagedId), CollectionContents.idle);
      });

      test('fetches a page once when asked twice at the same time', () async {
        await source.load(harness.pagedId);
        published.clear();

        await Future.wait([
          source.loadMore(harness.pagedId),
          source.loadMore(harness.pagedId),
        ]);

        expect(published, hasLength(1));
      });

      test('changes nothing for an id the source does not list', () async {
        await source.loadMore(harness.missingId);

        expect(published, isEmpty);
      });
    });

    group('failure', () {
      test('is a failed state, never an error from load', () async {
        final failLoads = harness.failLoads;
        if (failLoads == null) {
          markTestSkipped('this source cannot be made to fail loads');
          return;
        }
        failLoads(failing: true);

        await source.load(harness.pagedId);

        expect(contentsOf(harness.pagedId), isA<CollectionContents$Failed>());
      });

      test('is retried by loading the failed collection again', () async {
        final failLoads = harness.failLoads;
        if (failLoads == null) {
          markTestSkipped('this source cannot be made to fail loads');
          return;
        }
        failLoads(failing: true);
        await source.load(harness.pagedId);
        failLoads(failing: false);

        await source.load(harness.pagedId);

        expect(contentsOf(harness.pagedId), isA<CollectionContents$Loaded>());
      });

      test('leaves a loaded collection loaded when a page fails', () async {
        final failPages = harness.failPages;
        if (failPages == null) {
          markTestSkipped('this source cannot be made to fail pages');
          return;
        }
        await source.load(harness.pagedId);
        final before = contentsOf(harness.pagedId);
        failPages(failing: true);

        await source.loadMore(harness.pagedId);

        expect(contentsOf(harness.pagedId), before);
      });

      test('lets a failed page be fetched again', () async {
        final failPages = harness.failPages;
        if (failPages == null) {
          markTestSkipped('this source cannot be made to fail pages');
          return;
        }
        await source.load(harness.pagedId);
        final before = contentsOf(harness.pagedId) as CollectionContents$Loaded;
        failPages(failing: true);
        await source.loadMore(harness.pagedId);
        failPages(failing: false);

        await source.loadMore(harness.pagedId);

        final after = contentsOf(harness.pagedId) as CollectionContents$Loaded;
        expect(after.items.length, greaterThan(before.items.length));
      });
    });

    group('after dispose', () {
      test('is silent and ignores commands', () async {
        source.dispose();

        await source.load(harness.pagedId);
        await source.loadMore(harness.pagedId);

        expect(published, isEmpty);
        expect(contentsOf(harness.pagedId), CollectionContents.idle);
      });

      test('drops work still in flight', () async {
        final pending = source.load(harness.pagedId);
        published.clear();

        source.dispose();
        await pending;

        expect(published, isEmpty);
        expect(
          contentsOf(harness.pagedId),
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
