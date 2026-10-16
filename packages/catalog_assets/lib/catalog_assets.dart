/// The asset cache core: what a surface binds to, how far an asset has come,
/// how long it is kept, and what advances its animation.
///
/// A host creates one `AssetCacheScope` and hands it to the surfaces that draw
/// content. A surface calls `attach(key, spec, profile)` and gets an
/// `AssetBinding`: a staged readiness (`none`, `placeholder`, `firstFrame`,
/// `full`, never a failed one), an `AssetPaintable` to draw, and a pin that
/// keeps the entry in a byte-budgeted LRU until `detach`. Content is made
/// behind the `AssetProducer` seam (`AssetPipeline` resolves, fetches through
/// the host's `ContentFetcher` and decodes with its `Decoder`s); unicode glyphs bind to baked sprites on an
/// atlas page through the narrow `GlyphSpriteSource` seam (the atlas itself is
/// `glyph_atlas.dart`). One `PlaybackClock` advances every animation, gated per
/// binding and by host-set pause layers.
///
/// Surfaces draw content through `ContentView` (a widget, with the scope
/// handed down by `AssetCacheProvider`) or, inside text a body paints itself,
/// through an `InlineEmbed` (`ContentEmbed` is the adapter over a binding).
/// `AssetPresets` names the size, spec and profile of the common surfaces.
///
/// Single-threaded on the UI isolate; no static state.
library;

export 'src/asset/asset_binding.dart';
export 'src/asset/asset_cache_budgets.dart';
export 'src/asset/asset_cache_scope.dart';
export 'src/asset/asset_paintable.dart';
export 'src/asset/asset_preset.dart';
export 'src/asset/asset_producer.dart';
export 'src/asset/asset_profile.dart';
export 'src/asset/asset_readiness.dart';
export 'src/asset/asset_spec.dart';
export 'src/atlas/atlas_sprite.dart';
export 'src/embed/content_embed.dart';
export 'src/embed/content_embed_resolver.dart';
export 'src/embed/inline_embed.dart';
export 'src/glyph/glyph_sprite_source.dart';
export 'src/glyph/text_glyph_producer.dart';
export 'src/pipeline/asset_pipeline.dart';
export 'src/pipeline/cancellation_token.dart';
export 'src/pipeline/content_fetcher.dart';
export 'src/pipeline/decoder.dart';
export 'src/playback/playback_clock.dart' show PlaybackClock;
export 'src/playback/playback_policy.dart';
export 'src/playback/playback_tick_source.dart';
export 'src/playback/scheduler_playback_tick_source.dart';
export 'src/widget/asset_cache_provider.dart';
export 'src/widget/content_view.dart';
