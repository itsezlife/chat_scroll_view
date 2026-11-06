import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/src/engine/video_frame_pixels.dart';

void main() {
  group('premultiplyRgbaIntoBgra', () {
    test('swaps red and blue and scales the colour by the alpha', () {
      // One pixel, straight RGBA as getImageData returns it for a canvas with
      // alpha: R 255, G 128, B 10, A 128. The expected bytes are worked by
      // hand: round(c * 128 / 255) is 128, 64 and 5.
      final rgba = Uint8List.fromList([255, 128, 10, 128]);
      final bgra = Uint8List(4);

      VideoFramePixels.premultiplyRgbaIntoBgra(rgba, bgra);

      expect(bgra, [5, 64, 128, 128]);
    });

    test('keeps opaque pixels and zeroes the colour of clear ones', () {
      final rgba = Uint8List.fromList([1, 2, 3, 255, 200, 100, 50, 0]);
      final bgra = Uint8List(8);

      VideoFramePixels.premultiplyRgbaIntoBgra(rgba, bgra);

      expect(bgra, [3, 2, 1, 255, 0, 0, 0, 0]);
    });

    test('writes only the frame and leaves a longer destination alone', () {
      final rgba = Uint8List.fromList([9, 9, 9, 255]);
      final bgra = Uint8List.fromList([0, 0, 0, 0, 7, 7]);

      VideoFramePixels.premultiplyRgbaIntoBgra(rgba, bgra);

      expect(bgra.sublist(4), [7, 7]);
    });
  });

  group('hasTransparency', () {
    test('is false for an opaque frame', () {
      expect(
        VideoFramePixels.hasTransparency(
          Uint8List.fromList([1, 2, 3, 255, 4, 5, 6, 255]),
        ),
        isFalse,
      );
    });

    test('is true as soon as one pixel is not fully opaque', () {
      expect(
        VideoFramePixels.hasTransparency(
          Uint8List.fromList([1, 2, 3, 255, 4, 5, 6, 254]),
        ),
        isTrue,
      );
    });
  });
}
