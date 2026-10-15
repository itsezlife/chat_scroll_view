import 'dart:ui';

/// Seam between the baker and whatever draws a colour glyph: the system emoji
/// font in production, predictable pixels in tests.
///
/// The baker owns the canvas, the strip image and the page; a rasteriser only
/// paints one glyph. That keeps the part that needs a font as small as one
/// method, and lets the baker be tested without an emoji font.
///
/// Contract (run [runGlyphRasteriserContract] against an implementation):
///
/// - [paint] draws only inside [cell]; the gutter around it stays transparent,
///   so sampling a sprite near its edge never picks up a neighbour;
/// - painting is synchronous and keeps no reference to [canvas];
/// - the canvas is in physical pixels (no density scale): [cell] is the glyph's
///   baked size in pixels.
///
/// [runGlyphRasteriserContract]: package:catalog_assets/testing.dart
abstract interface class GlyphRasteriser {
  /// Draws [glyph] filling [cell] on [canvas].
  void paint(Canvas canvas, String glyph, Rect cell);
}
