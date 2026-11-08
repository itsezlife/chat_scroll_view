/// The GIF page as a user and the shell see it.
///
/// **Seam:** [GifPage] mounted under the chrome scopes with a fake source, a
/// fake page host and a real asset scope, observed through the picks,
/// requests and scroll reports the host received, what is tappable where, and
/// the semantics of the cells. Geometry: a 400 x 480 page; square clips are
/// 25 spans (100 px) each, so four to a row of 100 px under a 2 px gap, and
/// the first cell's centre is (49, 2 + 50).
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart' show isTest;
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

CollectionItem _gif(String id, {int width = 128, int height = 128}) =>
    CollectionItem.described(
      ContentDescriptor(
        key: ContentKey.document(id),
        semanticKind: SemanticKind.gif,
        mediaForm: MediaForm.video,
        animated: true,
        size: ContentSize(width, height),
        spokenName: 'gif $id',
      ),
    );

FakeCollectionSpec _clips(
  String id,
  String title, {
  int count = 8,
  int width = 128,
  int height = 128,
}) => FakeCollectionSpec(
  CollectionId.set(id),
  metadata: CollectionMetadata(title: title),
  pages: FakePages([
    [
      for (var i = 0; i < count; i++)
        _gif('$id-$i', width: width, height: height),
    ],
  ]),
);

FakeCollectionSpec _recents() => FakeCollectionSpec(
  CollectionId.recent,
  pages: FakePages([
    [_gif('a-3'), _gif('b-1')],
  ]),
);

// A widget test with semantics on, which the cells are found by; the handle
// must be released before the test ends.
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

