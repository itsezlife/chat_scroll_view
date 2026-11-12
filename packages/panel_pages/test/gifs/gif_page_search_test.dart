/// The GIF page when its clips can fail, can be searched, and carry an
/// attribution.
///
/// **Seam:** [GifPage] mounted under the chrome scopes with fake sources and
/// a fake page host, observed through the text the user reads, the clips that
/// can be tapped, where the search field sits and the reports the host
/// received. Geometry as in `gif_page_test.dart`: a 400 x 480 page, square
/// clips 100 px each, under the field's 50 px band on a page that searches.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

CollectionItem _gif(String id) => CollectionItem.described(
  ContentDescriptor(
    key: ContentKey.document(id),
    semanticKind: SemanticKind.gif,
    mediaForm: MediaForm.video,
    animated: true,
    size: const ContentSize(128, 128),
    spokenName: 'gif $id',
  ),
);

FakePages _pages(String prefix, {int count = 4}) => FakePages([
  [for (var i = 0; i < count; i++) _gif('$prefix-$i')],
]);

FakeCollectionSpec _trending({int count = 4}) => FakeCollectionSpec(
  const CollectionId.query(''),
  metadata: const CollectionMetadata(title: 'Trending'),
  pages: _pages('t', count: count),
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakePanelPageHost host;
  late AssetCacheScope assets;
  late FakeCollectionSource source;
  late FakeSearchSource search;
  late FakeCollectionSource suggestions;
  // How far down the field's band puts the clips of the page last pumped.
  var band = 0.0;

  setUp(() {
    host = FakePanelPageHost(pageId: 'gif');
    assets = PageAssets.createScope();
    source = FakeCollectionSource([_trending()]);
    search = FakeSearchSource({
      'cat': _pages('c'),
      'dog': _pages('d'),
      'many': _pages('m', count: 80),
      'more': _pages('o', count: 80),
      'none': FakePages.none,
    });
    suggestions = FakeCollectionSource([
      FakeCollectionSpec(
        const CollectionId.set('suggested'),
        metadata: const CollectionMetadata(title: 'Trending'),
        pages: _pages('s'),
      ),
    ]);
    addTearDown(() {
      source.dispose();
      search.dispose();
      suggestions.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    bool searchable = true,
    bool suggesting = false,
    String? attribution,
  }) async {
    await tester.pumpWidget(
      PanelShellTestScope(
        child: FakeSearchFieldScope(
          child: Center(
            child: SizedBox(
              width: 400,
              height: 480,
              child: GifPage(
                host: host,
                source: source,
                assets: assets,
                searchSource: searchable ? search : null,
                searchSuggestions: suggesting ? suggestions : null,
                attribution: attribution,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    band = searchable ? PanelSearchField.height : 0;
  }

  Offset firstCell(WidgetTester tester) =>
      tester.getTopLeft(find.byType(GifPage)) + Offset(49, band + 52);

  Future<void> typeQuery(WidgetTester tester, String query) async {
    host.searchState = PanelSearchState(isOpen: true, query: query);
    await tester.pump();
    await settle(tester);
  }

  group('a collection that failed to load', () {
    testWidgets('says so and offers a retry that loads it again', (
      tester,
    ) async {
      source.failLoads = true;
      await pumpPage(tester);
      expect(find.text("Couldn't load GIFs"), findsOneWidget);

      source.failLoads = false;
      await tester.tap(find.text('Retry'));
      await settle(tester);

      expect(find.text("Couldn't load GIFs"), findsNothing);
      await tester.tapAt(firstCell(tester));
      expect(host.picks.single.key, const ContentKey.document('t-0'));
    });
  });

  group('the attribution', () {
    testWidgets('heads the clips when the host gives one', (tester) async {
      await pumpPage(tester, attribution: 'Powered by GIPHY');

      expect(find.text('Powered by GIPHY'), findsOneWidget);
    });

    testWidgets('is not there when the host gives none', (tester) async {
      await pumpPage(tester);

      expect(find.text('Powered by GIPHY'), findsNothing);
    });
  });

  group('search', () {
    testWidgets('shows the results of the query in place of the clips', (
      tester,
    ) async {
      await pumpPage(tester);

      await typeQuery(tester, 'cat');
      await tester.tapAt(firstCell(tester));

      expect(host.picks.single.key, const ContentKey.document('c-0'));
      expect(host.searchResultCounts, [4]);
    });

    testWidgets('waits for typing to pause before it searches', (tester) async {
      await pumpPage(tester);

      host.searchState = const PanelSearchState(isOpen: true, query: 'ca');
      await tester.pump();
      host.searchState = const PanelSearchState(isOpen: true, query: 'cat');
      await tester.pump(const Duration(milliseconds: 100));

      expect(search.results.value.id, const CollectionId.query(''));
      await settle(tester);
      expect(search.results.value.id, const CollectionId.query('cat'));
    });

    testWidgets('says when it found nothing', (tester) async {
      await pumpPage(tester);

      await typeQuery(tester, 'none');

      expect(find.text('No GIFs found'), findsOneWidget);
    });

    testWidgets('offers a retry when the search failed', (tester) async {
      await pumpPage(tester);
      search.failSearches = true;
      await typeQuery(tester, 'cat');
      expect(find.text("Couldn't load GIFs"), findsOneWidget);

      search.failSearches = false;
      await tester.tap(find.text('Retry'));
      await settle(tester);

      await tester.tapAt(firstCell(tester));
      expect(host.picks.single.key, const ContentKey.document('c-0'));
    });

    testWidgets('closing it brings the clips back', (tester) async {
      await pumpPage(tester);
      await typeQuery(tester, 'cat');

      host.searchState = PanelSearchState.closed;
      await tester.pump();
      await settle(tester);
      await tester.tapAt(firstCell(tester));

      expect(host.picks.single.key, const ContentKey.document('t-0'));
    });

    testWidgets('does nothing for a page given no search source', (
      tester,
    ) async {
      await pumpPage(tester, searchable: false);

      await typeQuery(tester, 'cat');
      await tester.tapAt(firstCell(tester));

      expect(host.picks.single.key, const ContentKey.document('t-0'));
    });
  });

  group('while a search is in flight', () {
    testWidgets('the clips shown stay until its results arrive', (
      tester,
    ) async {
      await pumpPage(tester);
      search.pause();

      await typeQuery(tester, 'cat');
      await tester.tapAt(firstCell(tester));
      expect(host.picks.last.key, const ContentKey.document('t-0'));

      search.resume();
      await settle(tester);
      await tester.tapAt(firstCell(tester));
      expect(host.picks.last.key, const ContentKey.document('c-0'));
    });

    testWidgets('the results of the text before stay until the new ones '
        'arrive', (tester) async {
      await pumpPage(tester);
      await typeQuery(tester, 'cat');
      search.pause();

      await typeQuery(tester, 'dog');
      await tester.tapAt(firstCell(tester));
      expect(host.picks.last.key, const ContentKey.document('c-0'));

      search.resume();
      await settle(tester);
      await tester.tapAt(firstCell(tester));
      expect(host.picks.last.key, const ContentKey.document('d-0'));
    });

    testWidgets('the field shows progress, until the results arrive', (
      tester,
    ) async {
      await pumpPage(tester);
      search.pause();

      await typeQuery(tester, 'cat');
      expect(host.searchProgress, [true]);

      search.resume();
      await settle(tester);
      expect(host.searchProgress, [true, false]);
    });
  });

  group('the results that arrive', () {
    Finder viewOf(String id) => find.byWidgetPredicate(
      (w) => w is ContentView && w.content == ContentKey.document(id),
    );

    double opacityOf(WidgetTester tester, String id) {
      var opacity = 1.0;
      for (final fade in tester.widgetList<FadeTransition>(
        find.ancestor(of: viewOf(id), matching: find.byType(FadeTransition)),
      )) {
        opacity *= fade.opacity.value;
      }
      return opacity;
    }

    testWidgets('are shown from their start', (tester) async {
      await pumpPage(tester);
      await typeQuery(tester, 'many');
      await tester.drag(find.byType(GifPage), const Offset(0, -300));
      await settle(tester);

      await typeQuery(tester, 'more');
      await tester.tapAt(firstCell(tester));

      expect(host.picks.single.key, const ContentKey.document('o-0'));
    });

    testWidgets('fade their cells in', (tester) async {
      await pumpPage(tester);
      search.pause();
      await typeQuery(tester, 'cat');

      search.resume();
      await tester.pump();
      await tester.pump();
      expect(opacityOf(tester, 'c-0'), lessThan(1));

      await settle(tester);
      expect(opacityOf(tester, 'c-0'), 1);
    });
  });

  group('with no text yet', () {
    testWidgets('lists the suggestions the host gives in place of the clips', (
      tester,
    ) async {
      await pumpPage(tester, suggesting: true);

      await typeQuery(tester, '');
      await tester.tapAt(firstCell(tester));

      expect(host.picks.single.key, const ContentKey.document('s-0'));
    });

    testWidgets('lists the clips once search closes', (tester) async {
      await pumpPage(tester, suggesting: true);
      await typeQuery(tester, '');

      host.searchState = PanelSearchState.closed;
      await tester.pump();
      await settle(tester);
      await tester.tapAt(firstCell(tester));

      expect(host.picks.single.key, const ContentKey.document('t-0'));
    });

    testWidgets('lists the clips when the host gives no suggestions', (
      tester,
    ) async {
      await pumpPage(tester);

      await typeQuery(tester, '');
      await tester.tapAt(firstCell(tester));

      expect(host.picks.single.key, const ContentKey.document('t-0'));
    });

    testWidgets('asks for no suggestions before search opens', (tester) async {
      await pumpPage(tester, suggesting: true);

      expect(
        suggestions.collections.value.single.contents,
        CollectionContents.idle,
      );
    });
  });

  group('the field', () {
    Offset fieldTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(PanelSearchField)) -
        tester.getTopLeft(find.byType(GifPage));

    bool hairline(WidgetTester tester) => tester
        .widget<PanelSearchField>(find.byType(PanelSearchField))
        .shadow!
        .value;

    Future<void> pumpLong(WidgetTester tester) async {
      source.dispose();
      source = FakeCollectionSource([_trending(count: 80)]);
      await pumpPage(tester);
    }

    testWidgets('heads the page and stays there while the clips scroll', (
      tester,
    ) async {
      await pumpLong(tester);
      expect(fieldTop(tester), Offset.zero);

      await tester.drag(find.byType(GifPage), const Offset(0, -300));
      await settle(tester);

      expect(fieldTop(tester), Offset.zero);
    });

    testWidgets('has the clips start under it, never behind it: the panel '
        'background may be see-through', (tester) async {
      await pumpLong(tester);
      final list = find.descendant(
        of: find.byType(GifPage),
        matching: find.byType(Scrollable),
      );
      double listTop() =>
          tester.getTopLeft(list.first).dy -
          tester.getTopLeft(find.byType(GifPage)).dy;
      expect(listTop(), PanelSearchField.height);

      await tester.drag(find.byType(GifPage), const Offset(0, -300));
      await settle(tester);

      expect(listTop(), PanelSearchField.height);
    });

    testWidgets('is not there on a page given no search source', (
      tester,
    ) async {
      await pumpPage(tester, searchable: false);

      expect(find.byType(PanelSearchField), findsNothing);
    });

    testWidgets('shows its hairline unless search is open at the start', (
      tester,
    ) async {
      await pumpLong(tester);
      expect(hairline(tester), isTrue);

      host.searchState = const PanelSearchState(isOpen: true);
      await tester.pump();
      expect(hairline(tester), isFalse);

      await tester.drag(find.byType(GifPage), const Offset(0, -300));
      await settle(tester);
      expect(hairline(tester), isTrue);
    });
  });
}
