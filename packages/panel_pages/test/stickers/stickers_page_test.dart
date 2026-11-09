/// The stickers page as a user and the shell see it.
///
/// **Seam:** [StickersPage] mounted under the chrome scopes with a fake source,
/// a fake page host and a real asset scope, observed through the picks and
/// requests the host received, the semantics of the strip and the catalogue's
/// offset. Geometry: a 360 x 480 page with the 36 px strip above, packs of
/// 20 stickers in 5 columns of 72 x 82 under a 27 px header, so the first cell
/// of the first section has its centre at (36, 36 + 27 + 41).
library;

import 'dart:ui' show Tristate;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart' show isTest;
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/testing.dart';

CollectionItem _sticker(String id) => CollectionItem.described(
  ContentDescriptor(
    key: ContentKey.document(id),
    semanticKind: SemanticKind.sticker,
    mediaForm: MediaForm.still,
    size: const ContentSize(512, 512),
    spokenName: 'sticker $id',
  ),
);

FakeCollectionSpec _pack(String id, String title, {int count = 20}) =>
    FakeCollectionSpec(
      CollectionId.set(id),
      metadata: CollectionMetadata(title: title),
      pages: FakePages([
        [for (var i = 0; i < count; i++) _sticker('$id-$i')],
      ]),
    );

FakeCollectionSpec _recents() => FakeCollectionSpec(
  CollectionId.recent,
  pages: FakePages([
    [_sticker('a-3'), _sticker('b-1')],
  ]),
);

// The stand-ins of stickers nobody decodes here shimmer for good, so the page
// never settles: run the clock for a while instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// A widget test with semantics on, which the catalogue's titles and buttons
// are found by; the handle must be released before the test ends.
@isTest
void pageTest(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(name, (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        semantics.dispose();
      }
    });

