/// The emoji page under a mouse: the right-click menu of the recents, the
/// press that opens the variant picker after a hold, and the rules
/// of that picker while it is up.
///
/// **Seam:** [EmojiPage] under the pointer arrangement in an overlay, driven
/// by mouse [TestGesture]s (one pointer kind and button at a time) and
/// observed through the picks and requests a fake page host recorded, the
/// holds it counts, the preferences, and what is on screen. Geometry: the
/// page is 360 x 480 with its strip at the bottom, so the first cell of the
/// page is the reference desktop client's grid at 360 wide: nine columns of
/// 38 x 36 from 11 across (8 padding and half the 6 px the columns leave), so
/// the first cell's centre is 11 + 19 across and 27 + 18 down from the page's
/// top left; sections here are one row of 63 (27 header + 36 row) each.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
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

// The pointer grid at the page's 360 px (see the library comment).
const _cellWidth = 38.0;
const _cellHeight = 36.0;
const _x0 = 11.0;
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
    int count = 0,
    double width = 360,
  }) async {
    source = fixtures.source(recents: recents, count: count);
    await tester.pumpWidget(
      PanelShellTestScope(
        textDirection: direction,
        child: FakeSearchFieldScope(
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => PanelArrangementScope(
                  arrangement: arrangement,
                  child: Center(
                    child: SizedBox(
                      width: width,
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
      ),
    );
    await tester.pumpAndSettle();
  }

  Offset origin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(EmojiPage));

  // The centre of the cell at [row], [column] of the section whose header is
  // [top] below the content's start: the page's top under the pointer
  // arrangement, below whatever the page pins over the grid (the strip, the
  // search field) under touch, which the viewport's padding makes room for.
  Offset cell(
    WidgetTester tester, {
    required double top,
    int row = 0,
    int column = 0,
  }) {
    final viewport = tester.widget<PanelCatalogViewport>(
      find.byType(PanelCatalogViewport),
    );
    return tester.getTopLeft(find.byType(PanelCatalogViewport)) +
        Offset(
          _x0 + _cellWidth * (column + 0.5),
          viewport.padding.top + top + 27 + _cellHeight * (row + 0.5),
        );
  }

  const recents0 = 0.0; // 😀 (column 0) and 👍 (column 1)
  const smileys = 27 + _cellHeight; // 😀 (column 0), ❤ (column 1)
  const people = 2 * (27 + _cellHeight); // 👍 (column 0), 🕵, 💑

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
      cell: const Size(_cellWidth, _cellHeight),
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
    testWidgets('a quick click inserts the emoji as the grid shows it, before '
        'any variant was chosen too: the picker needs a hold', (tester) async {
      await pumpPage(tester);

      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(const Duration(milliseconds: 100));
      expect(picker(), findsNothing);
      await gesture.up();
      await tester.pump();

      expect(picker(), findsNothing);
      expect(host.picks.single.key, fixtures.thumbsUp.base);
    });

    testWidgets('a 500 ms hold opens the picker, before any variant was chosen '
        'too', (tester) async {
      await pumpPage(tester);

      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(const Duration(milliseconds: 450));
      expect(picker(), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));

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
      await tester.pump(_hold + _settle);

      final widget = tester.widget<EmojiVariantPicker>(picker());
      expect(widget.options, [
        fixtures.thumbsUp.base,
        for (final v in fixtures.thumbsUp.variants) v.key,
      ]);
      expect(widget.cell, const Size(_cellWidth, _cellHeight));
      final card = cardOf(tester);
      expect(card.width, 4 * 8 + 1 + 6 * _cellWidth);
      expect(card.height, 2 * 8 + _cellHeight);
      expect(tester.getSize(picker()), Size(card.width + 20, card.height + 20));
      await gesture.up();
    });

    testWidgets('nothing is highlighted until the mouse is over an option, '
        'and the cell stays pinned meanwhile', (tester) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_hold + _settle);

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

    testWidgets('the option under the mouse gets the grid\'s 34 x 32 hover '
        'box, centred', (tester) async {
      // 345 px: cells of 37 x 35, which an inset of 2 would not make 34 x 32.
      await pumpPage(tester, width: 345);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_hold + _settle);
      final option =
          tester.getTopLeft(picker()) +
          const Offset(
            EmojiVariantPickerLayout.shadowMargin,
            EmojiVariantPickerLayout.shadowMargin,
          ) +
          EmojiVariantPickerLayout(
            count: 6,
            cell: tester.widget<EmojiVariantPicker>(picker()).cell,
          ).optionRect(2).center;
      expect(
        tester.widget<EmojiVariantPicker>(picker()).cell,
        const Size(37, 35),
      );

      await gesture.moveTo(option);
      await tester.pump();

      final wash = ChromeCatalogTheme.hoverWashOf(
        ChromeThemeScope.paletteOf(tester.element(picker())),
      );
      final box = find.descendant(
        of: picker(),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == wash,
        ),
      );
      expect(tester.getSize(box), const Size(34, 32));
      expect(tester.getCenter(box), option);
      await gesture.up();
    });

    testWidgets('releasing over an option picks it, remembers it and closes', (
      tester,
    ) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_hold + _settle);

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

    testWidgets('the wheel does not scroll the grid while it is open', (
      tester,
    ) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_hold + _settle);
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

    testWidgets('choosing the base is remembered as a choice', (tester) async {
      await pumpPage(tester);
      final gesture = await mouse(tester);
      await gesture.down(cell(tester, top: people));
      await tester.pump(_hold + _settle);
      await gesture.moveTo(optionCenter(tester, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.picks.single.key, fixtures.thumbsUp.base);
      expect(
        preferences.preferredVariant(fixtures.thumbsUp.base),
        fixtures.thumbsUp.base,
      );
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
    testWidgets('keeps the platform delay, gets the mobile picker and '
        'releases anywhere on the nearest option', (tester) async {
      await pumpPage(tester, arrangement: PanelArrangement.touch);

      final touch = await tester.startGesture(cell(tester, top: people));
      await tester.pump(const Duration(milliseconds: 300));
      final tones = find.byType(EmojiTonePicker);
      expect(tones, findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      // A finger gets the mobile picker, whatever the arrangement.
      expect(tones, findsOneWidget);
      expect(tester.widget<EmojiTonePicker>(tones).marked, 0);

      // Far to the right of the card, level with it: the last option.
      await touch.moveTo(
        Offset(tester.getRect(tones).right + 60, tester.getCenter(tones).dy),
      );
      await tester.pump();
      expect(tester.widget<EmojiTonePicker>(tones).marked, 5);
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
      await tester.pump(_hold + _settle);

      final card = cardOf(tester);
      final cellRect = Rect.fromCenter(
        center: at,
        width: _cellWidth,
        height: _cellHeight,
      );
      expect(card.bottom, cellRect.top - 2);
      await gesture.up();
    });

    testWidgets('flips below the cell where it would cross the top edge', (
      tester,
    ) async {
      await pumpPage(tester, recents: ['👍'], count: 40);
      final gesture = await mouse(tester);
      // The search field is the first thing in the content; scrolled past, 👍
      // in the first recents row is 27 under the page's top.
      host.controllers.peek<CatalogPageController>('emoji')!.catalog.jumpTo(50);
      await tester.pump();
      final at = cell(tester, top: recents0) - const Offset(0, 50);
      await gesture.down(at);
      await tester.pump(_hold + _settle);

      final card = cardOf(tester);
      final cellRect = Rect.fromCenter(
        center: at,
        width: _cellWidth,
        height: _cellHeight,
      );
      expect(card.top, cellRect.bottom + 2);
      await gesture.up();
    });

    testWidgets('slides with the column: left over the first, right over the '
        'last, inside the page', (tester) async {
      await pumpPage(
        tester,
        recents: ['👍', '😀', '😀', '😀', '😀', '😀', '😀', '😀', '👍'],
      );
      final page = tester.getRect(find.byType(EmojiPage));
      final gesture = await mouse(tester);

      await gesture.down(cell(tester, top: people));
      await tester.pump(_hold + _settle);
      expect(cardOf(tester).left, closeTo(page.left + 10, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tapAt(page.center);
      await tester.pumpAndSettle();

      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.variants.first.key,
      );
      await gesture.down(cell(tester, top: recents0, column: 8));
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
    // The columns end 7 short of the right (4 padding and the other half of
    // what they leave).
    final first = Offset(
      page.right - 7 - _cellWidth / 2,
      cell(tester, top: recents0).dy,
    );

    await rightClick(tester, first);

    expect(menu(), findsOneWidget);
    expect(host.removeRecentRequests, isEmpty);
    await tester.tap(find.text(strings.removeRecentAction));
    await tester.pump();
    expect(host.removeRecentRequests.single.key, fixtures.key('😀'));
  });

  testWidgets('the picker draws its emoji the size the grid does', (
    tester,
  ) async {
    await pumpPage(tester);

    final gesture = await mouse(tester);
    await gesture.down(cell(tester, top: people));
    await tester.pump(_hold + _settle);

    final sizes = {
      for (final text in tester.widgetList<Text>(
        find.descendant(of: picker(), matching: find.byType(Text)),
      ))
        text.style?.fontSize,
    };
    expect(sizes, {closeTo(24, 1e-9)});
    await gesture.up();
  });

  group('the tone for all (the Smileys & People header\'s button)', () {
    // The button sits at the end of the header band of the second section:
    // the band ends 4 px before the viewport's right edge.
    Offset button(WidgetTester tester) {
      final viewport = tester.getRect(find.byType(PanelCatalogViewport));
      final padding = tester
          .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport))
          .padding;
      return Offset(
        viewport.right - padding.right - 12,
        viewport.top + padding.top + smileys + EmojiPagePolicy.headerExtent / 2,
      );
    }

    testWidgets('opens the waving hand in every tone under a title, and a '
        'choice is the tone of every emoji, inserting nothing', (tester) async {
      await pumpPage(tester);

      await tester.tapAt(button(tester), kind: PointerDeviceKind.mouse);
      await tester.pump(_settle);

      expect(picker(), findsOneWidget);
      expect(
        find.descendant(
          of: picker(),
          matching: find.text(strings.colorAllTitle),
        ),
        findsOneWidget,
      );
      final options = tester.widget<EmojiVariantPicker>(picker()).options;
      expect(options, [
        for (final glyph in [
          '👋',
          '👋\u{1F3FB}',
          '👋\u{1F3FC}',
          '👋\u{1F3FD}',
          '👋\u{1F3FE}',
          '👋\u{1F3FF}',
        ])
          fixtures.key(glyph),
      ]);

      await tester.tap(
        find.descendant(of: picker(), matching: find.text('👋\u{1F3FE}')),
      );
      await tester.pump(_settle);

      expect(
        preferences.defaultVariant,
        EmojiModifiers(tones: const [SkinTone.mediumDark]),
      );
      expect(host.picks, isEmpty);
      expect(picker(), findsNothing);
    });

    testWidgets('a finger has no such button', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPage(tester, arrangement: PanelArrangement.touch);

      expect(find.bySemanticsLabel(strings.colorAllTitle), findsNothing);
      semantics.dispose();
    });
  });

  group(
    'the grid follows its width, as the reference desktop client\'s does',
    () {
      // The page's width W: columns of 37 at least, whole pixels wide, the row
      // 2 shorter; the columns start 8 in from the left and end 4 before the
      // right, and the integer remainder is split. Recents: 30 smileys.
      for (final (width, columns, cellWidth, cellHeight, left) in [
        (292.0, 7, 40.0, 38.0, 0.0),
        (345.0, 9, 37.0, 35.0, 0.0),
        (392.0, 10, 38.0, 36.0, 0.0),
      ]) {
        testWidgets(
          '$width wide: $columns columns of $cellWidth x $cellHeight',
          (tester) async {
            final recents = [
              for (var i = 0; i < 30; i++) String.fromCharCode(0x1F600 + i),
            ];
            await pumpPage(tester, recents: recents, width: width);
            final viewport = tester.getRect(find.byType(PanelCatalogViewport));
            final top =
                viewport.top +
                tester
                    .widget<PanelCatalogViewport>(
                      find.byType(PanelCatalogViewport),
                    )
                    .padding
                    .top +
                EmojiPagePolicy.headerExtent;
            final x0 = viewport.left + 8 + left;

            // The last column of the first row, then the first of the second.
            await tester.tapAt(
              Offset(x0 + (columns - 0.5) * cellWidth, top + cellHeight / 2),
            );
            await tester.tapAt(
              Offset(x0 + cellWidth / 2, top + cellHeight * 1.5),
            );
            await tester.pump(const Duration(milliseconds: 500));

            expect(
              [for (final pick in host.picks) pick.key],
              [
                fixtures.key(recents[columns - 1]),
                fixtures.key(recents[columns]),
              ],
            );
          },
        );
      }

      testWidgets('a finger keeps the eight columns of the touch grid', (
        tester,
      ) async {
        final recents = [
          for (var i = 0; i < 30; i++) String.fromCharCode(0x1F600 + i),
        ];
        await pumpPage(
          tester,
          recents: recents,
          width: 392,
          arrangement: PanelArrangement.touch,
        );
        final viewport = tester.getRect(find.byType(PanelCatalogViewport));
        final padding = tester
            .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport))
            .padding;
        const cellHeight = EmojiPagePolicy.cellPitch;
        final cellWidth = (392 - padding.horizontal) / 8;
        final top = viewport.top + padding.top + EmojiPagePolicy.headerExtent;

        await tester.tapAt(
          Offset(
            viewport.left + padding.left + 7.5 * cellWidth,
            top + cellHeight / 2,
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        expect(host.picks.single.key, fixtures.key(recents[7]));
      });
    },
  );
}
