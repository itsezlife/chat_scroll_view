/// The emoji page under a mouse: the right-click menu of the recents, the
/// press that opens the variant picker at once or after a hold, and the rules
/// of that picker while it is up.
///
/// **Seam:** [EmojiPage] under the pointer arrangement in an overlay, driven
/// by mouse [TestGesture]s (one pointer kind and button at a time) and
/// observed through the picks and requests a fake page host recorded, the
/// holds it counts, the preferences, and what is on screen. Geometry: the
/// page is 360 x 480 with its strip at the bottom, so the first cell of the
/// first section is 5 + 21.875 across and 27 + 22.5 down from the page's top
/// left; sections here are one row of 72 (27 header + 45 row) each.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

import 'emoji_fixtures.dart' as fixtures;

const _hold = Duration(milliseconds: 500);
const _settle = Duration(milliseconds: 400);

void main() {
  late FakeCollectionSource source;
  late FakeSearchSource search;
  late FakePreferenceStore preferences;
  late FakePanelPageHost host;
  late AssetCacheScope assets;
  final strings = ChromeStringsPresets.english.panel;
  final mice = <TestGesture>[];

  tearDown(() async {
    for (final mouse in mice) {
      await mouse.removePointer();
    }
    mice.clear();
  });

  setUp(() {
    search = FakeSearchSource({});
    preferences = FakePreferenceStore();
    host = FakePanelPageHost(pageId: 'emoji');
    assets = PageAssets.createScope();
    addTearDown(() {
      source.dispose();
      search.dispose();
      preferences.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  // Recents: 😀 then 👍. Then the smileys (😀 ❤), the people (👍 🕵 💑), ...
  Future<void> pumpPage(
    WidgetTester tester, {
    PanelArrangement arrangement = PanelArrangement.pointer,
    List<String> recents = const ['😀', '👍'],
    TextDirection direction = TextDirection.ltr,
  }) async {
    source = fixtures.source(recents: recents, count: 0);
    await tester.pumpWidget(
      PanelShellTestScope(
        textDirection: direction,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => PanelArrangementScope(
                arrangement: arrangement,
                child: Center(
                  child: SizedBox(
                    width: 360,
                    height: 480,
                    child: EmojiPage(
                      host: host,
                      source: source,
                      searchSource: search,
                      preferences: preferences,
                      entryOf: fixtures.entryOf,
                      assets: assets,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Offset origin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(EmojiPage));

  // The centre of the cell at [row], [column] of the section whose header is
  // [top] below the page's top.
  Offset cell(
    WidgetTester tester, {
    required double top,
    int row = 0,
    int column = 0,
  }) =>
      origin(tester) +
      Offset(5 + 43.75 * (column + 0.5), top + 27 + 45 * row + 22.5);

  const recents0 = 0.0; // 😀 (column 0) and 👍 (column 1)
  const smileys = 72.0; // 😀 (column 0), ❤ (column 1)
  const people = 144.0; // 👍 (column 0), 🕵, 💑

  // One mouse is one device with one button state: a test that clicks with
  // both buttons takes the first away before the second comes.
  Future<TestGesture> mouse(
    WidgetTester tester, {
    int buttons = kPrimaryMouseButton,
  }) async {
    for (final old in mice) {
      await old.removePointer();
    }
    mice.clear();
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    await gesture.addPointer(location: const Offset(10, 10));
    mice.add(gesture);
    return gesture;
  }

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    final gesture = await mouse(tester, buttons: kSecondaryMouseButton);
    await gesture.down(at);
    await gesture.up();
    await tester.pump();
  }

  Finder picker() => find.byType(EmojiVariantPicker);
  Finder menu() => find.byType(CatalogContextMenuPanel);

  // The centre of option [index] of the open picker, in the grid's cell.
  Offset optionCenter(WidgetTester tester, int index, {int count = 6}) {
    final outer = tester.getTopLeft(picker());
    final layout = EmojiVariantPickerLayout(
      count: count,
      cell: const Size(43.75, 45),
    );
    return outer +
        const Offset(
          EmojiVariantPickerLayout.shadowMargin,
          EmojiVariantPickerLayout.shadowMargin,
        ) +
        layout.optionRect(index).center;
  }

  Rect cardOf(WidgetTester tester) =>
      tester.getRect(picker()).deflate(EmojiVariantPickerLayout.shadowMargin);

  group('the right-click menu', () {
    testWidgets('on a recent emoji lists copy, remove, clear, in that order', (
      tester,
    ) async {
      await pumpPage(tester);

      await rightClick(tester, cell(tester, top: recents0));

      expect(menu(), findsOneWidget);
      final copy = tester.getTopLeft(find.text(strings.copyAction));
      final remove = tester.getTopLeft(find.text(strings.removeRecentAction));
      final clear = tester.getTopLeft(find.text(strings.clearRecentAction));
      expect(copy.dy, lessThan(remove.dy));
      expect(remove.dy, lessThan(clear.dy));
      expect(
        tester.getTopLeft(menu()).dx,
        closeTo(cell(tester, top: recents0).dx, 0.01),
        reason: 'opens at the pointer',
      );
    });

    testWidgets('does not pick, press or open a picker', (tester) async {
      await pumpPage(tester);

      final gesture = await mouse(tester, buttons: kSecondaryMouseButton);
      await gesture.down(cell(tester, top: recents0, column: 1));
      await tester.pump(_hold + _settle);
      await gesture.up();
      await tester.pump();

      expect(host.picks, isEmpty);
      expect(picker(), findsNothing);
      expect(menu(), findsOneWidget);
    });

    testWidgets('on a cell outside the recents opens nothing and does '
        'nothing', (tester) async {
      await pumpPage(tester);

      await rightClick(tester, cell(tester, top: smileys));

      expect(menu(), findsNothing);
      expect(host.picks, isEmpty);
      expect(host.holdsTaken, 0);
    });

    testWidgets('on the empty part of the page opens nothing', (tester) async {
      await pumpPage(tester);

      await rightClick(tester, origin(tester) + const Offset(100, 400));

      expect(menu(), findsNothing);
    });

    testWidgets('under a finger\'s arrangement opens nothing', (tester) async {
      await pumpPage(tester, arrangement: PanelArrangement.touch);

      await rightClick(tester, cell(tester, top: recents0));

      expect(menu(), findsNothing);
    });

    testWidgets('copy asks the host to copy that emoji and closes', (
      tester,
    ) async {
      await pumpPage(tester);
      await rightClick(tester, cell(tester, top: recents0, column: 1));

      await tester.tap(find.text(strings.copyAction));
      await tester.pump();

      expect(host.copyRequests, [
        (key: fixtures.key('👍'), kind: SemanticKind.unicodeEmoji),
      ]);
      expect(menu(), findsNothing);
      expect(host.picks, isEmpty);
    });

    testWidgets('remove asks the host to forget that emoji in the recents', (
      tester,
    ) async {
      await pumpPage(tester);
      await rightClick(tester, cell(tester, top: recents0));

      await tester.tap(find.text(strings.removeRecentAction));
      await tester.pump();

      expect(host.removeRecentRequests, [
        (key: fixtures.key('😀'), kind: SemanticKind.unicodeEmoji),
      ]);
    });

    testWidgets('clear asks the host to clear the emoji recents', (
      tester,
    ) async {
      await pumpPage(tester);
      await rightClick(tester, cell(tester, top: recents0));

      await tester.tap(find.text(strings.clearRecentAction));
      await tester.pump();

      expect(host.clearRecentsRequests, [SemanticKind.unicodeEmoji]);
    });

    testWidgets('holds auto-hide while it is open', (tester) async {
      await pumpPage(tester);

      await rightClick(tester, cell(tester, top: recents0));
      expect(host.activeHolds, 1);

      await tester.tapAt(origin(tester) + const Offset(300, 400));
      await tester.pump();

      expect(menu(), findsNothing);
      expect(host.activeHolds, 0);
    });

    testWidgets('a click that closes it picks nothing', (tester) async {
      await pumpPage(tester);
      await rightClick(tester, cell(tester, top: recents0));

      await tester.tapAt(cell(tester, top: smileys, column: 1));
      await tester.pump();

      expect(menu(), findsNothing);
      expect(host.picks, isEmpty);
    });
  });

  group('a mouse press on an emoji with variants', () {
    testWidgets('opens the picker at once when no variant was ever chosen', (
      tester,
    ) async {
      await pumpPage(tester);

      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(Duration.zero);

      expect(picker(), findsOneWidget);
      expect(host.activeHolds, 1, reason: 'the picker holds auto-hide');
      expect(host.picks, isEmpty);
      await gesture.up();
    });

    testWidgets('the picker has the base and the five tones, in the grid\'s '
        'cell, with a separator after the first', (tester) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_settle);

      final widget = tester.widget<EmojiVariantPicker>(picker());
      expect(widget.options, [
        fixtures.thumbsUp.base,
        for (final v in fixtures.thumbsUp.variants) v.key,
      ]);
      expect(widget.cell, const Size(43.75, 45));
      final card = cardOf(tester);
      expect(card.width, 4 * 8 + 1 + 6 * 43.75);
      expect(card.height, 2 * 8 + 45);
      expect(tester.getSize(picker()), Size(card.width + 20, card.height + 20));
      await gesture.up();
    });

    testWidgets('nothing is highlighted until the mouse is over an option, '
        'and the cell stays pinned meanwhile', (tester) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_settle);

      expect(tester.widget<EmojiVariantPicker>(picker()).selected, isNull);
      expect(
        tester
            .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport))
            .pinnedLeaf
            ?.index,
        0,
      );

      await gesture.moveTo(optionCenter(tester, 2));
      await tester.pump();
      expect(tester.widget<EmojiVariantPicker>(picker()).selected, 2);

      await gesture.moveTo(origin(tester) + const Offset(300, 300));
      await tester.pump();
      expect(tester.widget<EmojiVariantPicker>(picker()).selected, isNull);
      await gesture.up();
    });

    testWidgets('releasing over an option picks it, remembers it and closes', (
      tester,
    ) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_settle);

      await gesture.moveTo(optionCenter(tester, 4));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final chosen = fixtures.thumbsUp.variants[3].key;
      expect(host.picks.single.key, chosen);
      expect(preferences.preferredVariant(fixtures.thumbsUp.base), chosen);
      expect(picker(), findsNothing);
      expect(host.activeHolds, 0);
      expect(
        tester
            .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport))
            .pinnedLeaf,
        isNull,
      );
    });

    testWidgets('releasing outside the picker the first time leaves it open '
        'until the next click', (tester) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_settle);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(picker(), findsOneWidget);
      expect(host.picks, isEmpty, reason: 'the release is not a click');
      expect(host.activeHolds, 1);

      // A click on an option now picks it.
      await tester.tapAt(optionCenter(tester, 1));
      await tester.pumpAndSettle();
      expect(host.picks.single.key, fixtures.thumbsUp.variants.first.key);
      expect(picker(), findsNothing);
      expect(host.activeHolds, 0);
    });

    testWidgets('a click elsewhere closes it and is swallowed', (tester) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_settle);
      await gesture.up();
      await tester.pumpAndSettle();

      // Beside the card, over the page: a cell that was not the picker's.
      await tester.tapAt(origin(tester) + const Offset(340, 60));
      await tester.pumpAndSettle();

      expect(picker(), findsNothing);
      expect(host.picks, isEmpty);
      expect(host.activeHolds, 0);
    });

    testWidgets('a right click closes it too, and opens no menu', (
      tester,
    ) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_settle);
      await gesture.up();
      await tester.pumpAndSettle();

      await rightClick(tester, cell(tester, top: recents0));
      await tester.pumpAndSettle();

      expect(picker(), findsNothing);
      expect(menu(), findsNothing);
    });

    testWidgets('the wheel does not scroll the grid while it is open', (
      tester,
    ) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_settle);
      await gesture.up();
      await tester.pumpAndSettle();
      final controller = host.controllers.peek<EmojiPageController>('emoji')!;

      final wheel = TestPointer(7, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(cell(tester, top: smileys)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 90)));
      await tester.pump();

      expect(controller.catalog.offset, 0);
    });

    testWidgets('after a variant was chosen the picker waits for the '
        'hold, and a quick click picks the emoji as the grid shows it', (
      tester,
    ) async {
      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.variants[1].key,
      );
      await pumpPage(tester);
      final gesture = await mouse(tester);

      await gesture.down(cell(tester, top: people));
      await tester.pump(const Duration(milliseconds: 300));
      expect(picker(), findsNothing);
      await gesture.up();
      await tester.pump();

      expect(picker(), findsNothing);
      expect(host.picks.single.key, fixtures.thumbsUp.base);
    });

    testWidgets('after a variant was chosen the picker opens after 500 ms, '
        'and a release outside closes it without picking', (tester) async {
      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.variants[1].key,
      );
      await pumpPage(tester);
      final gesture = await mouse(tester);

      await gesture.down(cell(tester, top: people));
      await tester.pump(const Duration(milliseconds: 450));
      expect(picker(), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(picker(), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(picker(), findsNothing);
      expect(host.picks, isEmpty);
      expect(host.activeHolds, 0);
    });

    testWidgets('after a variant was chosen, releasing over an option '
        'picks it', (tester) async {
      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.variants[1].key,
      );
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_hold + _settle);

      await gesture.moveTo(optionCenter(tester, 5));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(host.picks.single.key, fixtures.thumbsUp.variants[4].key);
    });

    testWidgets('choosing the base is remembered, so the next press holds', (
      tester,
    ) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_settle);
      await gesture.moveTo(optionCenter(tester, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.picks.single.key, fixtures.thumbsUp.base);

      await gesture.down(cell(tester, top: people));
      await tester.pump(const Duration(milliseconds: 100));

      expect(picker(), findsNothing, reason: 'a variant was chosen: it holds');
      await gesture.up();
    });

    testWidgets('an emoji without variants stays a plain click', (
      tester,
    ) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);

      await gesture.down(cell(tester, top: smileys, column: 1));
      await tester.pump(_hold + _settle);
      await gesture.up();
      await tester.pump();

      expect(picker(), findsNothing);
      expect(host.picks.single.key, fixtures.key('❤'));
    });

    testWidgets('the recents hold even before any choice: the cell is the '
        'exact emoji used', (tester) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);

      await gesture.down(cell(tester, top: recents0, column: 1));
      await tester.pump(const Duration(milliseconds: 100));

      expect(picker(), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(host.picks.single.source, PickSource.recents);
    });
  });

  group('a finger', () {
    testWidgets('keeps the platform delay and releases anywhere on the '
        'nearest option', (tester) async {
      await pumpPage(tester, arrangement: PanelArrangement.touch);

      // The strip is on top for a finger: 36 px more above the grid.
      final touch = await tester.startGesture(
        cell(tester, top: people) + const Offset(0, 36),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(picker(), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(picker(), findsOneWidget);
      expect(tester.widget<EmojiVariantPicker>(picker()).selected, 0);

      // Far to the right of the card, level with it: the last option.
      await touch.moveTo(
        Offset(tester.getRect(picker()).right + 60, cardOf(tester).center.dy),
      );
      await tester.pump();
      expect(tester.widget<EmojiVariantPicker>(picker()).selected, 5);
      await touch.up();
      await tester.pumpAndSettle();

      expect(host.picks.single.key, fixtures.thumbsUp.variants.last.key);
    });
  });

  group('where the picker is', () {
    testWidgets('above the cell with a 2 px gap', (tester) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      // The people row: far enough down for the card to fit above.
      final at = cell(tester, top: people);
      await gesture.down(at);
      await tester.pump(_settle);

      final card = cardOf(tester);
      final cellRect = Rect.fromCenter(center: at, width: 43.75, height: 45);
      expect(card.bottom, cellRect.top - 2);
      await gesture.up();
    });

    testWidgets('flips below the cell where it would cross the top edge', (
      tester,
    ) async {
      await pumpPage(tester, recents: ['👍']);
      final gesture = await mouse(tester);
      // 👍 is in the first recents row, 27 under the page's top.
      final at = cell(tester, top: recents0);
      await gesture.down(at);
      await tester.pump(_hold + _settle);

      final card = cardOf(tester);
      final cellRect = Rect.fromCenter(center: at, width: 43.75, height: 45);
      expect(card.top, cellRect.bottom + 2);
      await gesture.up();
    });

    testWidgets('slides with the column: left over the first, right over the '
        'last, inside the page', (tester) async {
      await pumpPage(
        tester,
        recents: ['👍', '😀', '😀', '😀', '😀', '😀', '😀', '👍'],
      );
      final page = tester.getRect(find.byType(EmojiPage));
      final gesture = await mouse(tester);

      await gesture.down(cell(tester, top: people));
      await tester.pump(_settle);
      expect(cardOf(tester).left, closeTo(page.left + 10, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tapAt(page.center);
      await tester.pumpAndSettle();

      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.variants.first.key,
      );
      await gesture.down(cell(tester, top: recents0, column: 7));
      await tester.pump(_hold + _settle);
      expect(cardOf(tester).right, closeTo(page.right - 10, 0.01));
      await gesture.up();
    });
  });

  testWidgets('the picker and the menu open in a right-to-left page too, '
      'with the options in the page\'s order', (tester) async {
    await pumpPage(tester, direction: TextDirection.rtl);
    final page = tester.getRect(find.byType(EmojiPage));
    // The first recent is the first cell from the right.
    final first = Offset(page.right - 5 - 21.875, page.top + 27 + 22.5);

    await rightClick(tester, first);

    expect(menu(), findsOneWidget);
    expect(host.removeRecentRequests, isEmpty);
    await tester.tap(find.text(strings.removeRecentAction));
    await tester.pump();
    expect(host.removeRecentRequests.single.key, fixtures.key('😀'));
  });
}
