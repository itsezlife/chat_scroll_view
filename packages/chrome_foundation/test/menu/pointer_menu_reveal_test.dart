import 'dart:math' as math;
import 'dart:ui';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';

double circ(double t) => math.sqrt(1 - (t - 1) * (t - 1));

void main() {
  const size = Size(200, 300);

  group('PointerMenuReveal', () {
    test('starts at half the width, 30% of the height and no opacity', () {
      final r = PointerMenuReveal.at(0);
      expect(r.widthFraction, 0.5);
      expect(r.heightFraction, 0.3);
      expect(r.opacity, 0);
    });

    test('ends full size and opaque', () {
      final r = PointerMenuReveal.at(1);
      expect(r.widthFraction, 1);
      expect(r.heightFraction, 1);
      expect(r.opacity, 1);
      expect(r.contentRevealed, 1);
    });

    test('the width is done at 0.6 of the clock, the height at 0.9', () {
      expect(PointerMenuReveal.at(0.6).widthFraction, 1);
      expect(PointerMenuReveal.at(0.6).heightFraction, lessThan(1));
      expect(PointerMenuReveal.at(0.9).heightFraction, 1);
    });

    test('the width follows easeOutCirc over its own 0.6', () {
      final r = PointerMenuReveal.at(0.15);
      expect(r.widthFraction, closeTo(0.5 + 0.5 * circ(0.25), 1e-12));
    });

    test('the height follows easeOutCirc over its own 0.9', () {
      final r = PointerMenuReveal.at(0.45);
      expect(r.heightFraction, closeTo(0.3 + 0.7 * circ(0.5), 1e-12));
    });

    test('the opacity is full by 0.3 of the clock', () {
      expect(PointerMenuReveal.at(0.3).opacity, 1);
      expect(PointerMenuReveal.at(0.15).opacity, closeTo(circ(0.5), 1e-12));
    });

    test('the content is revealed from the top as the clock runs', () {
      expect(PointerMenuReveal.at(0).contentRevealed, 0);
      expect(
        PointerMenuReveal.at(0.5).contentRevealed,
        closeTo(circ(0.5), 1e-12),
      );
    });
  });

  group('the frame', () {
    test('grows from the origin corner', () {
      final r = PointerMenuReveal.at(0);
      expect(
        r.frame(size, PointerMenuOrigin.topLeft),
        const Rect.fromLTWH(0, 0, 100, 90),
      );
      expect(
        r.frame(size, PointerMenuOrigin.topRight),
        const Rect.fromLTWH(100, 0, 100, 90),
      );
      expect(
        r.frame(size, PointerMenuOrigin.bottomLeft),
        const Rect.fromLTWH(0, 210, 100, 90),
      );
      expect(
        r.frame(size, PointerMenuOrigin.bottomRight),
        const Rect.fromLTWH(100, 210, 100, 90),
      );
    });

    test('is the whole body at the end', () {
      expect(
        PointerMenuReveal.at(1).frame(size, PointerMenuOrigin.bottomRight),
        Offset.zero & size,
      );
    });
  });

  test('a clock outside 0..1 is clamped', () {
    expect(PointerMenuReveal.at(-1).widthFraction, 0.5);
    expect(PointerMenuReveal.at(2).widthFraction, 1);
  });
}