void main() {
  late FakePanelPageHost host;
  late AssetCacheScope assets;
  late FakeCollectionSource source;

  setUp(() {
    host = FakePanelPageHost(pageId: 'stickers');
    assets = PageAssets.createScope();
    source = FakeCollectionSource([
      _pack('a', 'Cats'),
      _pack('b', 'Dogs'),
      _pack('c', 'Birds'),
    ]);
    addTearDown(() {
      source.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  Widget page({double width = 360, TextDirection? direction}) =>
      PanelShellTestScope(
        textDirection: direction ?? TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: width,
            height: 480,
            child: StickersPage(host: host, source: source, assets: assets),
          ),
        ),
      );

  Future<void> pumpPage(WidgetTester tester, {double width = 360}) async {
    await tester.pumpWidget(page(width: width));
    await settle(tester);
  }

  Offset origin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(StickersPage));

  // The centre of the cell at [row], [column] of the first section, for
  // [columnWidth] wide columns.
  Offset cell(
    WidgetTester tester, {
    int row = 0,
    int column = 0,
    double columnWidth = 72,
  }) =>
      origin(tester) +
      Offset(columnWidth * (column + .5), 36 + 27 + 82 * row + 41);

  CatalogPageController controller() =>
      host.controllers.peek<CatalogPageController>('stickers')!;

  bool selected(WidgetTester tester, String label) =>
      tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData()
          .flagsCollection
          .isSelected ==
      Tristate.isTrue;

  pageTest('loads every pack as it comes near', (tester) async {
    await pumpPage(tester);

    expect(
      source.collections.value.first.contents,
      isA<CollectionContents$Loaded>(),
    );
  });

  group('with nothing to list', () {
    final empty = ChromeStringsPresets.english.panel.stickersEmpty;

    pageTest('says so once the recents are known to be empty and there is '
        'no pack', (tester) async {
      source.dispose();
      source = FakeCollectionSource([
        const FakeCollectionSpec(CollectionId.recent, pages: FakePages([[]])),
      ]);
      await pumpPage(tester);

      expect(find.text(empty), findsOneWidget);
    });

    pageTest('says nothing of it while there are recents', (tester) async {
      source.dispose();
      source = FakeCollectionSource([_recents()]);
      await pumpPage(tester);

      expect(find.text(empty), findsNothing);
    });

    pageTest('says nothing of it while there is a pack', (tester) async {
      await pumpPage(tester);

      expect(find.text(empty), findsNothing);
    });
  });

  group('the grid', () {
    pageTest('has as many 72 wide columns as the width holds', (tester) async {
      await pumpPage(tester);
      // 360 / 72 = 5 columns: the cell after the fifth is the next row's first.
      await tester.tapAt(cell(tester, column: 4));
      await tester.tapAt(cell(tester, row: 1));
      await tester.pump();

      expect(host.picks.map((pick) => pick.key), [
        const ContentKey.document('a-4'),
        const ContentKey.document('a-5'),
      ]);
    });

    pageTest('holds one more column when the width allows', (tester) async {
      await pumpPage(tester, width: 432);
      // 432 / 72 = 6 columns, 72 wide.
      await tester.tapAt(cell(tester, column: 5));
      await tester.pump();

      expect(host.picks.single.key, const ContentKey.document('a-5'));
    });

    pageTest('titles each section by its pack', (tester) async {
      await pumpPage(tester);

      expect(
        tester.getSemantics(find.byType(StickersPage)).getSemanticsData().label,
        isNotNull,
      );
      expect(find.bySemanticsLabel('Cats'), findsOneWidget);
      expect(find.bySemanticsLabel('Dogs'), findsOneWidget);
    });
  });

  group('picking', () {
    pageTest('a tap picks the sticker under its own kind, from the pack', (
      tester,
    ) async {
      await pumpPage(tester);

      await tester.tapAt(cell(tester, column: 1));
      await tester.pump();

      expect(host.picks, [
        (
          key: const ContentKey.document('a-1'),
          kind: SemanticKind.sticker,
          recentsKind: SemanticKind.sticker,
          source: PickSource.collection,
        ),
      ]);
    });

    pageTest('a tap in the recents picks it as a recent', (tester) async {
      source.dispose();
      source = FakeCollectionSource([_recents(), _pack('a', 'Cats')]);
      await pumpPage(tester);

      await tester.tapAt(cell(tester));
      await tester.pump();

      expect(host.picks.single.key, const ContentKey.document('a-3'));
      expect(host.picks.single.source, PickSource.recents);
    });

    pageTest('the recents have a clear button, which asks the host', (
      tester,
    ) async {
      source.dispose();
      source = FakeCollectionSource([_recents(), _pack('a', 'Cats')]);
      await pumpPage(tester);

      // The button is the last 48 px of the first header, under the strip.
      await tester.tapAt(origin(tester) + const Offset(360 - 24, 36 + 13.5));
      await tester.pump();

      expect(host.clearRecentsRequests, [SemanticKind.sticker]);
    });

    pageTest('no pack header has a clear button', (tester) async {
      await pumpPage(tester);

      await tester.tapAt(origin(tester) + const Offset(360 - 24, 36 + 13.5));
      await tester.pump();

      expect(host.clearRecentsRequests, isEmpty);
    });
  });

  group('the strip', () {
    pageTest('has a tab per pack, the first one active', (tester) async {
      await pumpPage(tester);

      expect(selected(tester, 'Cats'), isTrue);
      expect(find.bySemanticsLabel('Dogs'), findsWidgets);
      expect(find.bySemanticsLabel('Birds'), findsWidgets);
    });

    pageTest('a tap on a tab scrolls the grid to the head of the pack', (
      tester,
    ) async {
      await pumpPage(tester);

      // The strip's tabs are buttons; the header titles are not.
      await tester.tap(
        find.descendant(
          of: find.byType(StickerPackStrip),
          matching: find.bySemanticsLabel('Dogs'),
        ),
      );
      await settle(tester);

      // Cats: a header of 27 and 4 rows of 82 are above Dogs' header.
      expect(controller().catalog.offset, closeTo(27 + 4 * 82, 1));
      expect(selected(tester, 'Dogs'), isTrue);
    });

    pageTest('follows the grid as the user scrolls it', (tester) async {
      await pumpPage(tester);

      controller().catalog.jumpTo((27 + 4 * 82) * 2 + 10);
      await settle(tester);

      expect(selected(tester, 'Birds'), isTrue);
      expect(selected(tester, 'Cats'), isFalse);
    });

    pageTest('does not move the grid when the grid moved it', (tester) async {
      await pumpPage(tester);
      controller().catalog.jumpTo(27 + 4 * 82 + 10);
      await settle(tester);

      expect(controller().catalog.offset, closeTo(27 + 4 * 82 + 10, .5));
    });
  });

  group('a fresh open', () {
    double stripTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(StickerPackStrip)).dy - origin(tester).dy;

    // Reads on into the second pack until the strip has slid away, as a user
    // closing the panel there leaves it.
    Future<void> readOnUntilTheStripIsGone(WidgetTester tester) async {
      controller().catalog.jumpTo(27 + 4 * 82 + 100);
      await settle(tester);
      controller().catalog.scrollBy(80);
      await settle(tester);
      expect(stripTop(tester), lessThan(-StickerPackStrip.height + 1));
      expect(selected(tester, 'Dogs'), isTrue);
    }

    pageTest('brings the grid to its start, the strip back whole and the '
        'first tab marked', (tester) async {
      await pumpPage(tester);
      await readOnUntilTheStripIsGone(tester);

      host
        ..visible = false
        ..openAfresh()
        ..visible = true;
      await settle(tester);

      expect(controller().catalog.offset, 0);
      expect(stripTop(tester), 0);
      expect(selected(tester, 'Cats'), isTrue);
      expect(selected(tester, 'Dogs'), isFalse);
    });

    pageTest('marks the recents when the page has some', (tester) async {
      source.dispose();
      source = FakeCollectionSource([_recents(), _pack('a', 'Cats')]);
      await pumpPage(tester);
      controller().catalog.jumpTo(400);
      await settle(tester);

      host.openAfresh();
      await settle(tester);

      expect(controller().catalog.offset, 0);
      expect(
        selected(tester, ChromeStringsPresets.english.panel.recentlyUsedTitle),
        isTrue,
      );
    });

    pageTest('without one, a hide and a show keep the place', (tester) async {
      await pumpPage(tester);
      await readOnUntilTheStripIsGone(tester);
      final offset = controller().catalog.offset;

      host
        ..visible = false
        ..visible = true;
      await settle(tester);

      expect(controller().catalog.offset, offset);
      expect(stripTop(tester), lessThan(-StickerPackStrip.height + 1));
      expect(selected(tester, 'Dogs'), isTrue);
    });
  });

  group('right to left', () {
    pageTest('fills a row from the right, the first sticker at the start', (
      tester,
    ) async {
      await tester.pumpWidget(page(direction: TextDirection.rtl));
      await settle(tester);

      await tester.tapAt(origin(tester) + const Offset(360 - 36, 36 + 27 + 41));
      await tester.pump();

      expect(host.picks.single.key, const ContentKey.document('a-0'));
    });
  });
}
