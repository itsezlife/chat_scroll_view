import 'package:catalog_assets/src/atlas/atlas_sprite.dart';

/// One claim on an atlas page, given back exactly once.
///
/// A hold is a count, never pixels: whoever has one asks the source for a
/// sprite when it draws, because the page image can go away (memory pressure)
/// while the count stays. Counts belong to the holder, so nothing that happens
/// to a cache entry can change another holder's claim.
abstract interface class SpritePageHold {
  /// Whether [release] was called.
  bool get isReleased;

  /// Gives the claim back. A second call does nothing, so a count is never
  /// taken from someone else's claim.
  void release();
}

/// The one narrow seam between the asset cache and whatever bakes glyphs onto
/// atlas pages: where a glyph's sprite is, a hold on its page, and a signal
/// when pages change.
///
/// The cache's glyph media form speaks only this; it never learns how pages
/// are planned, baked, persisted or released. `GlyphAtlas` implements it, and
/// the host that plans the atlas registers it with the scope
/// (`AssetCacheScope.glyphSource`). Pages are owned by the source (the atlas's
/// residency), shared by every binding that holds them, never by a binding.
///
/// ## Contract
///
/// - [spriteOf] is null for a glyph the source does not know, for one whose
///   page is not baked and loaded yet, and after the source is gone. It may
///   have a side effect (asking for a released page queues its reload), so it
///   is called when painting, not to poll. A sprite is for the call that asked
///   for it: ask again to draw.
/// - [holdPageOf] is null for a glyph the source does not know. Otherwise the
///   page stays resident while the hold does (the source's own retention and
///   pressure rules decide the rest).
/// - Page listeners hear the index of each page whose drawability changed:
///   once its sprites can be drawn and again when it is released.
/// - [waitsForSprite] says how a surface bridges the time before a sprite:
///   with its placeholder (a glyph of the source's background bake) or with
///   the glyph drawn as text (one the source does not know, or bakes on
///   demand).
abstract interface class GlyphSpriteSource {
  /// The sprite of [glyph], or null (see the class contract).
  AtlasSprite? spriteOf(String glyph);

  /// Claims the page [glyph] is on, or returns null for an unknown glyph.
  SpritePageHold? holdPageOf(String glyph);

  /// Whether a surface shows its placeholder while [glyph] has no sprite,
  /// rather than drawing the glyph as text.
  ///
  /// True for the glyphs of the background bake: drawing them as text while
  /// it runs would lay out a paragraph for every cell of every scrolled frame,
  /// which is what baking avoids. False for a glyph the source does not know
  /// and for one it bakes on demand (a tone the user just chose, an emoji
  /// typed elsewhere): there are few of them, and a circle where the user
  /// expects the emoji they chose reads as a failure.
  bool waitsForSprite(String glyph);

  /// Calls [listener] with the index of each page whose drawability changed.
  void addPageListener(void Function(int pageIndex) listener);

  /// Removes a listener added with [addPageListener].
  void removePageListener(void Function(int pageIndex) listener);
}
