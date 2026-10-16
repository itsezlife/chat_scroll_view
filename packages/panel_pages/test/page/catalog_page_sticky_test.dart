/// The sticky header of a catalogue page as a user sees it: a strip that
/// yields to reading, a search field that scrolls away with the content and
/// pins when search opens.
///
/// **Seam:** [CatalogPage] mounted with a policy that has a strip and places
/// its search field inline, over a fake host. Geometry is read from where the
/// widgets are painted: the strip is 40 px tall, the field's band 50 px, so the
/// catalogue's first header starts 90 px down, in a 320 x 480 page.
library;

import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

const _stripKey = ValueKey('strip');
const _faces = CollectionId.set('faces');
const _animals = CollectionId.set('animals');

CollectionItem _item(int i) =>
    CollectionItem.bare(ContentKey.unicode(String.fromCharCode(0x1F600 + i)));

FakeCollectionSource _source() => FakeCollectionSource([
  for (final (id, title, size) in [
    (_faces, 'Faces', 120),
    (_animals, 'Animals', 120),
  ])
    FakeCollectionSpec(
      id,
      metadata: CollectionMetadata(title: title),
      pages: FakePages([
        [for (var i = 0; i < size; i++) _item(i)],
      ]),
    ),
]);

class _Policy extends CatalogPagePolicy {
  CatalogStripHandle? handle;

  @override
  PageCapabilities get capabilities => const PageCapabilities(
    search: true,
    searchPlacement: SearchPlacement.inline,
    topStrip: true,
  );

  @override
  double get stripExtent => 40;

  @override
  SectionLayout? layoutOf(Collection collection) =>
      const SectionLayout.grid(spanCount: 4, cellExtent: 40, headerExtent: 24);

  @override
  Widget? buildStrip(BuildContext context, CatalogStripHandle strip) {
    handle = strip;
    return const SizedBox(height: 40, width: 320, key: _stripKey);
  }
}

void main() {
  late FakeCollectionSource source;
  late FakeSearchSource search;
  late FakePanelPageHost host;
  late AssetCacheScope assets;
  late _Policy policy;

  setUp(() {
    source = _source();
    search = FakeSearchSource({});
    host = FakePanelPageHost();
    assets = PageAssets.createScope();
    policy = _Policy();
    addTearDown(() {
      source.dispose();
      search.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      PanelShellTestScope(
        child: FakeSearchFieldScope(
          child: Center(
            child: SizedBox(
              width: 320,
              height: 480,
              child: CatalogPage(
                host: host,
                source: source,
                searchSource: search,
                policy: policy,
                assets: assets,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PanelCatalogController catalog() =>
      host.controllers.peek<CatalogPageController>('page')!.catalog;

  Offset page(WidgetTester tester) =>
      tester.getTopLeft(find.byType(CatalogPage));

  double stripTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(_stripKey)).dy - page(tester).dy;

  double fieldTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PanelSearchField)).dy - page(tester).dy;

  // Puts the catalogue at [offset] the way a jump does: nothing was read.
  Future<void> place(WidgetTester tester, double offset) async {
    catalog().jumpTo(offset);
    await tester.pump();
  }

  Future<void> read(WidgetTester tester, double distance) async {
    catalog().scrollBy(distance);
    await tester.pump();
  }

  group('at rest', () {
    testWidgets('the strip is at the top and the field in its band under it', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(stripTop(tester), 0);
      expect(fieldTop(tester), 40);
    });

    testWidgets('the catalogue starts under both', (tester) async {
      await pumpPage(tester);

      // A tap on the first row lands on its cell, not on the header chrome.
      await tester.tapAt(page(tester) + const Offset(40, 40 + 50 + 24 + 20));
      await tester.pump();
      expect(host.picks, hasLength(1));
    });
  });

  group('reading on', () {
    testWidgets('the field scrolls away with the content, the strip stays '
        'until the field has gone', (tester) async {
      await pumpPage(tester);

      await read(tester, 30);
      expect(fieldTop(tester), 10);
      expect(stripTop(tester), 0);

      // Up to the field's own height of reading the strip keeps its place...
      await read(tester, 20);
      expect(fieldTop(tester), -10);
      expect(stripTop(tester), 0);
      // ...and what is read beyond it moves the strip.
      await read(tester, 10);
      expect(fieldTop(tester), -20);
      expect(stripTop(tester), -10);
    });

    testWidgets('then the strip slides up by what is read, and back by what '
        'is read back', (tester) async {
      await pumpPage(tester);
      await place(tester, 300);

      await read(tester, 20);
      expect(stripTop(tester), -20);
      await read(tester, 100);
      expect(stripTop(tester), -40);

      await read(tester, -15);
      expect(stripTop(tester), -25);
      await read(tester, -50);
      expect(stripTop(tester), 0);
    });

    testWidgets('a field that has scrolled away is out of the way: a tap '
        'where it was reaches the catalogue', (tester) async {
      await pumpPage(tester);
      await read(tester, 400);
      await tester.pumpAndSettle();

      await tester.tapAt(page(tester) + const Offset(40, 60));
      await tester.pump();
      expect(host.picks, hasLength(1));
    });
  });

  group('search', () {
    testWidgets('opening it takes the strip out and pins the field at the '
        'top', (tester) async {
      await pumpPage(tester);
      await read(tester, 400);

      host.searchState = const PanelSearchState(isOpen: true);
      await tester.pumpAndSettle();

      expect(find.byKey(_stripKey), findsNothing);
      expect(fieldTop(tester), 0);
    });

    testWidgets('closing it brings the strip back, whole, and the field to '
        'its band', (tester) async {
      await pumpPage(tester);
      await place(tester, 400);
      await read(tester, 60);
      expect(stripTop(tester), -40);

      host.searchState = const PanelSearchState(isOpen: true);
      await tester.pumpAndSettle();
      host.searchState = PanelSearchState.closed;
      await tester.pumpAndSettle();

      expect(stripTop(tester), 0);
      expect(fieldTop(tester), -50);
    });
  });

  group('jumping to a section', () {
    testWidgets('lands its header right under the strip and leaves the strip '
        'whole', (tester) async {
      await pumpPage(tester);
      await place(tester, 400);
      await read(tester, 60);
      expect(stripTop(tester), -40);

      unawaited(policy.handle!.jumpToSection('CollectionId.set(animals)'));
      await tester.pumpAndSettle();

      expect(stripTop(tester), 0);
      // Section 1's header starts 24 + 30 rows of 40 under section 0's top.
      const headerContentTop = 90 + 24 + 30 * 40;
      expect(catalog().offset, headerContentTop - 40);
    });

    testWidgets('selecting the page tab again reveals the strip and lands the '
        'first section under it', (tester) async {
      await pumpPage(tester);
      await place(tester, 500);
      await read(tester, 60);
      expect(stripTop(tester), -40);

      host.reselect();
      await tester.pumpAndSettle();

      expect(stripTop(tester), 0);
      expect(catalog().offset, 90 - 40);
    });
  });
}
