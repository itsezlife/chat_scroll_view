import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/glyph/text_glyph_producer.dart';

/// A unicode glyph painted as a paragraph in the system font, laid out for the
/// rectangle it is drawn in and again only when that size changes.
///
/// The paragraph strategy of the glyph form: the paintable of
/// [TextGlyphProducer] on a platform that bakes nothing, and what a glyph
/// binding draws while a source has no sprite for a glyph it does not make a
/// surface wait for. Internal to the package.
final class TextGlyphPaintable implements AssetPaintable {
  /// A paintable for [glyph], its font [fontScale] of the box's shorter side.
  TextGlyphPaintable(
    this._glyph, {
    double fontScale = TextGlyphProducer.defaultFontScale,
  }) : _fontScale = fontScale;

  final String _glyph;
  final double _fontScale;
  Paragraph? _paragraph;
  double _laidOutFor = 0;
  double _laidOutWidth = 0;
  // Known once per layout: asking the engine for it on every draw would cost
  // more than the clip it saves.
  bool _overflows = false;

  // Single-threaded painting sets the paint fully on every use.
  static final Paint _fade = Paint();

  // Logical pixels below which two sizes are the same layout.
  static const double _layoutTolerance = 1e-3;

  @override
  AtlasSprite? get sprite => null;

  @override
  bool get isAnimated => false;

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    final paragraph = _paragraphFor(rect);
    final fades = context.opacity < 1;
    if (fades) {
      canvas.saveLayer(
        rect,
        _fade..color = Color.fromRGBO(0, 0, 0, context.opacity),
      );
    }
    final at = Offset(
      rect.left,
      rect.top + (rect.height - paragraph.height) / 2,
    );
    // Clipped only when a sequence is wider than the box, so it cannot bleed
    // out of it. Nearly every glyph fits, and a save and a clip per cell of a
    // screenful are most of what drawing one costs.
    if (_overflows) {
      canvas
        ..save()
        ..clipRect(rect)
        ..drawParagraph(paragraph, at)
        ..restore();
    } else {
      canvas.drawParagraph(paragraph, at);
    }
    if (fades) canvas.restore();
  }

  Paragraph _paragraphFor(Rect rect) {
    final fontSize = rect.shortestSide * _fontScale;
    final cached = _paragraph;
    // A rectangle's width is `right - left`, so the same size at two positions
    // differs in the last bits; a tolerance keeps one paragraph for all of
    // them instead of laying it out again at every cell it is drawn in.
    if (cached != null &&
        (_laidOutFor - fontSize).abs() < _layoutTolerance &&
        (_laidOutWidth - rect.width).abs() < _layoutTolerance) {
      return cached;
    }
    cached?.dispose();
    _laidOutFor = fontSize;
    _laidOutWidth = rect.width;
    final laidOut =
        (ParagraphBuilder(
            ParagraphStyle(textAlign: TextAlign.center, fontSize: fontSize),
          )..addText(_glyph)).build()
          ..layout(ParagraphConstraints(width: rect.width));
    _overflows = laidOut.longestLine > rect.width;
    return _paragraph = laidOut;
  }

  @override
  void dispose() {
    _paragraph?.dispose();
    _paragraph = null;
  }
}
