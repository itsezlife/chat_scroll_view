/// Where the selection menu goes: above the selection when the tallest menu
/// (264 dp: four rows, the Back row and the peek of a fifth) fits, else below,
/// else the roomier side; 16 dp from the screen's left and right edges and 12
/// from the safe area and the keyboard; 8 dp above the selection and 20 dp
/// below it.
///
/// **Seam:** `computeSelectionMenuPlacement` over anchors and insets, and the
/// layout delegate that turns a placement into an offset.
library;

import 'package:chat_composer/src/menu/selection_menu_position.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const screen = Size(400, 800);

  SelectionMenuPlacement place({
    Size size = screen,
    EdgeInsets safe = EdgeInsets.zero,
    double keyboard = 0,
    Offset primary = const Offset(200, 400),
    Offset? secondary,
    double maxHeight = 264,
    double maxWidth = 400,
  }) => computeSelectionMenuPlacement(
    screen: size,
    safe: safe,
    keyboardInset: keyboard,
    anchors: TextSelectionToolbarAnchors(
      primaryAnchor: primary,
      secondaryAnchor: secondary ?? primary + const Offset(0, 20),
    ),
    maxHeight: maxHeight,
    maxWidth: maxWidth,
  );

  group('above or below', () {
    test('above when 264 dp fit over the selection', () {
      final placement = place();
      expect(placement.fitsAbove, isTrue);
      expect(placement.maxHeight, 264);
    });

    test('below when they do not fit above but do below', () {
      final placement = place(primary: const Offset(200, 100));
      expect(placement.fitsAbove, isFalse);
      expect(placement.maxHeight, 264);
    });

    test('the roomier side when neither fits, capped to its room', () {
      // A short screen, so neither side reaches 264.
      final placement = place(
        size: const Size(400, 500),
        primary: const Offset(200, 200),
        secondary: const Offset(200, 220),
      );
      // Above: 200 - 8 - 12 = 180. Below: 500 - 12 - 220 - 20 = 248.
      expect(placement.fitsAbove, isFalse);
      expect(placement.maxHeight, 248);
    });

    test('stays above, with its room, when neither side fits and above has '
        'more', () {
      final placement = place(
        size: const Size(400, 300),
        primary: const Offset(200, 230),
        secondary: const Offset(200, 250),
      );
      // Above: 230 - 8 - 12 = 210. Below: 300 - 12 - 250 - 20 = 18.
      expect(placement.fitsAbove, isTrue);
      expect(placement.maxHeight, 210);
    });
  });

  group('gaps and margins', () {
    test(
      'the card sits 8 dp over the primary anchor, 20 below the secondary',
      () {
        final placement = place();
        expect(placement.anchorAbove, const Offset(200, 392));
        expect(placement.anchorBelow, const Offset(200, 440));
      },
    );

    test('the region keeps 16 dp from the sides and 12 from the safe area', () {
      final placement = place(safe: const EdgeInsets.only(top: 30, bottom: 20));
      expect(placement.padding, const EdgeInsets.fromLTRB(16, 42, 16, 32));
      expect(placement.localAdjustment, const Offset(16, 42));
    });

    test('an open keyboard replaces the bottom safe area', () {
      final placement = place(
        safe: const EdgeInsets.only(bottom: 20),
        keyboard: 300,
      );
      expect(placement.padding.bottom, 312);
    });

    test('the row is 400 wide at most, or the screen less 32', () {
      expect(place().maxWidth, 368);
      expect(place(size: const Size(500, 800)).maxWidth, 400);
    });

    test('the page is as wide as the screen less 32, with no cap of 400', () {
      expect(place().pageMaxWidth, 368);
      expect(place(size: const Size(500, 800)).pageMaxWidth, 468);
    });
  });

  test('an anchor off the visible band is pulled back to the other one', () {
    // The primary anchor is above the top margin; the secondary is in view.
    final placement = place(
      primary: const Offset(200, -50),
      secondary: const Offset(200, 120),
    );
    expect(placement.anchorAbove.dy, 120 - 8);
  });

  group('layout delegate', () {
    SelectionMenuLayoutDelegate delegate({
      Offset above = const Offset(100, 300),
      Offset below = const Offset(100, 340),
      bool fitsAbove = true,
      double? referenceWidth,
      TextDirection direction = TextDirection.ltr,
    }) => SelectionMenuLayoutDelegate(
      anchorAbove: above,
      anchorBelow: below,
      fitsAbove: fitsAbove,
      referenceWidth: referenceWidth,
      textDirection: direction,
    );

    test('loosens the constraints so the card shrink-wraps', () {
      final constraints = delegate().getConstraintsForChild(
        BoxConstraints.tight(const Size(376, 600)),
      );
      expect(constraints.minWidth, 0);
      expect(constraints.maxWidth, 376);
    });

    test('above, the card ends at the anchor and is centred on it', () {
      final offset = delegate().getPositionForChild(
        const Size(376, 600),
        const Size(100, 42),
      );
      expect(offset, const Offset(50, 258));
    });

    test('below, the card starts at the anchor', () {
      final offset = delegate(
        fitsAbove: false,
      ).getPositionForChild(const Size(376, 600), const Size(100, 42));
      expect(offset, const Offset(50, 340));
    });

    test('the card stays inside the region', () {
      final offset = delegate(
        above: const Offset(0, 300),
      ).getPositionForChild(const Size(376, 600), const Size(100, 42));
      expect(offset.dx, 0);
      final right = delegate(
        above: const Offset(376, 300),
      ).getPositionForChild(const Size(376, 600), const Size(100, 42));
      expect(right.dx, 276);
    });

    test('a narrower page hugs the trailing edge of the reference width', () {
      // Centred as a 200 dp card (x 0 to 200 at anchor 100); a 150 dp page
      // keeps the right edge.
      final offset = delegate(
        referenceWidth: 200,
      ).getPositionForChild(const Size(376, 600), const Size(150, 42));
      expect(offset.dx, 50);
    });

    test('in right-to-left it hugs the leading edge instead', () {
      final offset = delegate(
        referenceWidth: 200,
        direction: TextDirection.rtl,
      ).getPositionForChild(const Size(376, 600), const Size(150, 42));
      expect(offset.dx, 0);
    });

    test('relayouts only when an input changed', () {
      expect(delegate().shouldRelayout(delegate()), isFalse);
      expect(delegate().shouldRelayout(delegate(fitsAbove: false)), isTrue);
      expect(
        delegate().shouldRelayout(delegate(above: const Offset(101, 300))),
        isTrue,
      );
    });
  });
}
