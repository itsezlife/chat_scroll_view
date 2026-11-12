import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextureFrameRegion', () {
    test(
      'centres a frame that is not square, rounding toward the top left',
      () {
        final region = TextureFrameRegion(
          textureWidth: 8,
          textureHeight: 8,
          rowStride: 40,
          width: 8,
          height: 3,
        );

        expect(region.left, 0);
        expect(region.top, 2);
        expect(region.offsetBytes, 2 * 40);
      },
    );

    test('a frame larger than the texture is refused', () {
      expect(
        () => TextureFrameRegion(
          textureWidth: 4,
          textureHeight: 4,
          rowStride: 16,
          width: 5,
          height: 4,
        ),
        throwsArgumentError,
      );
    });

    test('clears every byte of the texture outside the frame and nothing '
        'inside it or past a row', () {
      // A 4 x 4 texture, rows padded by one pixel, a 2 x 2 frame in the
      // middle.
      final region = TextureFrameRegion(
        textureWidth: 4,
        textureHeight: 4,
        rowStride: 20,
        width: 2,
        height: 2,
      );
      final target = Uint8List(20 * 4)..fillRange(0, 80, 9);

      region.clearMargins(target);

      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 5; x++) {
          final pixel = target.sublist(y * 20 + x * 4, y * 20 + x * 4 + 4);
          final inFrame = x >= 1 && x < 3 && y >= 1 && y < 3;
          final padding = x == 4;
          expect(
            pixel,
            inFrame || padding ? [9, 9, 9, 9] : [0, 0, 0, 0],
            reason: 'pixel ($x, $y)',
          );
        }
      }
    });

    test('copies packed rows into the frame at the stride', () {
      final region = TextureFrameRegion(
        textureWidth: 2,
        textureHeight: 2,
        rowStride: 12,
        width: 2,
        height: 1,
      );
      final target = Uint8List(24);
      final pixels = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      region.copyInto(target, pixels, swapRedBlue: false);

      // Top 0: the frame is one row, centred rounding up.
      expect(target, [
        1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      ]);
    });

    test('copies with red and blue swapped when the orders differ', () {
      final region = TextureFrameRegion(
        textureWidth: 2,
        textureHeight: 1,
        rowStride: 8,
        width: 2,
        height: 1,
      );
      final target = Uint8List(8);
      final bgra = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);

      region.copyInto(target, bgra, swapRedBlue: true);

      expect(target, [30, 20, 10, 40, 70, 60, 50, 80]);
    });

    test('swaps red and blue in place inside the frame only', () {
      final region = TextureFrameRegion(
        textureWidth: 2,
        textureHeight: 2,
        rowStride: 8,
        width: 2,
        height: 1,
      );
      final target = Uint8List.fromList([
        1, 2, 3, 4, 5, 6, 7, 8, //
        9, 9, 8, 9, 9, 9, 8, 9,
      ]);

      region.swapRedBlue(target);

      expect(target, [
        3, 2, 1, 4, 7, 6, 5, 8, //
        9, 9, 8, 9, 9, 9, 8, 9,
      ]);
    });

    test('works on a view that does not start on a word', () {
      final region = TextureFrameRegion(
        textureWidth: 1,
        textureHeight: 1,
        rowStride: 4,
        width: 1,
        height: 1,
      );
      final backing = Uint8List(6);
      final target = Uint8List.view(backing.buffer, 1, 4);

      region.copyInto(
        target,
        Uint8List.fromList([1, 2, 3, 4]),
        swapRedBlue: true,
      );

      expect(backing, [0, 3, 2, 1, 4, 0]);
    });
  });
}
