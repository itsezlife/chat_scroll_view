/// Baked glyph atlas: planning, rasterising and paging colour glyphs.
///
/// A **bake** rasterises the glyphs the data layer supplies, a few per frame,
/// into fixed-size **glyph atlas pages**; a **baked glyph** is then addressed
/// as a page plus a source rectangle (a sprite). The rasteriser and the page
/// store are seams; their fakes and contract suites are in `testing.dart`. The
/// resident pages are owned by a `GlyphPageResidency`: held per page by the
/// bindings that draw them and by the open panel, kept for a retention after
/// the last hold, and released at once under memory pressure.
library;

export 'src/atlas/atlas_sprite.dart';
export 'src/atlas/cache/computed_glyph_art_version.dart';
export 'src/atlas/cache/glyph_art_version_source.dart';
export 'src/atlas/cache/glyph_atlas_persistence.dart';
export 'src/atlas/cache/glyph_cache_key.dart';
export 'src/atlas/cache/glyph_cache_store.dart';
export 'src/atlas/cache/memory_glyph_cache_store.dart';
export 'src/atlas/bake_frame_source.dart';
export 'src/atlas/bake_governor.dart';
export 'src/atlas/bake_pause_signals.dart';
export 'src/atlas/glyph_atlas.dart';
export 'src/atlas/glyph_atlas_index.dart';
export 'src/atlas/glyph_atlas_layout.dart';
export 'src/atlas/glyph_bake_observer.dart';
export 'src/atlas/glyph_bake_scheduler.dart';
export 'src/atlas/glyph_baker.dart';
export 'src/atlas/glyph_page_residency.dart';
export 'src/atlas/glyph_pixel_reader.dart';
export 'src/atlas/glyph_page_store.dart';
export 'src/atlas/glyph_rasteriser.dart';
export 'src/atlas/memory_glyph_page_store.dart';
export 'src/atlas/paragraph_glyph_rasteriser.dart';
export 'src/atlas/platform/glyph_atlas_platform.dart';
export 'src/atlas/platform/glyph_cache_store_platform.dart';
export 'src/atlas/scheduler_bake_frame_source.dart';
export 'src/atlas/system_memory_pressure.dart';
