import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';
import 'package:catalog_assets/src/atlas/testing/image_pixels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Behaviour every [GlyphRasteriser] must have, for adapter authors and hosts.
abstract final class GlyphRasteriserContract {
  /// Runs it as a test group. [create] makes a fresh rasteriser. [glyphs] are
  /// glyphs it can draw; pass the widest ones the platform has (a family
  /// sequence, a flag) to check they do not spill into the gutter.
  static void run(
    String name,
    GlyphRasteriser Function() create, {
    List<String> glyphs = const <String>['A'],
  }) {
    group('GlyphRasteriser contract: $name', () {
      // A cell sitting in the middle of a canvas with a margin all round, in
      // physical pixels, like a cell inside a strip.
      const cell = Rect.fromLTWH(40, 40, 72, 72);
      const size = 152.0;

      Future<ImagePixels> paintOne(GlyphRasteriser rasteriser, String glyph) {
        final recorder = PictureRecorder();
        rasteriser.paint(Canvas(recorder), glyph, cell);
        final picture = recorder.endRecording();
        final image = picture.toImageSync(size.toInt(), size.toInt());
        picture.dispose();
        return ImagePixels.of(image).whenComplete(image.dispose);
      }

      for (final glyph in glyphs) {
        test('paints ink inside the cell for $glyph', () async {
          final pixels = await paintOne(create(), glyph);

          expect(pixels.hasInk(cell), isTrue);
        });

        test(
          'leaves the gutter around the cell transparent for $glyph',
          () async {
            final pixels = await paintOne(create(), glyph);

            // Ink outside the cell would bleed into a neighbouring sprite.
            expect(pixels.hasInk(const Rect.fromLTWH(0, 0, size, 40)), isFalse);
            expect(
              pixels.hasInk(const Rect.fromLTWH(0, 112, size, 40)),
              isFalse,
            );
            expect(pixels.hasInk(const Rect.fromLTWH(0, 0, 40, size)), isFalse);
            expect(
              pixels.hasInk(const Rect.fromLTWH(112, 0, 40, size)),
              isFalse,
            );
          },
        );

        test('paints the same pixels each time for $glyph', () async {
          final rasteriser = create();
          final first = await paintOne(rasteriser, glyph);
          final second = await paintOne(rasteriser, glyph);

          for (var y = 40; y < 112; y += 7) {
            for (var x = 40; x < 112; x += 7) {
              expect(second.at(x, y), first.at(x, y), reason: '($x, $y)');
            }
          }
        });
      }
    });
  }
}
