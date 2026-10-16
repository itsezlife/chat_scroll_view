import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_request.dart';

/// The web bakes nothing: its surfaces draw glyphs as text (the paragraph
/// strategy).
///
/// Takes the baking platforms' [request] and ignores it, so the two files are
/// interchangeable at the call site. A `residency` or a `predecessor` the
/// request carries is the caller's to dispose, as no atlas takes it over.
GlyphAtlas? createGlyphAtlasForPlatform(GlyphAtlasRequest request) => null;
