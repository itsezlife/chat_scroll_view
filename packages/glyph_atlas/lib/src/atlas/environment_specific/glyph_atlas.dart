/// Whether this platform bakes glyphs, decided by which file the build picks:
/// the hub behind [GlyphAtlas.forPlatform].
library;

export 'glyph_atlas_vm.dart' if (dart.library.js_interop) 'glyph_atlas_js.dart';
