import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_request.dart';

/// The web hook behind [GlyphAtlas.forPlatform]: the web bakes nothing, and its
/// surfaces draw glyphs as text (the paragraph strategy) until it is measured.
///
/// The [request] is ignored, so a `residency` or `predecessor` it carries is
/// the caller's to dispose, as no atlas takes it over.
GlyphAtlas? $createGlyphAtlas(GlyphAtlasRequest request) => null;
