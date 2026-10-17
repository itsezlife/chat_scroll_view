import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/foundation.dart';

/// How a host builds the [AssetCacheScope] the pages draw through.
///
/// A scope decides how unicode glyphs are drawn, and a page cannot tell from
/// the scope whether a baked atlas will ever exist, so the choice is made
/// once, where the scope is made:
///
/// - With a `glyphSource` (a glyph atlas) glyphs are baked sprites: a circle
///   until their page exists, then one batched atlas draw per page.
/// - Without one, glyphs are drawn as text by [TextGlyphProducer], which this
///   composes in front of the host's own producer. A platform that bakes
///   nothing (the web) is this case, and so is a host whose atlas does not
///   exist yet.
///
/// The text path is composed whether or not an atlas is registered because the
/// producer only ever sees unicode keys the glyph source did not take. The
/// strategy follows the source for the life of a glyph, not only when it
/// attaches: glyphs drawn as text move onto an atlas registered later, and
/// glyphs on an atlas that is dropped go back to the text path (never to a
/// placeholder that stays); the viewport never decides the strategy.
abstract final class PageAssets {
  /// A scope that draws unicode glyphs through [glyphSource] when given and as
  /// text otherwise, and everything else through [producer].
  ///
  /// [systemFonts] is the engine's signal that its fonts changed
  /// (`PaintingBinding.systemFonts`): glyphs drawn as text lay out again on
  /// it, since a browser fetches the font that draws an emoji only once it
  /// meets one. A host that draws glyphs as text passes it.
  ///
  /// The caller owns the scope and disposes it.
  static AssetCacheScope createScope({
    AssetProducer? producer,
    GlyphSpriteSource? glyphSource,
    AssetCacheBudgets budgets = AssetCacheBudgets.defaults,
    PlaybackClock? clock,
    Listenable? memoryPressure,
    Listenable? systemFonts,
  }) => AssetCacheScope(
    producer: TextGlyphProducer(next: producer),
    glyphSource: glyphSource,
    budgets: budgets,
    clock: clock,
    memoryPressure: memoryPressure,
    systemFonts: systemFonts,
  );
}
