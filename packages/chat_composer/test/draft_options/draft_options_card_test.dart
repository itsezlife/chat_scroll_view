/// The Android card presentation as pure values: the layout's metrics and
/// motion pinned on the Android policy, and the card and menu placed for a
/// window, portrait and landscape, at two window sizes.
///
/// **Seam:** `DraftOptionsPolicy$Android.card` / `cardMotion` and
/// `DraftOptionsCardLayout.resolve`. Expected rects are worked by hand from
/// the layout rules (card height H − 6 − menu, the visible top following
/// the first message − 4 within 80 % of the display − 8, the group centred
/// with an offset of at most 8; landscape full height, width
/// min(W, max(340, 0.6 W))).
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('policy', () {
    test('the Android policy carries the card layout and motion', () {
      final policy = DraftOptionsPolicy.forPlatform(TargetPlatform.android);

      expect(
        policy,
        isA<DraftOptionsPolicy$Android>()
            .having((p) => p.card, 'card', DraftOptionsCardLayout.android)
            .having(
              (p) => p.cardMotion,
              'cardMotion',
              DraftOptionsCardMotion.android,
            ),
      );
    });

    test('the card layout values', () {
      const card = DraftOptionsCardLayout.android;

      expect(card.sideMargin, 8);
      expect(card.cornerRadius, 8);
      expect(card.elevation, 4);
      expect(card.headerHeight, 56);
      expect(card.headerPadding, 18);
      expect(card.titleSize, 18);
      expect(card.subtitleSize, 14);
      expect(card.listPadding, 4);
      expect(card.menuGap, 6);
      expect(card.minHeightFraction, 0.5);
      expect(card.firstMessageInset, 4);
      expect(card.displayFraction, 0.8);
      expect(card.displayInset, 8);
      expect(card.maxCentringOffset, 8);
      expect(card.menuRadius, 12);
      expect(card.menuPadding, 8);
      expect(card.menuOverlap, 2);
      expect(card.landscapeMargin, 8);
      expect(card.landscapeMinWidth, 340);
      expect(card.landscapeWidthFraction, 0.6);
      expect(card.landscapeMenuGap, 8);
    });

    test('the card motion values', () {
      const motion = DraftOptionsCardMotion.android;
      const curve = Cubic(0.199, 0.011, 0.279, 0.910);

      for (final spec in [
        motion.open,
        motion.close,
        motion.offsets,
        motion.scroll,
      ]) {
        expect(spec.duration, const Duration(milliseconds: 250));
        final cubic = spec.curve as Cubic;
        expect(cubic.a, closeTo(curve.a, 0.001));
        expect(cubic.b, closeTo(curve.b, 0.001));
        expect(cubic.c, closeTo(curve.c, 0.001));
        expect(cubic.d, closeTo(curve.d, 0.001));
      }
      expect(motion.openScale, 0.95);
      expect(motion.offsetsDelay, const Duration(milliseconds: 50));
    });

    test('a host overrides the card through the constructor', () {
      const policy = DraftOptionsPolicy$Android(
        card: DraftOptionsCardLayout(sideMargin: 12),
        cardMotion: DraftOptionsCardMotion(openScale: 0.9),
      );

      expect(policy.card.sideMargin, 12);
      expect(policy.card.cornerRadius, 8);
      expect(policy.cardMotion.openScale, 0.9);
    });
  });

  group('portrait', () {
    const card = DraftOptionsCardLayout.android;

    test('400 x 800: the card shrinks to the message within 80 %, the group '
        'centred', () {
      // Menu 200 x 200 inside 8 padding: a 216 box. Card 800 − 6 − 216 =
      // 578; list 578 − 56 = 522; the message's top 522 − 4 − 120 = 398,
      // less 4 = 394, held to 522 − (0.8 · 800 − 216 − 8) = 106. Group
      // 216 − 8 + 578 − 106 = 680 in 784: offset 8 + 52 − 106 = −46.
      final geometry = card.resolve(
        area: const Size(400, 800),
        display: 800,
        menu: const Size(200, 200),
        content: 120,
      );

      expect(geometry.landscape, isFalse);
      expect(geometry.card, const Rect.fromLTWH(8, -46, 384, 578));
      expect(geometry.topOffset, 106);
      expect(geometry.visibleTop, 60);
      expect(geometry.menu, const Rect.fromLTWH(184, 530, 216, 216));
    });

    test('360 x 640: the same rules at a smaller window', () {
      // Card 640 − 6 − 216 = 418; list 362; message top 238, less 4 = 234,
      // held to 362 − (512 − 224) = 74. Group 208 + 344 = 552 in 624:
      // offset 8 + 36 − 74 = −30.
      final geometry = card.resolve(
        area: const Size(360, 640),
        display: 640,
        menu: const Size(200, 200),
        content: 120,
      );

      expect(geometry.card, const Rect.fromLTWH(8, -30, 344, 418));
      expect(geometry.topOffset, 74);
      expect(geometry.menu, const Rect.fromLTWH(144, 386, 216, 216));
    });

    test('a message taller than the list keeps the full card', () {
      // Its top is above the list: no shrink. Group 208 + 578 = 786 in
      // 784: offset 8 − 1 = 7.
      final geometry = card.resolve(
        area: const Size(400, 800),
        display: 800,
        menu: const Size(200, 200),
        content: 600,
      );

      expect(geometry.topOffset, 0);
      expect(geometry.card, const Rect.fromLTWH(8, 7, 384, 578));
    });

    test('a tall menu leaves the card half the height', () {
      // Box 516: 800 − 6 − 516 = 278 is under 400, so 400.
      final geometry = card.resolve(
        area: const Size(400, 800),
        display: 800,
        menu: const Size(200, 500),
        content: 600,
      );

      expect(geometry.card.height, 400);
      expect(geometry.menu.top, geometry.card.bottom - 2);
    });

    test('the centring offset is at most 8', () {
      // A display much taller than the area would centre lower than 8.
      final geometry = card.resolve(
        area: const Size(400, 800),
        display: 800,
        menu: Size.zero,
        content: 0,
      );

      expect(geometry.card.top, lessThanOrEqualTo(8));
    });
  });

  group('landscape', () {
    const card = DraftOptionsCardLayout.android;

    test('800 x 400: full height, 0.6 of the width, the menu to its right', () {
      final geometry = card.resolve(
        area: const Size(800, 400),
        display: 400,
        menu: const Size(200, 200),
        content: 120,
      );

      expect(geometry.landscape, isTrue);
      expect(geometry.card, const Rect.fromLTWH(8, 8, 480, 384));
      expect(geometry.topOffset, 0);
      expect(geometry.menu, const Rect.fromLTWH(488, 0, 216, 216));
    });

    test('640 x 360 and a narrow 500 x 400 take at least 340', () {
      final wide = card.resolve(
        area: const Size(640, 360),
        display: 360,
        menu: const Size(200, 200),
        content: 120,
      );
      final narrow = card.resolve(
        area: const Size(500, 400),
        display: 400,
        menu: const Size(100, 100),
        content: 120,
      );

      expect(wide.card, const Rect.fromLTWH(8, 8, 384, 344));
      expect(wide.menu.topLeft, const Offset(392, 0));
      expect(narrow.card, const Rect.fromLTWH(8, 8, 340, 384));
      expect(narrow.menu.topLeft, const Offset(348, 0));
    });
  });

  group('lerp', () {
    test('the offsets lerp; the rest is the target', () {
      const card = DraftOptionsCardLayout.android;
      final from = card.resolve(
        area: const Size(400, 800),
        display: 800,
        menu: const Size(200, 200),
        content: 600,
      );
      final to = card.resolve(
        area: const Size(400, 800),
        display: 800,
        menu: const Size(200, 200),
        content: 120,
      );

      final half = DraftOptionsCardGeometry.lerp(from, to, 0.5);

      expect(half.topOffset, 53);
      expect(half.card.top, (7 + -46) / 2);
      expect(half.card.height, to.card.height);
      expect(half.menu.top, half.card.bottom - 2);
    });
  });

  test('ChromeCardOverlayTiming is the list cubic', () {
    expect(ChromeCardOverlayTiming.show.curve, ChromeMotion.androidListCurve);
  });
}
