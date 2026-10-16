import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:content_model/content_model.dart';

/// The `AssetProducer` of a platform that draws unicode glyphs as text: it
/// answers a unicode key at once with a paintable that paints the glyph as a
/// paragraph in the system font, and hands every other key to the producer it
/// wraps.
///
/// This is the paragraph strategy of the glyph media form, for a platform
/// where no atlas is baked (the web). A host composes it as the producer of
/// its scope **only where it registers no `glyphSource`**: on a platform that
/// bakes, glyphs bind to baked sprites and a paragraph at scroll time is
/// exactly what the glyph form avoids.
///
/// ## What a glyph costs
///
/// A glyph is an ordinary entry. It is final (`AssetStage.full`) on attach,
/// never animated, and counted against the still budget as
/// [paragraphBytes], an estimate of the engine memory its paragraph holds, so
/// the byte-budgeted LRU bounds how many paragraphs stay alive. The
/// paragraph is laid out when the glyph is first painted and again only when
/// the rectangle's size changes; drawing it afterwards is one
/// `Canvas.drawParagraph`. A glyph keeps its own colours: a tint does not
/// apply.
final class TextGlyphProducer implements AssetProducer {
  /// Creates a producer that wraps [next] for every key but a unicode one
  /// (without [next] those entries stay at `AssetStage.none`).
  ///
  /// [fontScale] is the glyph's font size as a fraction of the shorter side
  /// of the rectangle: an emoji advance is wider than its em, and 0.85 keeps
  /// the widest sequences inside the box.
  const TextGlyphProducer({
    this.next,
    this.paragraphBytes = 16 * 1024,
    this.fontScale = 0.85,
  }) : assert(paragraphBytes > 0, 'a paragraph costs memory'),
       assert(fontScale > 0, 'the font needs a size');

  /// The producer for content that is not a unicode glyph, or null.
  final AssetProducer? next;

  /// What one laid-out paragraph counts against the still budget.
  final int paragraphBytes;

  /// Font size as a fraction of the shorter side of the painted rectangle.
  final double fontScale;

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    final key = request.key;
    if (key is ContentKey$Unicode) {
      progress.advance(
        AssetStage.full,
        _TextGlyphPaintable(key.sequence, fontScale),
        bytes: paragraphBytes,
      );
      return const _FinishedTask();
    }
    return next?.produce(request, progress, demand) ?? const _FinishedTask();
  }
}

final class _FinishedTask implements AssetTask {
  const _FinishedTask();

  @override
  void cancel() {}
}

final class _TextGlyphPaintable implements AssetPaintable {
  _TextGlyphPaintable(this._glyph, this._fontScale);

  final String _glyph;
  final double _fontScale;
  Paragraph? _paragraph;
  double _laidOutFor = 0;
  double _laidOutWidth = 0;

  // Single-threaded painting sets the paint fully on every use.
  static final Paint _fade = Paint();

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
    canvas
      ..save()
      // Clipped, so a sequence wider than the box cannot bleed out of it.
      ..clipRect(rect)
      ..drawParagraph(
        paragraph,
        Offset(rect.left, rect.top + (rect.height - paragraph.height) / 2),
      )
      ..restore();
    if (fades) canvas.restore();
  }

  Paragraph _paragraphFor(Rect rect) {
    final fontSize = rect.shortestSide * _fontScale;
    final cached = _paragraph;
    if (cached != null &&
        _laidOutFor == fontSize &&
        _laidOutWidth == rect.width) {
      return cached;
    }
    cached?.dispose();
    _laidOutFor = fontSize;
    _laidOutWidth = rect.width;
    return _paragraph =
        (ParagraphBuilder(
            ParagraphStyle(textAlign: TextAlign.center, fontSize: fontSize),
          )..addText(_glyph)).build()
          ..layout(ParagraphConstraints(width: rect.width));
  }

  @override
  void dispose() {
    _paragraph?.dispose();
    _paragraph = null;
  }
}
