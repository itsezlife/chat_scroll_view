import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_request.dart';

/// The atlas for a platform that bakes glyphs: android, iOS and desktop.
///
/// The web counterpart takes the same [request] and returns null. A
/// `residency` or `predecessor` the request carries is owned by the atlas from
/// then on.
GlyphAtlas? createGlyphAtlasForPlatform(GlyphAtlasRequest request) =>
    request.build();
