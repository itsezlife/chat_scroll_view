/// Whether this platform bakes glyphs, decided by which file the build picks.
///
/// Android, iOS and desktop bake emoji into atlas pages and draw sprites. The
/// web keeps drawing glyphs as text until it is measured; it must not start a
/// bake, and a platform fork is a boundary between two files, not a condition
/// inside one.
library;

export 'glyph_atlas_platform_baking.dart'
    if (dart.library.js_interop) 'glyph_atlas_platform_web.dart';
