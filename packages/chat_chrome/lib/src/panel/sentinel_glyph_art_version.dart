import 'package:catalog_assets/glyph_atlas.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/scheduler.dart';

/// The system emoji art version signal for the baked glyph cache: a pixel
/// fingerprint of a few sentinel glyphs drawn by the system rasteriser, with
/// no native call.
///
/// Joins the data layer's fingerprint (`computeGlyphArtFingerprint`, which
/// knows sentinels and hashing) with the asset layer's seam
/// (`GlyphArtVersionSource`, which knows the cache key). It draws with the same
/// rasteriser the bake uses, so a system emoji art update that redraws the
/// sentinels changes the version. It samples a few glyphs, so an update
/// confined to others goes unseen.
///
/// Computed once, on the first read (the atlas reads it at start), one
/// sentinel per frame, so it never lands more than one small render in a
/// frame; the persisted cache key holds the previous value, and a difference
/// is what makes the cached pages stale.
final class SentinelGlyphArtVersion implements GlyphArtVersionSource {
  /// Creates the source. All arguments default to production behaviour: the
  /// system font ([ParagraphGlyphRasteriser]), [defaultArtSentinelGlyphs] and
  /// the end of the next frame; tests replace them.
  SentinelGlyphArtVersion({
    GlyphRasteriser? rasteriser,
    Iterable<String> sentinels = defaultArtSentinelGlyphs,
    Future<void> Function()? nextFrame,
  }) : _version = ComputedGlyphArtVersion(() {
         final reader = GlyphPixelReader(
           rasteriser ?? ParagraphGlyphRasteriser(),
         );
         return computeGlyphArtFingerprint(
           sentinels: sentinels,
           pixelsOf: reader.pixelsOf,
           nextFrame: nextFrame ?? () => SchedulerBinding.instance.endOfFrame,
         );
       });

  final ComputedGlyphArtVersion _version;

  @override
  Future<String> read() => _version.read();
}
