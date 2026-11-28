/// The web's draft options menu policy: its pinned values, the side by width
/// class, the style by input class and the placement at the strip.
///
/// **Seam:** `DraftOptionsWebMenuPolicy` (pure Dart), as
/// `DraftOptionsPolicy$Web.menu` carries it.
library;

import 'dart:ui';

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart' show Alignment;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const menu = DraftOptionsWebMenuPolicy.standard;

  group('pinned values', () {
    test('the web policy carries the standard menu', () {
      expect(const DraftOptionsPolicy$Web().menu, menu);
      expect(
        const DraftOptionsPolicy.web(),
        isNot(isA<DraftOptionsOverlayPolicy>()),
      );
    });

    test('hover opens after 200 ms; the menu reveals over 0.2 s on the '
        'standard easing, opacity 0 to 1 and scale 0.8 to 1', () {
      expect(menu.hoverDelay, const Duration(milliseconds: 200));
      expect(menu.reveal.duration, const Duration(milliseconds: 200));
      expect(menu.reveal.curve, const Cubic(0.4, 0, 0.2, 1));
      expect(menu.revealScaleFrom, 0.8);
      expect(menu.leaveGrace, const Duration(milliseconds: 200));
      expect(DraftOptionsPolicy.openGuard, const Duration(milliseconds: 400));
    });

    test('anchored 8 in from the strip top end, 8 above it, 8 from the '
        'window edges', () {
      expect(menu.anchorInset, 8);
      expect(menu.anchorGap, 8);
      expect(menu.edgeMargin, 8);
    });
  });

  group('side by width class', () {
    test('compact prefers the end side, medium and expanded the start', () {
      expect(
        menu.sideFor(ChromeWidthClass.compact),
        DraftOptionsMenuSide.towardEnd,
      );
      expect(
        menu.sideFor(ChromeWidthClass.medium),
        DraftOptionsMenuSide.towardStart,
      );
      expect(
        menu.sideFor(ChromeWidthClass.expanded),
        DraftOptionsMenuSide.towardStart,
      );
    });

    test('the side flips between 600 and 601 wide', () {
      DraftOptionsMenuSide at(double width) =>
          menu.sideFor(ChromeWidthClass.fromSize(Size(width, 800)));

      expect(at(600), DraftOptionsMenuSide.towardEnd);
      expect(at(601), DraftOptionsMenuSide.towardStart);
    });
  });

  group('style by input class', () {
    test('touch: a solid surface, rows 48 with 16 text, ripples', () {
      final touch = menu.styleFor(ChromeInputClass.touch);

      expect(touch.surface, DraftOptionsMenuSurface.solid);
      expect(touch.rowMetrics.height, 48);
      expect(touch.rowMetrics.fontSize, 16);
      expect(touch.ink, ChromeInkKind.ripple);
      expect(touch.verticalPadding, 8);
    });

    test('mouse: menu glass, compact rows, pointer presses', () {
      final mouse = menu.styleFor(ChromeInputClass.mouse);

      expect(mouse.surface, DraftOptionsMenuSurface.glass);
      expect(mouse.glass, GlassMaterial.menu);
      expect(mouse.rowMetrics.height, lessThan(48));
      expect(mouse.rowMetrics.fontSize, lessThan(16));
      expect(mouse.ink, ChromeInkKind.pointer);
    });

    test('a host overrides a value', () {
      final tall = menu.copyWith(hoverDelay: Duration.zero);

      expect(tall.hoverDelay, Duration.zero);
      expect(tall.reveal, menu.reveal);
      expect(tall, isNot(menu));
    });
  });

  group('placement', () {
    const bounds = Rect.fromLTWH(0, 0, 1000, 800);
    const strip = Rect.fromLTWH(200, 700, 600, 44);
    const size = Size(200, 150);

    test('toward the start: the end edge 8 in from the strip end, the bottom '
        '8 above it, growing from the bottom end corner', () {
      final placed = menu.place(
        strip: strip,
        size: size,
        bounds: bounds,
        side: DraftOptionsMenuSide.towardStart,
      );

      expect(placed.rect, const Rect.fromLTWH(592, 542, 200, 150));
      expect(placed.side, DraftOptionsMenuSide.towardStart);
      expect(placed.origin, Alignment.bottomRight);
    });

    test('toward the end with room: the start edge at the anchor', () {
      const narrow = Rect.fromLTWH(0, 700, 400, 44);
      final placed = menu.place(
        strip: narrow,
        size: size,
        bounds: bounds,
        side: DraftOptionsMenuSide.towardEnd,
      );

      expect(placed.rect.left, 392);
      expect(placed.side, DraftOptionsMenuSide.towardEnd);
      expect(placed.origin, Alignment.bottomLeft);
    });

    test('toward the end without room flips to the start', () {
      const full = Rect.fromLTWH(0, 700, 1000, 44);
      final placed = menu.place(
        strip: full,
        size: size,
        bounds: bounds,
        side: DraftOptionsMenuSide.towardEnd,
      );

      expect(placed.rect.right, 992);
      expect(placed.side, DraftOptionsMenuSide.towardStart);
    });

    test('right to left mirrors: toward the start goes right of the anchor '
        'at the strip left', () {
      final placed = menu.place(
        strip: strip,
        size: size,
        bounds: bounds,
        side: DraftOptionsMenuSide.towardStart,
        textDirection: TextDirection.rtl,
      );

      expect(placed.rect.left, 208);
      expect(placed.origin, Alignment.bottomLeft);
    });

    test('without room above it opens below the strip', () {
      const high = Rect.fromLTWH(200, 40, 600, 44);
      final placed = menu.place(
        strip: high,
        size: size,
        bounds: bounds,
        side: DraftOptionsMenuSide.towardStart,
      );

      expect(placed.rect.top, 92);
      expect(placed.origin, Alignment.topRight);
    });

    test('a menu that fits neither side is pushed inside the edge margin', () {
      final placed = menu.place(
        strip: const Rect.fromLTWH(0, 700, 120, 44),
        size: const Size(1100, 150),
        bounds: bounds,
        side: DraftOptionsMenuSide.towardStart,
      );

      expect(placed.rect.left, 8);
    });
  });
}
