import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';

final PanelStrings _strings = ChromeStringsPresets.english.panel;

const _faces = CollectionId.set('faces');
const _animals = CollectionId.set('animals');

CollectionItem _item(String glyph) =>
    CollectionItem.bare(ContentKey.unicode(glyph));

FakePages _pages(List<List<String>> pages) =>
    FakePages([for (final page in pages) page.map(_item).toList()]);

const _facesSection = 'CollectionId.set(faces)';
const _animalsSection = 'CollectionId.set(animals)';

void main() {
  late FakeCollectionSource source;
  late FakePanelPageHost host;
  late StreamController<PanelCatalogScrollEvent> events;
  final models = <CatalogPageModel>[];

  void disposeModels() {
    for (final model in models) {
      model.dispose();
    }
    models.clear();
  }

  setUp(() {
    source = FakeCollectionSource([
      FakeCollectionSpec(
        _faces,
        metadata: const CollectionMetadata(title: 'Faces'),
        pages: _pages([
          ['a', 'b'],
          ['c'],
        ]),
      ),
      FakeCollectionSpec(
        _animals,
        metadata: const CollectionMetadata(title: 'Animals'),
        pages: _pages([
          ['x'],
        ]),
      ),
    ]);
    host = FakePanelPageHost();
    events = StreamController<PanelCatalogScrollEvent>.broadcast(sync: true);
    addTearDown(() {
      disposeModels();
      source.dispose();
      host.dispose();
      unawaited(events.close());
    });
  });

  CatalogPageModel build({
    CollectionSource? withSource,
    SearchSource? search,
    CatalogPagePolicy policy = const _Plain(),
  }) {
    final model = CatalogPageModel(
      source: withSource ?? source,
      searchSource: search,
      policy: policy,
      strings: _strings,
      host: host,
      events: events.stream,
    );
    models.add(model);
    return model;
  }

  Map<String, CatalogSection> sectionsOf(CatalogPageModel model) => {
    for (final section in model.snapshots.value.sections) section.id: section,
  };

  void near(String section, CatalogSectionEdge edge) =>
      events.add(PanelCatalogSectionNearViewport(section, edge));

  group('the catalogue it shows', () {
    test('holds one section per collection, loading until announced', () {
      final model = build();

      final sections = model.snapshots.value.sections;
      expect(sections.map((section) => section.id), [
        _facesSection,
        _animalsSection,
      ]);
      expect(sections.map((section) => section.title), ['Faces', 'Animals']);
      expect(
        sections.map((section) => section.state),
        everyElement(CatalogSectionState.loading),
      );
    });

    test('publishes a new snapshot when a collection changes', () async {
      final model = build();
      final seen = <CatalogSnapshot>[];
      model.snapshots.addListener(() => seen.add(model.snapshots.value));

      await source.load(_faces);

      expect(seen, isNotEmpty);
      final faces = sectionsOf(model)[_facesSection]!;
      expect(faces.state, CatalogSectionState.loaded);
      expect(faces.leaves.map((leaf) => leaf.key), [
        const ContentKey.unicode('a'),
        const ContentKey.unicode('b'),
      ]);
    });

    test('lists the sections for the strip, in order', () {
      final model = build();

      expect(model.stripEntries.value.map((entry) => entry.sectionId), [
        _facesSection,
        _animalsSection,
      ]);
      expect(model.stripEntries.value.first.collection.id, _faces);
    });

    test('locates a section by id', () {
      final model = build();

      expect(model.sectionIndexOf(_animalsSection), 1);
      expect(model.sectionIndexOf('missing'), isNull);
      expect(model.collectionOf(_animalsSection)!.id, _animals);
    });

    test('shows what the policy leaves of the collections', () {
      final model = build(policy: const _OnlyFaces());

      expect(sectionsOf(model).keys, [_facesSection]);
    });
  });

  group('near the viewport', () {
    test('loads an idle collection whose edge came near', () async {
      final model = build();

      near(_facesSection, CatalogSectionEdge.leading);
      await pumpEventQueue();

      expect(
        sectionsOf(model)[_facesSection]!.state,
        CatalogSectionState.loaded,
      );
      expect(
        sectionsOf(model)[_animalsSection]!.state,
        CatalogSectionState.loading,
        reason: 'only the section that came near is loaded',
      );
    });

    test('pages a loaded collection on its trailing edge', () async {
      final model = build();
      await source.load(_faces);

      near(_facesSection, CatalogSectionEdge.trailing);
      await pumpEventQueue();

      expect(sectionsOf(model)[_facesSection]!.leaves, hasLength(3));
    });

    test('does not page on the leading edge', () async {
      final model = build();
      await source.load(_faces);

      near(_facesSection, CatalogSectionEdge.leading);
      await pumpEventQueue();

      expect(sectionsOf(model)[_facesSection]!.leaves, hasLength(2));
    });

    test('stops paging when there is nothing more', () async {
      final model = build();
      await source.load(_animals);

      near(_animalsSection, CatalogSectionEdge.trailing);
      await pumpEventQueue();

      expect(sectionsOf(model)[_animalsSection]!.leaves, hasLength(1));
    });

    test(
      'retries a failed collection when its edge is announced again',
      () async {
        final model = build();
        source.failLoads = true;
        near(_facesSection, CatalogSectionEdge.leading);
        await pumpEventQueue();
        expect(
          sectionsOf(model)[_facesSection]!.state,
          CatalogSectionState.failed,
        );

        source.failLoads = false;
        near(_facesSection, CatalogSectionEdge.leading);
        await pumpEventQueue();

        expect(
          sectionsOf(model)[_facesSection]!.state,
          CatalogSectionState.loaded,
        );
      },
    );

    test('leaves a collection that is loading alone', () async {
      final model = build();
      source.pause();

      near(_facesSection, CatalogSectionEdge.leading);
      near(_facesSection, CatalogSectionEdge.trailing);
      source.resume();
      await pumpEventQueue();

      expect(sectionsOf(model)[_facesSection]!.leaves, hasLength(2));
    });

    test(
      'ignores a section it does not hold and events that are not near',
      () async {
        final model = build();

        near('missing', CatalogSectionEdge.leading);
        events
          ..add(const PanelCatalogUserDragStart())
          ..add(const PanelCatalogScrollingChanged(scrolling: true));
        await pumpEventQueue();

        expect(
          sectionsOf(model).values.map((section) => section.state),
          everyElement(CatalogSectionState.loading),
        );
      },
    );
  });

  group('swapping the data source', () {
    FakeCollectionSource other() => FakeCollectionSource([
      FakeCollectionSpec(
        _animals,
        metadata: const CollectionMetadata(title: 'Other animals'),
        pages: _pages([
          ['z'],
        ]),
      ),
    ]);

    test('shows the new source at once', () {
      final model = build();
      final next = other();
      addTearDown(next.dispose);

      model.source = next;

      expect(sectionsOf(model).keys, [_animalsSection]);
      expect(sectionsOf(model)[_animalsSection]!.title, 'Other animals');
    });

    test('follows the new source and forgets the old one', () async {
      final model = build();
      final next = other();
      addTearDown(next.dispose);
      model.source = next;

      await source.load(_faces);
      expect(sectionsOf(model).keys, [_animalsSection]);

      await next.load(_animals);
      expect(sectionsOf(model)[_animalsSection]!.leaves, hasLength(1));
    });

    test('loads from the new source when a section comes near', () async {
      final model = build();
      final next = other();
      addTearDown(next.dispose);
      model.source = next;

      near(_animalsSection, CatalogSectionEdge.leading);
      await pumpEventQueue();

      expect(
        next.collections.value.single.contents,
        isA<CollectionContents$Loaded>(),
      );
      expect(
        source.collections.value.last.contents,
        isNot(isA<CollectionContents$Loaded>()),
      );
    });

    test('keeps the viewport on the same snapshot listenable', () {
      final model = build();
      final snapshots = model.snapshots;
      final next = other();
      addTearDown(next.dispose);

      model.source = next;

      expect(model.snapshots, same(snapshots));
    });
  });

  group('a new language or policy', () {
    test('rebuilds the catalogue at once', () {
      final model = build();
      final before = model.snapshots.value;

      model.strings = _strings;
      expect(
        model.snapshots.value,
        same(before),
        reason: 'same strings: no change',
      );

      model.policy = const _OnlyFaces();
      expect(model.snapshots.value, isNot(same(before)));
      expect(sectionsOf(model).keys, [_facesSection]);
    });
  });

  group('search', () {
    late FakeSearchSource search;

    // The model's debounce timers must be gone before the test body ends.
    void searchTest(
      String description,
      Future<void> Function(WidgetTester tester) body,
    ) => testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        disposeModels();
      }
    });

    setUp(() {
      search = FakeSearchSource({
        'smile': _pages([
          ['😀', '😃'],
          ['😄'],
        ]),
        'nothing': _pages([[]]),
      });
    });
    tearDown(() => search.dispose());

    PanelSearchState open(String query) =>
        PanelSearchState(isOpen: true, query: query, wantsFocus: true);

    searchTest('keeps browsing while search is open with no query', (
      tester,
    ) async {
      final model = build(search: search);

      host.searchState = open('');

      expect(model.showsResults.value, isFalse);
      expect(sectionsOf(model).keys, [_facesSection, _animalsSection]);
    });

    searchTest('lets the policy narrow what an empty search shows', (
      tester,
    ) async {
      final model = build(
        search: search,
        policy: const _OnlyFacesWhileSearching(),
      );

      expect(sectionsOf(model).keys, [_facesSection, _animalsSection]);

      host.searchState = open('');

      expect(sectionsOf(model).keys, [_facesSection]);
    });

    searchTest('shows loading results as soon as there is a query', (
      tester,
    ) async {
      final model = build(search: search);

      host.searchState = open('smile');

      expect(model.showsResults.value, isTrue);
      final section = model.snapshots.value.sections.single;
      expect(section.title, _strings.searchResultsTitle);
      expect(section.state, CatalogSectionState.loading);
      expect(model.stripEntries.value, isEmpty);
    });

    searchTest('searches after the debounce and shows the results', (
      tester,
    ) async {
      final model = build(search: search);
      host.searchState = open('smile');

      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pump();

      final section = model.snapshots.value.sections.single;
      expect(section.state, CatalogSectionState.loaded);
      expect(section.leaves.map((leaf) => leaf.key), [
        const ContentKey.unicode('😀'),
        const ContentKey.unicode('😃'),
      ]);
    });

    searchTest(
      'keeps the earlier results up while the next query is searched',
      (tester) async {
        final model = build(search: search);
        host.searchState = open('smile');
        await tester.pump(DebouncedSearch.defaultDebounce);
        await tester.pump();

        host.searchState = open('smiley');

        final section = model.snapshots.value.sections.single;
        expect(section.state, CatalogSectionState.loaded);
        expect(section.leaves, hasLength(2));
      },
    );

    searchTest('says empty results with the panel strings', (tester) async {
      final model = build(search: search);
      host.searchState = open('nothing');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pump();

      final section = model.snapshots.value.sections.single;
      expect(section.leaves, isEmpty);
      expect(section.emptyMessage, _strings.searchEmpty);
    });

    searchTest('pages the results on their trailing edge', (tester) async {
      final model = build(search: search);
      host.searchState = open('smile');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pump();
      final id = model.snapshots.value.sections.single.id;

      near(id, CatalogSectionEdge.trailing);
      await tester.pump();

      expect(model.snapshots.value.sections.single.leaves, hasLength(3));
    });

    searchTest('returns to the collections when search closes', (tester) async {
      final model = build(search: search);
      host.searchState = open('smile');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pump();

      host.searchState = PanelSearchState.closed;
      await tester.pump();

      expect(model.showsResults.value, isFalse);
      expect(sectionsOf(model).keys, [_facesSection, _animalsSection]);
      expect(
        search.results.value.contents,
        CollectionContents.idle,
        reason: 'closing clears the results of the source',
      );
    });

    searchTest('reports progress while a search takes a while', (tester) async {
      build(search: search);
      search.pause();

      host.searchState = open('smile');
      await tester.pump(DebouncedSearch.defaultBusyDelay);
      expect(host.searchProgress, [true]);

      search.resume();
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pump();
      expect(host.searchProgress, [true, false]);
    });

    searchTest('announces the result count once per query, not per page', (
      tester,
    ) async {
      final model = build(search: search);
      host.searchState = open('smile');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pump();
      expect(host.searchResultCounts, [2]);

      near(
        model.snapshots.value.sections.single.id,
        CatalogSectionEdge.trailing,
      );
      await tester.pump();

      expect(host.searchResultCounts, [2]);
    });

    searchTest('announces again for the same query typed a second time', (
      tester,
    ) async {
      build(search: search);
      host.searchState = open('smile');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pump();

      host.searchState = PanelSearchState.closed;
      await tester.pump();
      host.searchState = open('smile');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pump();

      expect(host.searchResultCounts, [2, 2]);
    });

    searchTest('a page without a search source never leaves the collections', (
      tester,
    ) async {
      final model = build();

      host.searchState = open('smile');
      await tester.pump(DebouncedSearch.defaultDebounce);

      expect(model.showsResults.value, isFalse);
      expect(sectionsOf(model).keys, [_facesSection, _animalsSection]);
    });

    searchTest('searches a source set later for the query already typed', (
      tester,
    ) async {
      final model = build();
      host.searchState = open('smile');

      model.searchSource = search;
      await tester.pump();

      expect(model.showsResults.value, isTrue);
      expect(search.results.value.id, const CollectionId.query('smile'));
    });
  });

  test('stops following everything after dispose', () async {
    final model = build();
    final before = model.snapshots.value;

    model.dispose();
    await source.load(_faces);
    near(_facesSection, CatalogSectionEdge.leading);

    expect(model.snapshots.value, same(before));
  });
}

final class _Plain extends CatalogPagePolicy {
  const _Plain();
}

final class _OnlyFaces extends CatalogPagePolicy {
  const _OnlyFaces();

  @override
  List<Collection> visibleCollections(
    List<Collection> all, {
    required bool searchOpen,
  }) => [
    for (final collection in all)
      if (collection.id == _faces) collection,
  ];
}

final class _OnlyFacesWhileSearching extends CatalogPagePolicy {
  const _OnlyFacesWhileSearching();

  @override
  List<Collection> visibleCollections(
    List<Collection> all, {
    required bool searchOpen,
  }) => searchOpen
      ? [
          for (final collection in all)
            if (collection.id == _faces) collection,
        ]
      : all;
}
