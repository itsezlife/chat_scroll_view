import 'package:catalog_assets/src/atlas/bake_frame_source.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_index.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';
import 'package:flutter/foundation.dart';

/// The atlas for a platform that bakes glyphs: android, iOS and desktop.
///
/// Arguments are those of [GlyphAtlas]; the web counterpart takes the same and
/// returns null.
GlyphAtlas? createGlyphAtlasForPlatform({
  required GlyphAtlasIndex index,
  required GlyphRasteriser rasteriser,
  required GlyphPageStore store,
  required BakeFrameSource frames,
  required BakeClock clock,
  required ValueListenable<bool> panelVisible,
  required ValueListenable<bool> panelOpening,
}) => GlyphAtlas(
  index: index,
  rasteriser: rasteriser,
  store: store,
  frames: frames,
  clock: clock,
  panelVisible: panelVisible,
  panelOpening: panelOpening,
);
