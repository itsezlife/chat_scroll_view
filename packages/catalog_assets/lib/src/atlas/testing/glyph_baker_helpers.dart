import 'package:catalog_assets/src/atlas/glyph_atlas_index.dart';
import 'package:catalog_assets/src/atlas/glyph_baker.dart';

/// Test conveniences over a [GlyphBaker]: running it to completion without a
/// scheduler and asking what a surface could draw. The baker itself offers
/// neither, because a host drives it through `GlyphBakeScheduler` and draws
/// through `GlyphAtlas`.
extension GlyphBakerTesting on GlyphBaker {
  /// Bakes everything: one [GlyphBaker.step] per frame, waiting for
  /// [nextFrame] before each. A fixed pace.
  Future<void> bakeAll({
    required int glyphsPerFrame,
    required Future<void> Function() nextFrame,
  }) async {
    while (!isComplete) {
      await nextFrame();
      await step(glyphs: glyphsPerFrame);
    }
  }

  /// Planned sprite of [glyph], or null when it is unknown or its page is not
  /// baked yet.
  GlyphSprite? spriteOf(String glyph) {
    final planned = index.placementOf(glyph);
    return planned != null && isPageBaked(planned.pageIndex) ? planned : null;
  }
}
