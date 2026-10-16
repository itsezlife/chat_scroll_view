import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';

/// A [GlyphRasteriser] that needs no emoji font: it fills the glyph's cell with
/// one opaque colour derived from the glyph, so a test can tell which glyph
/// ended up where by reading a pixel ([colorFor]).
final class FakeGlyphRasteriser implements GlyphRasteriser {
  /// Creates a fake; [onPaint] runs after each glyph is painted, so a test can
  /// advance a clock to model a slow glyph or throw to model a missing font.
  FakeGlyphRasteriser({this.onPaint});

  /// Called with each glyph after it is painted, or null.
  final void Function(String glyph)? onPaint;

  /// Glyphs painted so far, in order (one entry per [paint] call).
  final List<String> painted = <String>[];

  /// The opaque colour [paint] fills the cell of [glyph] with. Stable across
  /// runs (FNV-1a over the code units), distinct for distinct short glyphs.
  static Color colorFor(String glyph) {
    var hash = 0x811C9DC5;
    for (final unit in glyph.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return Color(0xFF000000 | (hash & 0x00FFFFFF));
  }

  @override
  void paint(Canvas canvas, String glyph, Rect cell) {
    painted.add(glyph);
    canvas.drawRect(
      cell,
      Paint()
        ..color = colorFor(glyph)
        ..isAntiAlias = false,
    );
    onPaint?.call(glyph);
  }
}
