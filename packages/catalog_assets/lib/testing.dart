/// Fakes and contract suites for the seams of `catalog_assets`.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/atlas/testing/bake_frame_source_contract.dart';
export 'src/atlas/testing/fake_bake_frame_source.dart';
export 'src/atlas/testing/fake_glyph_art_version_source.dart';
export 'src/atlas/testing/fake_glyph_bake_observer.dart';
export 'src/atlas/testing/fake_glyph_cache_store.dart';
export 'src/atlas/testing/fake_glyph_page_store.dart';
export 'src/atlas/testing/fake_glyph_rasteriser.dart';
export 'src/atlas/testing/glyph_cache_store_contract.dart';
export 'src/atlas/testing/glyph_page_store_contract.dart';
export 'src/atlas/testing/glyph_rasteriser_contract.dart';
export 'src/atlas/testing/image_pixels.dart';
export 'src/atlas/testing/manual_bake_clock.dart';
export 'src/atlas/testing/manual_memory_pressure.dart';
export 'src/atlas/testing/manual_retention_timers.dart';
