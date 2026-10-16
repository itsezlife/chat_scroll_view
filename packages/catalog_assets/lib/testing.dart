/// Fakes and contract suites for the seams of `catalog_assets`.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/asset/testing/fake_asset_paintable.dart';
export 'src/asset/testing/fake_asset_producer.dart';
export 'src/atlas/testing/bake_frame_source_contract.dart';
export 'src/atlas/testing/fake_bake_frame_source.dart';
export 'src/atlas/testing/fake_glyph_art_version_source.dart';
export 'src/atlas/testing/fake_glyph_bake_observer.dart';
export 'src/atlas/testing/fake_glyph_cache_store.dart';
export 'src/atlas/testing/fake_glyph_page_store.dart';
export 'src/atlas/testing/fake_glyph_rasteriser.dart';
export 'src/atlas/testing/glyph_baker_helpers.dart';
export 'src/atlas/testing/glyph_cache_store_contract.dart';
export 'src/atlas/testing/glyph_page_store_contract.dart';
export 'src/atlas/testing/glyph_rasteriser_contract.dart';
export 'src/atlas/testing/image_pixels.dart';
export 'src/atlas/testing/manual_bake_clock.dart';
export 'src/atlas/testing/manual_memory_pressure.dart';
export 'src/atlas/testing/manual_retention_timers.dart';
export 'src/atlas/testing/sample_glyph_catalogue.dart';
export 'src/embed/testing/fake_inline_embed.dart';
export 'src/embed/testing/inline_embed_contract.dart';
export 'src/embed/testing/inline_embed_resolver_contract.dart';
export 'src/glyph/testing/fake_glyph_sprite_source.dart';
export 'src/glyph/testing/glyph_sprite_source_contract.dart';
export 'src/pipeline/testing/asset_fetcher_contract.dart';
export 'src/pipeline/testing/decoder_contract.dart';
export 'src/pipeline/testing/fake_decoder.dart';
export 'src/pipeline/testing/fake_fetcher.dart';
export 'src/pipeline/testing/manual_clock.dart';
export 'src/playback/testing/manual_playback_tick_source.dart';
export 'src/playback/testing/playback_tick_source_contract.dart';
