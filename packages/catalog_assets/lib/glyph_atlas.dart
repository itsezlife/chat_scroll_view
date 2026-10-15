/// Baked glyph atlas: planning, rasterising and paging colour glyphs.
///
/// A **bake** rasterises the glyphs the data layer supplies, a few per frame,
/// into fixed-size **glyph atlas pages**; a **baked glyph** is then addressed
/// as a page plus a source rectangle (a sprite). The rasteriser and the page
/// store are seams; their fakes and contract suites are in `testing.dart`.
library;

export 'src/atlas/atlas_sprite.dart';
export 'src/atlas/bake_frame_source.dart';
export 'src/atlas/bake_governor.dart';
export 'src/atlas/bake_pause_signals.dart';
export 'src/atlas/glyph_atlas.dart';
export 'src/atlas/glyph_atlas_index.dart';
export 'src/atlas/glyph_atlas_layout.dart';
export 'src/atlas/glyph_bake_scheduler.dart';
export 'src/atlas/glyph_baker.dart';
export 'src/atlas/glyph_page_store.dart';
export 'src/atlas/glyph_rasteriser.dart';
export 'src/atlas/memory_glyph_page_store.dart';
export 'src/atlas/paragraph_glyph_rasteriser.dart';
export 'src/atlas/platform/glyph_atlas_platform.dart';
export 'src/atlas/scheduler_bake_frame_source.dart';
