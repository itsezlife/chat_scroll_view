/// Where a pack sheet's card sits on touch, and how its top follows the grid.
///
/// **Seam:** [PackSheetFrame] built from a screen, a status bar and a
/// content height, read through its height, the grid's lead, the card's top
/// under a grid offset and the background drawn behind it. Numbers: an
/// 800 tall portrait screen and a 24 status bar unless a test says otherwise.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_frame.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_view.dart';

PackSheetFrame touch(
  double content, {
  PackSheetGrid grid = PackSheetGrid.stickers,
  Size screen = const Size(400, 800),
  double statusBar = 24,
}) => PackSheetFrame.touch(
  screen: screen,
  statusBar: statusBar,
  content: content,
  grid: grid,
);

void main() {
  group('a short sheet', () {
    test('wraps its content, under 3.2/5 of the screen', () {
      final frame = touch(480);

      expect(frame.height, 480);
      expect(frame.lead, 0);
      expect(frame.topInset, 0);
      expect(frame.cardTopAt(0), 0);
      expect(frame.cardTopAt(100), 0);
    });
  });

  group('a tall sticker sheet', () {
    test('opens with its card two fifths down the screen', () {
      final frame = touch(2000);

      expect(frame.height, 800);
      expect(frame.topInset, 24);
      expect(frame.lead, 320);
      // In the sheet's box, which is the screen's.
      expect(frame.cardTopAt(0), 24 + 320);
    });

    test('a sheet shorter than the screen still opens two fifths down, and '
        'its lead is what the grid scrolls before it is all in view', () {
      // 600 + 24 of 800: the sheet's box starts at 176.
      final frame = touch(600);

      expect(frame.height, 624);
      expect(frame.lead, 320 - 176);
      expect(176 + frame.cardTopAt(0), 24 + 320);
    });

    test('the card rises with the grid, then stays under the status bar', () {
      final frame = touch(2000);

      expect(frame.cardTopAt(100), 24 + 220);
      expect(frame.cardTopAt(320), 24);
      expect(frame.cardTopAt(900), 24);
    });

    test('the grid is under the header once it has scrolled past the lead', () {
      final frame = touch(2000);

      expect(frame.scrolledUnderHeaderAt(320), isFalse);
      expect(frame.scrolledUnderHeaderAt(321), isTrue);
    });
  });

  group('a tall emoji sheet', () {
    test('opens with its card at 0.56 of a portrait screen', () {
      final frame = touch(2000, grid: PackSheetGrid.emoji);

      expect(frame.lead, closeTo(800 * 0.56, 1e-9));
    });

    test('and at 0.3 of a landscape one', () {
      final frame = touch(
        2000,
        grid: PackSheetGrid.severalEmoji,
        screen: const Size(800, 400),
      );

      expect(frame.lead, closeTo(400 * 0.3, 1e-9));
    });
  });

  group('the sticker background', () {
    test('keeps its 12 radius away from the status bar', () {
      final frame = touch(2000);

      expect(frame.stickersBackdrop(200), (top: 200.0, radius: 12.0));
    });

    test('closes on the status bar, squaring its corners', () {
      final frame = touch(2000);

      // Within two status bars of the top: it grows up by the distance in.
      final halfway = frame.stickersBackdrop(42);
      expect(halfway.top, 42 - 6);
      expect(halfway.radius, closeTo(12 * (1 - 12 / 24), 1e-9));

      expect(frame.stickersBackdrop(24), (top: 0.0, radius: 0.0));
    });

    test('a sheet that does not fill the screen never squares', () {
      final frame = touch(600);

      expect(frame.stickersBackdrop(30), (top: 30.0, radius: 12.0));
    });
  });

  group('the emoji background', () {
    test('lerps to the top of the screen as it closes', () {
      final frame = touch(2000, grid: PackSheetGrid.emoji);

      expect(frame.emojiBackdrop(24, 0), (top: 24.0, radius: 14.0));
      expect(frame.emojiBackdrop(24, 0.5), (top: 12.0, radius: 7.0));
      expect(frame.emojiBackdrop(24, 1), (top: 0.0, radius: 0.0));
    });

    test('closes once the card is at the status bar', () {
      final frame = touch(2000, grid: PackSheetGrid.emoji);

      expect(frame.closesAt(25), isFalse);
      expect(frame.closesAt(24), isTrue);
    });

    test('a sheet that does not fill the screen never closes', () {
      expect(touch(480, grid: PackSheetGrid.emoji).closesAt(0), isFalse);
      expect(touch(600, grid: PackSheetGrid.emoji).closesAt(24), isFalse);
    });
  });
}
