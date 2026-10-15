import 'package:catalog_assets/src/atlas/bake_frame_source.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_atlas_persistence.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_index.dart';
import 'package:catalog_assets/src/atlas/glyph_page_residency.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/glyph_rasteriser.dart';
import 'package:flutter/foundation.dart';

/// The web bakes nothing: its surfaces draw glyphs as text (the paragraph
/// strategy), exactly as before the bake existed.
///
/// Takes the arguments of the baking platforms' factory and ignores them, so
/// the two files are interchangeable at the call site. A `residency` it is
/// given is the caller's to dispose, as no atlas takes it over.
GlyphAtlas? createGlyphAtlasForPlatform({
  required GlyphAtlasIndex index,
  required GlyphRasteriser rasteriser,
  GlyphPageStore? store,
  GlyphAtlasPersistence? persistence,
  required BakeFrameSource frames,
  required BakeClock clock,
  required ValueListenable<bool> panelVisible,
  required ValueListenable<bool> panelOpening,
  GlyphPageResidency? residency,
}) => null;