// The clips are never decoded here, so their stand-ins shimmer for good and
// the page never settles: run the clock for a while instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakePanelPageHost host;
  late AssetCacheScope assets;
  late FakeCollectionSource source;

  setUp(() {
    host = FakePanelPageHost(pageId: 'gif');
    assets = PageAssets.createScope();
    source = FakeCollectionSource([_clips('a', 'Cats'), _clips('b', 'Dogs')]);
    addTearDown(() {
      source.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  Widget page({TextDirection direction = TextDirection.ltr}) =>
      PanelShellTestScope(
        textDirection: direction,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 480,
            child: GifPage(host: host, source: source, assets: assets),
          ),
        ),
      );

  Future<void> pumpPage(
    WidgetTester tester, {
    TextDirection direction = TextDirection.ltr,
  }) async {
    await tester.pumpWidget(page(direction: direction));
    await settle(tester);
  }

  Offset origin(WidgetTester tester) => tester.getTopLeft(find.byType(GifPage));

  // The centre of the square clip at [column] of [row] of the first section.
  Offset cell(WidgetTester tester, {int row = 0, int column = 0}) =>
      origin(tester) + Offset(100 * column + 49, 102 * row + 2 + 50);

  pageTest('loads every collection of the source', (tester) async {
    await pumpPage(tester);

    for (final collection in source.collections.value) {
      expect(collection.contents, isA<CollectionContents$Loaded>());
    }
  });

  group('the rows', () {
    pageTest('put four square clips in a row of 100', (tester) async {
      await pumpPage(tester);

      await tester.tapAt(cell(tester, column: 3));
      await tester.tapAt(cell(tester, row: 1));
      await tester.pump();

      expect(host.picks.map((pick) => pick.key), [
        const ContentKey.document('a-3'),
        const ContentKey.document('a-4'),
      ]);
    });

    pageTest('give a wide clip more of the row', (tester) async {
      source.dispose();
      source = FakeCollectionSource([
        FakeCollectionSpec(
          const CollectionId.set('a'),
          pages: FakePages([
            [
              _gif('wide-0', width: 1600, height: 900),
              _gif('wide-1', width: 1600, height: 900),
              _gif('wide-2', width: 1600, height: 900),
            ],
          ]),
        ),
      ]);
      await pumpPage(tester);

      // Two wide clips share the row, 200 px each; the third is a row to
      // itself.
      await tester.tapAt(origin(tester) + const Offset(250, 52));
      await tester.tapAt(origin(tester) + const Offset(200, 102 + 52));
      await tester.pump();

      expect(host.picks.map((pick) => pick.key), [
        const ContentKey.document('wide-1'),
        const ContentKey.document('wide-2'),
      ]);
    });

    pageTest('start at the right under right-to-left', (tester) async {
      await pumpPage(tester, direction: TextDirection.rtl);

      await tester.tapAt(origin(tester) + const Offset(400 - 49, 52));
      await tester.pump();

      expect(host.picks.single.key, const ContentKey.document('a-0'));
    });
  });

  group('the sections', () {
    pageTest('head every section but the first with its title', (tester) async {
      source.dispose();
      source = FakeCollectionSource([_recents(), _clips('a', 'Featured')]);
      await pumpPage(tester);

      expect(find.bySemanticsLabel('Featured'), findsOneWidget);
      expect(find.bySemanticsLabel('Recently used'), findsNothing);
    });

    pageTest('do not head the first section, whatever it is called', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(find.bySemanticsLabel('Cats'), findsNothing);
    });

    pageTest('hide the recents while they are known to be empty', (
      tester,
    ) async {
      source.dispose();
      source = FakeCollectionSource([
        const FakeCollectionSpec(CollectionId.recent, pages: FakePages([[]])),
        _clips('a', 'Featured'),
      ]);
      await pumpPage(tester);

      await tester.tapAt(cell(tester));
      await tester.pump();

      expect(host.picks.single.key, const ContentKey.document('a-0'));
    });
  });

  group('with nothing to list', () {
    final empty = ChromeStringsPresets.english.panel.gifsEmpty;

    pageTest('says so once the recents are known to be empty and nothing '
        'else is listed', (tester) async {
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

    pageTest('says nothing of it while a collection is still loading', (
      tester,
    ) async {
      source.dispose();
      source = FakeCollectionSource([
        const FakeCollectionSpec(CollectionId.recent, pages: FakePages([[]])),
        _clips('t', 'Trending'),
      ])..pause();
      await pumpPage(tester);

      expect(find.text(empty), findsNothing);
      source.resume();
    });

    pageTest('says the load failed, not that there is nothing, when one did', (
      tester,
    ) async {
      source.dispose();
      source = FakeCollectionSource([
        const FakeCollectionSpec(CollectionId.recent, pages: FakePages([[]])),
        _clips('t', 'Trending'),
      ])..failLoads = true;
      await pumpPage(tester);

      expect(find.text(empty), findsNothing);
      expect(
        find.text(ChromeStringsPresets.english.panel.gifsFailed),
        findsOneWidget,
      );
    });
  });

  group('picking', () {
    pageTest('a tap picks the clip under its own kind, from the section', (
      tester,
    ) async {
      await pumpPage(tester);

      await tester.tapAt(cell(tester, column: 1));
      await tester.pump();

      expect(host.picks, [
        (
          key: const ContentKey.document('a-1'),
          kind: SemanticKind.gif,
          recentsKind: SemanticKind.gif,
          source: PickSource.collection,
        ),
      ]);
    });

    pageTest('a tap in the recents picks it as a recent', (tester) async {
      source.dispose();
      source = FakeCollectionSource([_recents(), _clips('a', 'Featured')]);
      await pumpPage(tester);

      await tester.tapAt(cell(tester));
      await tester.pump();

      expect(host.picks.single.key, const ContentKey.document('a-3'));
      expect(host.picks.single.source, PickSource.recents);
    });

    pageTest('a cell is a button named for its clip', (tester) async {
      await pumpPage(tester);

      final data = tester
          .getSemantics(find.bySemanticsLabel('gif a-0'))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    });
  });

  group('reporting to the shell', () {
    pageTest('says a drag is a drag and the rest is idle', (tester) async {
      source.dispose();
      source = FakeCollectionSource([_clips('a', 'Cats', count: 80)]);
      await pumpPage(tester);

      await tester.drag(find.byType(GifPage), const Offset(0, -150));
      await settle(tester);

      expect(
        host.scrollActivity.whereType<PageScrollDrag>().map((a) => a.delta),
        everyElement(greaterThan(0)),
      );
      expect(host.scrollActivity.whereType<PageScrollDrag>(), isNotEmpty);
      expect(host.scrollActivity.last, isA<PageScrollIdle>());
    });

    // The reference client brings its bottom tabs back at rest at an end of
    // the emoji grid only; over GIFs only reading back shows them.
    pageTest('never says it rests at an end', (tester) async {
      source.dispose();
      source = FakeCollectionSource([_clips('a', 'Cats', count: 80)]);
      await pumpPage(tester);

      await tester.drag(find.byType(GifPage), const Offset(0, -5000));
      await settle(tester);
      await tester.drag(find.byType(GifPage), const Offset(0, 5000));
      await settle(tester);

      final rests = host.scrollActivity.whereType<PageScrollIdle>();
      expect(rests, isNotEmpty);
      expect(rests.map((rest) => rest.atEdge), everyElement(isFalse));
    });
  });

  group('its place', () {
    double offset(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(GifPage),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;

    pageTest('is kept when the page is built again', (tester) async {
      source.dispose();
      source = FakeCollectionSource([_clips('a', 'Cats', count: 80)]);
      await pumpPage(tester);
      await tester.drag(find.byType(GifPage), const Offset(0, -300));
      await settle(tester);
      final left = offset(tester);
      expect(left, greaterThan(0));

      // Off screen, as the pager drops a page another tab replaced.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpPage(tester);

      expect(offset(tester), left);
    });

    pageTest('goes back to the start when its tab is chosen again', (
      tester,
    ) async {
      source.dispose();
      source = FakeCollectionSource([_clips('a', 'Cats', count: 80)]);
      await pumpPage(tester);
      await tester.drag(find.byType(GifPage), const Offset(0, -300));
      await settle(tester);

      host.reselect();
      await settle(tester);

      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(GifPage),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.pixels, 0);
    });
  });

  group('playback', () {
    pageTest('mounts only the rows in view, so only they play', (tester) async {
      source.dispose();
      source = FakeCollectionSource([_clips('a', 'Cats', count: 80)]);
      await pumpPage(tester);

      // 480 px shows five rows of 102 (partly); 20 rows are laid out in all.
      expect(find.byType(ContentView).evaluate().length, lessThan(30));
    });
  });

  group('a cell that waits for its clip', () {
    // The painting box inside the view's repaint boundary.
    RenderObject boxOf(WidgetTester tester) => tester.renderObject(
      find.descendant(
        of: find.byType(ContentView).first,
        matching: find.byWidgetPredicate((w) => w is LeafRenderObjectWidget),
      ),
    );

    pageTest('is the clip\'s rectangle in a quiet token, not a circle', (
      tester,
    ) async {
      await pumpPage(tester);

      final view = find.byType(ContentView).first;
      final skeleton = ChromeThemeScope.of(
        tester.element(view),
      ).placeholder.skeleton;
      // A square clip of 25 spans is a 98 x 100 cell (the gap is after it): drawn whole from the
      // first frame, so the thumbnail that arrives changes no bounds.
      expect(
        tester.renderObject(view),
        paints..rect(rect: const Rect.fromLTWH(0, 0, 98, 100), color: skeleton),
      );
      expect(tester.renderObject(view), isNot(paints..path()));
    });

    pageTest('has the radial progress over its centre', (tester) async {
      await pumpPage(tester);

      expect(boxOf(tester), paints..circle(x: 49, y: 50, radius: 12));
    });

    pageTest('fills its cell with the clip, cropping the overflow', (
      tester,
    ) async {
      await pumpPage(tester);

      final view = tester.widget<ContentView>(find.byType(ContentView).first);

      expect(view.preset.profile.fit, AssetFit.cover);
      expect(view.preset.profile.animate, isTrue);
    });
  });
}
