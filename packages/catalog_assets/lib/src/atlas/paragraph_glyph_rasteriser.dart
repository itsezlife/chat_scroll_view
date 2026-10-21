import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';
import 'package:catalog_assets/src/glyph/text_glyph_producer.dart';

/// Draws a glyph as a text paragraph in the system font, so a baked glyph looks
/// exactly like the same emoji in the composer and in message text.
///
/// This is the only place a glyph is drawn as text; the bake runs it once per
/// glyph and scroll time draws the resulting sprite instead. The font size is
/// [fontScale] of the cell: an emoji advance is wider than its em, and the
/// default of 0.85 keeps the widest sequences inside their cell. A sequence
/// the font cannot form into one glyph is drawn as nothing.
final class ParagraphGlyphRasteriser implements GlyphRasteriser {
  /// Creates a rasteriser whose font size is [fontScale] of the cell height.
  ParagraphGlyphRasteriser({
    this.fontScale = TextGlyphProducer.defaultFontScale,
  });

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
    // A glyph the font forms is one cluster and stays on one line. A sequence
    // it has no glyph for (a joined emoji its font lacks) falls back to its
    // parts side by side, wraps, and would show as their halves stacked and
    // cut by the cell; it is drawn as nothing, which a glyph-support probe
    // reads as a glyph the system cannot draw.
    if (paragraph.computeLineMetrics().length > 1) {
      paragraph.dispose();
      return;
    }
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
