import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';

/// Draws a glyph as a text paragraph in the system font, so a baked glyph looks
/// exactly like the same emoji in the composer and in message text.
///
/// This is the only place a glyph is drawn as text; the bake runs it once per
/// glyph and scroll time draws the resulting sprite instead. The font size is
/// [fontScale] of the cell: an emoji advance is wider than its em, and the
/// default of 0.85 keeps the widest sequences inside their cell.
final class ParagraphGlyphRasteriser implements GlyphRasteriser {
  /// Creates a rasteriser whose font size is [fontScale] of the cell height.
  ParagraphGlyphRasteriser({this.fontScale = 0.85});

  /// Font size as a fraction of the cell edge.
  final double fontScale;

  @override
  void paint(Canvas canvas, String glyph, Rect cell) {
    final paragraph = (ParagraphBuilder(
      ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: cell.height * fontScale,
      ),
    )..addText(glyph)).build()..layout(ParagraphConstraints(width: cell.width));
    canvas
      // Clipped, so a sequence wider than the cell cannot bleed into the gutter.
      ..save()
      ..clipRect(cell)
      ..drawParagraph(
        paragraph,
        Offset(cell.left, cell.top + (cell.height - paragraph.height) / 2),
      )
      ..restore();
    paragraph.dispose();
  }
}
