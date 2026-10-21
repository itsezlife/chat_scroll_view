/// The geometry of the variant picker, without a widget.
///
/// **Seam:** [EmojiVariantPickerLayout] asked for sizes, rectangles, hit
/// tests and the origin of the picker against a pressed cell.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';

const _cell = Size(45, 45);

void main() {
  group('one row of six: the emoji, a separator, five tones', () {
    const layout = EmojiVariantPickerLayout(count: 6, cell: _cell);

    test('is 8 px pads around cells of the grid\'s size', () {
      expect(layout.hasSeparator, isTrue);
      expect(layout.card, const Size(4 * 8 + 1 + 6 * 45, 2 * 8 + 45));
      expect(
        layout.outer,
        const Size(4 * 8 + 1 + 6 * 45 + 20, 2 * 8 + 45 + 20),
      );
    });

    test('places the first option, the separator, then the rest', () {
      expect(layout.optionRect(0), const Rect.fromLTWH(8, 8, 45, 45));
      expect(layout.separatorRect, const Rect.fromLTWH(61, 8, 1, 45));
      expect(layout.optionRect(1), const Rect.fromLTWH(70, 8, 45, 45));
      expect(layout.optionRect(5).right, layout.card.width - 8);
    });

    test('reads the option under a point, and none on a pad or the line', () {
      expect(layout.indexAt(const Offset(30, 30)), 0);
      expect(layout.indexAt(const Offset(90, 30)), 1);
      expect(layout.indexAt(const Offset(61.5, 30)), isNull);
      expect(layout.indexAt(const Offset(4, 30)), isNull);
      expect(layout.indexAt(const Offset(30, 4)), isNull);
    });

    test('reads the nearest option for a finger, whatever its height', () {
      expect(layout.nearestIndex(const Offset(-50, 300)), 0);
      expect(layout.nearestIndex(const Offset(500, -300)), 5);
      expect(layout.nearestIndex(const Offset(92, 500)), 1);
    });
  });

  group('more than six options', () {
    const layout = EmojiVariantPickerLayout(count: 9, cell: _cell);

    test('are a grid of six columns with no separator', () {
      expect(layout.hasSeparator, isFalse);
      expect(layout.separatorRect, isNull);
      expect(layout.rows, 2);
      expect(layout.card, const Size(2 * 8 + 6 * 45, 2 * 8 + 2 * 45));
      expect(layout.optionRect(6), const Rect.fromLTWH(8, 53, 45, 45));
    });

    test('read both axes for a finger', () {
      expect(layout.nearestIndex(const Offset(30, 90)), 6);
    });
  });

  group('where it opens', () {
    const layout = EmojiVariantPickerLayout(count: 6, cell: _cell);
    // A 360 wide viewport at (100, 100), eight columns of 45.
    const viewport = Rect.fromLTWH(100, 100, 360, 400);

    Rect cellAt(int column, double top) =>
        Rect.fromLTWH(100 + column * 45, top, 45, 45);

    test('above the cell with a 2 px gap', () {
      final origin = layout.originFor(cellAt(3, 300), viewport);

      final card = Rect.fromLTWH(
        origin.dx + 10,
        origin.dy + 10,
        layout.card.width,
        layout.card.height,
      );
      expect(card.bottom, 300 - 2);
    });

    test('below the cell where above would cross the viewport\'s top', () {
      final origin = layout.originFor(cellAt(3, 120), viewport);

      expect(origin.dy + 10, 120 + 45 + 2);
    });

    test('slides from the left edge over the first column to the right edge '
        'over the last', () {
      final first = layout.originFor(cellAt(0, 300), viewport);
      final last = layout.originFor(cellAt(7, 300), viewport);

      // The shadow margin is part of the picker's box, as in the reference
      // client: the card keeps that much inside the edge at the ends.
      expect(first.dx, viewport.left);
      expect(last.dx + layout.outer.width, viewport.right);
    });

    test('in between, in proportion to the column', () {
      final middle = layout.originFor(cellAt(3, 300), viewport);
      final first = layout.originFor(cellAt(0, 300), viewport);
      final last = layout.originFor(cellAt(7, 300), viewport);

      expect(middle.dx, closeTo(first.dx + (last.dx - first.dx) * 3 / 7, 0.01));
    });

    test('never leaves a viewport narrower than itself', () {
      const narrow = Rect.fromLTWH(0, 100, 200, 400);
      final origin = layout.originFor(
        const Rect.fromLTWH(155, 300, 45, 45),
        narrow,
      );

      expect(origin.dx + 10, greaterThanOrEqualTo(narrow.left - 0.01));
    });
  });
}
