import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/glyph/text_glyph_paintable.dart';
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
/// the rectangle's size changes or the system fonts do (a scope given the
/// engine's `systemFonts` signal); drawing it afterwards is one
/// `Canvas.drawParagraph`, inside a clip only for a sequence wider than the
/// rectangle. A glyph keeps its own colours: a tint does not apply.
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
    this.fontScale = defaultFontScale,
  }) : assert(paragraphBytes > 0, 'a paragraph costs memory'),
       assert(fontScale > 0, 'the font needs a size');

  /// The font size of a glyph as a fraction of the box it is drawn in, for the
  /// paragraph strategy here and for the baked one
  /// (`ParagraphGlyphRasteriser`): the one number a surface that draws an
  /// emoji next to the grid (a variant picker) reads to look the same.
  static const double defaultFontScale = 0.85;

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
    if (request.key case ContentKey$Unicode(:final sequence)) {
      progress.advance(
        AssetStage.full,
        TextGlyphPaintable(sequence, fontScale: fontScale),
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
