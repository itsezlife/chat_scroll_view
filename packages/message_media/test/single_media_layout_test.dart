import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

void main() {
  group('SingleMediaLayout.compute', () {
    const maxWidth = 300.0;

    test('landscape 16:9 fills max width under height clamp', () {
      final size = SingleMediaLayout.compute(
        aspectRatio: 16 / 9,
        maxWidth: maxWidth,
      );
      // Scaled to the max width; the height stays under maxWidth + 100.
      expect(size, const Size(300, 168));
    });

    test('portrait 9:16 hits photoHeight then shrinks width', () {
      final size = SingleMediaLayout.compute(
        aspectRatio: 9 / 16,
        maxWidth: maxWidth,
      );
      // h > photoHeight (400): clamp h, rescale w.
      expect(size, const Size(225, 400));
    });

    test('very wide aspect raises height to minHeight without shrinking w', () {
      final size = SingleMediaLayout.compute(
        aspectRatio: 10,
        maxWidth: maxWidth,
      );
      // h < 120: h = 120; the aspect-scaled width is not narrower, keep w.
      expect(size, const Size(300, 120));
    });

    test('a side that truncates to zero takes the no-dimensions side', () {
      final size = SingleMediaLayout.compute(aspectRatio: 500, maxWidth: 300);
      expect(size, const Size(300, 150));
    });

    test('an explicit max height is not soft-capped', () {
      final size = SingleMediaLayout.compute(
        aspectRatio: 9 / 16,
        maxWidth: 300,
        maxHeight: 350,
      );
      expect(size.height, 350);
    });

    test('non-positive aspect or width gives Size.zero', () {
      expect(
        SingleMediaLayout.compute(aspectRatio: 0, maxWidth: 300),
        Size.zero,
      );
      expect(SingleMediaLayout.compute(aspectRatio: 1, maxWidth: 0), Size.zero);
    });
  });
}
