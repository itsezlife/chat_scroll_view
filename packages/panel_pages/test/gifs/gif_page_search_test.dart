/// The GIF page when its clips can fail, can be searched, and carry an
/// attribution.
///
/// **Seam:** [GifPage] mounted under the chrome scopes with fake sources and
/// a fake page host, observed through the text the user reads, the clips that
/// can be tapped and the reports the host received. Geometry as in
/// `gif_page_test.dart`: a 400 x 480 page, square clips 100 px each.
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

FakeCollectionSpec _trending() => FakeCollectionSpec(
  const CollectionId.query(''),
  metadata: const CollectionMetadata(title: 'Trending'),
  pages: _pages('t'),
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

  setUp(() {
    host = FakePanelPageHost(pageId: 'gif');
    assets = PageAssets.createScope();
    source = FakeCollectionSource([_trending()]);
    search = FakeSearchSource({'cat': _pages('c'), 'none': FakePages.none});
    addTearDown(() {
      source.dispose();
      search.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    bool searchable = true,
    String? attribution,
  }) async {
    await tester.pumpWidget(
      PanelShellTestScope(
        child: Center(
          child: SizedBox(
            width: 400,
            height: 480,
            child: GifPage(
              host: host,
              source: source,
              assets: assets,
              searchSource: searchable ? search : null,
              attribution: attribution,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Offset firstCell(WidgetTester tester) =>
      tester.getTopLeft(find.byType(GifPage)) + const Offset(49, 52);

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
}
