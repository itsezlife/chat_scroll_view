import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

void main() {
  group('computeSingleMediaSize', () {
    const maxWidth = 300.0;

    test('landscape 16:9 fills max width under height clamp', () {
      final size = computeSingleMediaSize(
        aspectRatio: 16 / 9,
        maxWidth: maxWidth,
      );
      // Scaled to the max width; the height stays under maxWidth + 100.
      expect(size, const Size(300, 168));
    });

    test('portrait 9:16 hits photoHeight then shrinks width', () {
      final size = computeSingleMediaSize(
        aspectRatio: 9 / 16,
        maxWidth: maxWidth,
      );
      // h > photoHeight (400): clamp h, rescale w.
      expect(size, const Size(225, 400));
    });

    test('very wide aspect raises height to minHeight without shrinking w', () {
      final size = computeSingleMediaSize(aspectRatio: 10, maxWidth: maxWidth);
      // h < 120: h = 120; the aspect-scaled width is not narrower, keep w.
      expect(size, const Size(300, 120));
    });

    test('photo, video and animation share the same box for one aspect', () {
      Size boxOf(MediaItemKind kind) => computeSingleMediaSize(
        aspectRatio: 4 / 3,
        maxWidth: maxWidth,
        kind: kind,
      );
      final photo = boxOf(MediaItemKind.photo);
      expect(boxOf(MediaItemKind.video), photo);
      expect(boxOf(MediaItemKind.animation), photo);
    });

    test('a file or custom kind is not a box', () {
      for (final kind in const [
        MediaItemKind.file,
        MediaItemKind.custom('sticker'),
      ]) {
        expect(
          () => computeSingleMediaSize(
            aspectRatio: 1,
            maxWidth: maxWidth,
            kind: kind,
          ),
          throwsAssertionError,
        );
      }
    });

    test('a side that truncates to zero takes the no-dimensions side', () {
      // Corrected from the port's 120 (the minimum height) to 150, the
      // Android box without dimensions.
      final size = computeSingleMediaSize(aspectRatio: 500, maxWidth: 300);
      expect(size, const Size(300, 150));
    });

    test('an explicit max height is not soft-capped', () {
      final size = computeSingleMediaSize(
        aspectRatio: 9 / 16,
        maxWidth: 300,
        maxHeight: 350,
      );
      expect(size.height, 350);
    });

    test('non-positive aspect or width gives Size.zero', () {
      expect(computeSingleMediaSize(aspectRatio: 0, maxWidth: 300), Size.zero);
      expect(computeSingleMediaSize(aspectRatio: 1, maxWidth: 0), Size.zero);
    });
  });
}
