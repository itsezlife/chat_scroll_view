import 'dart:ui';

import 'package:chat_composer/src/menu/selection_menu_layout.dart';
import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The layout arithmetic of the selection menu: the reference floating
/// toolbar's numbers as pure functions.
///
/// **Seam:** `SelectionMenuLayout` and `SelectionMenuMorph`, read as sizes and
/// rectangles.
void main() {
  group('main row', () {
    test('an item is its label and 16 dp each side, at least 48', () {
      expect(
        SelectionMenuLayout.mainItemWidth(10, first: false, last: false),
        48,
      );
      expect(
        SelectionMenuLayout.mainItemWidth(50, first: false, last: false),
        82,
      );
    });

    test('the first item and the last take 24 at their outer end', () {
      expect(
        SelectionMenuLayout.mainItemWidth(50, first: true, last: false),
        90,
      );
      expect(
        SelectionMenuLayout.mainItemWidth(50, first: false, last: true),
        90,
      );
      expect(
        SelectionMenuLayout.mainItemWidth(50, first: true, last: true),
        98,
      );
    });

    test('the budget is 400 or the screen less 16 each side', () {
      expect(SelectionMenuLayout.budget(800), 400);
      expect(SelectionMenuLayout.budget(360), 328);
    });

    test('items stay while they fit beside the More button', () {
      // 90 + 82 = 172, then 82 more would leave 328 - 254 = 74 < 56 + 82.
      final row = SelectionMenuLayout.mainRow(
        textWidths: [50, 50, 50, 50],
        budget: 328,
      );

      expect(row.count, 3);
      // The three items and the More button.
      expect(row.width, 90 + 82 + 82 + 56);
    });

    test('the last item may take the More button\'s room when all fit', () {
      final row = SelectionMenuLayout.mainRow(
        textWidths: [50, 50, 50],
        budget: 90 + 82 + 90,
      );

      expect(row.count, 3);
      expect(row.width, 90 + 82 + 90);
    });

    test('the first item that does not fit ends the row', () {
      final row = SelectionMenuLayout.mainRow(
        textWidths: [50, 400, 10],
        budget: 328,
      );

      expect(row.count, 1);
    });

    test('an item wider than the budget is cut to it', () {
      final row = SelectionMenuLayout.mainRow(textWidths: [1000], budget: 328);

      expect(row.count, 1);
      expect(row.width, 328);
    });
  });

  group('overflow page', () {
    test('the width is the widest item, at least the More button\'s 56', () {
      expect(SelectionMenuLayout.overflowWidth([10]), 56);
      expect(SelectionMenuLayout.overflowWidth([40, 100]), 136);
      expect(SelectionMenuLayout.overflowWidth([100], budget: 100), 100);
    });

    test('the height is the rows, the back row and a peek when it scrolls', () {
      // 2 rows and nothing to scroll.
      expect(SelectionMenuLayout.overflowHeight(2), 2 * 48 + 48);
      // 4 rows, the most the page shows at rest, nothing more to scroll.
      expect(SelectionMenuLayout.overflowHeight(4), 4 * 48 + 48);
      // Five items scroll: four rows, the back row and half a row.
      expect(SelectionMenuLayout.overflowHeight(5), 264);
      expect(SelectionMenuLayout.overflowHeight(12), 264);
    });

    test('a page is never sized to fewer than two rows or more than four', () {
      expect(SelectionMenuLayout.overflowHeight(9, rows: 0), 2 * 48 + 48 + 24);
      expect(SelectionMenuLayout.overflowHeight(9, rows: 9), 264);
      expect(SelectionMenuLayout.overflowHeight(1), 48 + 48);
    });

    test('rows that fit a height leave out the back row', () {
      expect(SelectionMenuLayout.rowsIn(48 + 3 * 48 + 10), 3);
      expect(SelectionMenuLayout.rowsIn(48), 0);
    });
  });

  group('placement', () {
    const viewport = Rect.fromLTWH(0, 0, 400, 800);
    const main = Size(300, 48);

    test('a menu with no page goes above the selection, 8 dp clear', () {
      final placement = SelectionMenuLayout.place(
        viewport: viewport,
        content: const Rect.fromLTWH(150, 400, 100, 20),
        main: main,
        overflowWidth: 0,
        overflowCount: 0,
      );

      final card = placement.cardRect(main);
      expect(card.bottom, 400 - 8);
      expect(card.height, 48);
      expect(placement.overflowUpwards, isFalse);
    });

    test('with no room above it goes below, 8 dp clear', () {
      final placement = SelectionMenuLayout.place(
        viewport: viewport,
        content: const Rect.fromLTWH(150, 30, 100, 20),
        main: main,
        overflowWidth: 0,
        overflowCount: 0,
      );

      expect(placement.cardRect(main).top, 50 + 8);
    });

    test('the card keeps 16 dp from the screen edge', () {
      final left = SelectionMenuLayout.place(
        viewport: viewport,
        content: const Rect.fromLTWH(0, 400, 20, 20),
        main: main,
        overflowWidth: 0,
        overflowCount: 0,
      );
      final right = SelectionMenuLayout.place(
        viewport: viewport,
        content: const Rect.fromLTWH(380, 400, 20, 20),
        main: main,
        overflowWidth: 0,
        overflowCount: 0,
      );

      expect(left.cardRect(main).left, 16);
      expect(right.cardRect(main).right, 400 - 16);
    });

    test('a page opens upwards when two rows fit above the selection', () {
      final placement = SelectionMenuLayout.place(
        viewport: viewport,
        content: const Rect.fromLTWH(150, 600, 100, 20),
        main: main,
        overflowWidth: 200,
        overflowCount: 8,
      );

      expect(placement.overflowUpwards, isTrue);
      // The card keeps its bottom edge while it grows.
      final open = placement.cardRect(placement.overflow!);
      final closed = placement.cardRect(main);
      expect(open.bottom, closed.bottom);
      expect(open.bottom, 600 - 8);
      expect(open.height, 264);
    });

    test(
      'a page opens downwards from a card above a selection near the top',
      () {
        final placement = SelectionMenuLayout.place(
          viewport: viewport,
          content: const Rect.fromLTWH(150, 70, 100, 20),
          main: main,
          overflowWidth: 200,
          overflowCount: 8,
        );

        expect(placement.overflowUpwards, isFalse);
        final closed = placement.cardRect(main);
        final open = placement.cardRect(placement.overflow!);
        expect(closed.top, open.top);
        // The row sits above the selection and the page reaches over it.
        expect(closed.bottom, 70 - 8);
      },
    );

    test('a page that fits only below opens below the selection', () {
      final placement = SelectionMenuLayout.place(
        viewport: viewport,
        content: const Rect.fromLTWH(150, 20, 100, 20),
        main: main,
        overflowWidth: 200,
        overflowCount: 8,
      );

      expect(placement.overflowUpwards, isFalse);
      expect(placement.cardRect(main).top, 40 + 8);
    });

    test('a page with too little room is cut to what the screen allows', () {
      const short = Rect.fromLTWH(0, 0, 400, 200);
      final placement = SelectionMenuLayout.place(
        viewport: short,
        content: const Rect.fromLTWH(150, 100, 100, 20),
        main: main,
        overflowWidth: 200,
        overflowCount: 8,
      );

      expect(placement.overflow!.height, lessThan(264));
      expect(placement.overflow!.height, greaterThanOrEqualTo(2 * 48 + 48));
    });

    test('a right-to-left card keeps its left edge', () {
      final placement = SelectionMenuLayout.place(
        viewport: viewport,
        content: const Rect.fromLTWH(0, 400, 20, 20),
        main: main,
        overflowWidth: 0,
        overflowCount: 0,
        rtl: true,
      );

      expect(placement.cardRect(main).left, 16);
      expect(placement.cardRect(const Size(120, 48)).left, 16);
    });
  });

  group('morph', () {
    const morph = SelectionMenuMorph(
      main: Size(300, 48),
      overflow: Size(200, 264),
      upwards: false,
      rtl: false,
    );

    test('at rest closed the card is the row and the More button its end', () {
      final frame = morph.frame(opening: true, width: 0, height: 0, ease: 0);

      expect(frame.size, const Size(300, 48));
      expect(frame.main, const Rect.fromLTWH(0, 0, 300, 48));
      // The 56 by 48 button sits flush at the card's end.
      expect(frame.backRow.left, 300 - 56);
      expect(frame.backRow.top, 0);
      expect(frame.backOpacity, 0);
    });

    test('at rest open the card is the page and the back row its top', () {
      final frame = morph.frame(opening: true, width: 1, height: 1, ease: 1);

      expect(frame.size, const Size(200, 264));
      expect(frame.backRow, const Rect.fromLTWH(0, 0, 200, 48));
      expect(frame.list, const Rect.fromLTWH(0, 48, 200, 216));
      expect(frame.backOpacity, 1);
    });

    test('opening upwards, the back row is the page\'s bottom', () {
      const up = SelectionMenuMorph(
        main: Size(300, 48),
        overflow: Size(200, 264),
        upwards: true,
        rtl: false,
      );

      final closed = up.frame(opening: true, width: 0, height: 0, ease: 0);
      final open = up.frame(opening: true, width: 1, height: 1, ease: 1);

      expect(closed.main.top, 0);
      expect(open.backRow, const Rect.fromLTWH(0, 216, 200, 48));
      expect(open.list, const Rect.fromLTWH(0, 0, 200, 216));
    });

    test('width and height move on their own progress', () {
      final frame = morph.frame(
        opening: true,
        width: 0.1,
        height: 0.9,
        ease: 0.9,
      );

      expect(frame.size.width, closeTo(300 - 10, 1e-9));
      expect(frame.size.height, closeTo(48 + 0.9 * 216, 1e-9));
    });

    test('the row keeps to the end edge while the card narrows', () {
      final frame = morph.frame(
        opening: true,
        width: 0.5,
        height: 0.5,
        ease: 0.5,
      );

      // The card is 250 wide; the 300 wide row has slid so its end stays at
      // the card's end.
      expect(frame.size.width, 250);
      expect(frame.main.right, 250);
    });

    test('closing runs the same pieces from the page back to the row', () {
      final start = morph.frame(opening: false, width: 0, height: 0, ease: 0);
      final end = morph.frame(opening: false, width: 1, height: 1, ease: 1);

      expect(start.size, const Size(200, 264));
      expect(start.backOpacity, 1);
      expect(end.size, const Size(300, 48));
      expect(end.backOpacity, 0);
      expect(end.backRow.left, 300 - 56);
    });

    test('mirrored, every piece keeps to the start edge instead', () {
      const rtl = SelectionMenuMorph(
        main: Size(300, 48),
        overflow: Size(200, 264),
        upwards: false,
        rtl: true,
      );

      final closed = rtl.frame(opening: true, width: 0, height: 0, ease: 0);
      final open = rtl.frame(opening: true, width: 1, height: 1, ease: 1);

      expect(closed.main.left, 0);
      expect(closed.backRow.left, closeTo(56 - 200, 1e-9));
      expect(open.backRow, const Rect.fromLTWH(0, 0, 200, 48));
    });

    test('the morph diagonal is the distance the size changes along', () {
      expect(morph.diagonal, closeTo(238.03, 0.01));
    });
  });

  group('metrics', () {
    test('touch platforms clear the handles under a selection', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          SelectionMenuMetrics.forPlatform(platform).belowClearance,
          greaterThan(0),
        );
      }
    });

    test('pointer platforms clear nothing, and the web is one', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(SelectionMenuMetrics.forPlatform(platform).belowClearance, 0);
      }
      expect(
        SelectionMenuMetrics.forPlatform(
          TargetPlatform.android,
          isWeb: true,
        ).belowClearance,
        0,
      );
    });
  });
}
