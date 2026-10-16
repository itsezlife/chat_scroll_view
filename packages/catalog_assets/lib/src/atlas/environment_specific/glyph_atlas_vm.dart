import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas_request.dart';

/// The VM hook behind [GlyphAtlas.forPlatform]: android, iOS and desktop bake
/// emoji into atlas pages and draw sprites.
///
/// A `residency` or `predecessor` the request carries is owned by the atlas
/// from then on.
GlyphAtlas? $createGlyphAtlas(GlyphAtlasRequest request) => request.build();
