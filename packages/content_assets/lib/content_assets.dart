/// Chat content on `mpx_core`'s asset cache, by `ContentKey`.
///
/// `ContentAssetScope` is where surfaces attach content: media goes to the
/// media core's `AssetCacheScope` under its `MediaKey`
/// (`ContentKeyMedia.mediaKey`), unicode glyphs to the glyph atlas or are
/// drawn as text (`GlyphBinding`). `ContentAssetView` shows any content in a
/// widget tree, `ContentEmbed` in message text. `ContentMediaResolver` lets
/// the media core resolve bare keys through the chat's `ContentResolver`, and
/// `ContentAssetPresets` names the chat's surfaces.
///
/// Hosts import `mpx_core` and `glyph_atlas` for their types: nothing is
/// re-exported.
library;

export 'src/embed/content_embed.dart';
export 'src/embed/content_embed_overlay.dart';
export 'src/embed/content_embed_resolver.dart';
export 'src/embed/inline_embed.dart';
export 'src/glyph/glyph_binding.dart';
export 'src/identity/content_media.dart';
export 'src/preset/content_asset_presets.dart';
export 'src/scope/content_asset_scope.dart';
export 'src/widget/content_asset_view.dart';
