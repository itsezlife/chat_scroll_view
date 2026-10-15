import 'dart:ui';

import 'package:meta/meta.dart';

/// A baked glyph ready to draw: the page image it sits on and the rectangle of
/// its pixels on that page.
///
/// This is the optional sprite capability of a catalog asset. A surface that
/// finds one draws the rectangle of [page] instead of painting the asset
/// itself, and draws every sprite of one page in a single batch; an asset
/// without one paints itself.
///
/// The [page] handle belongs to the page residency of the [GlyphAtlas] that
/// handed the sprite out and is disposed when the page is released (retention
/// elapsed, memory pressure, or the atlas going away). A sprite is for use
/// within the call that asked for it, never to be kept: ask again to learn
/// whether the pixels are still there.
///
/// [GlyphAtlas]: package:catalog_assets/glyph_atlas.dart
@immutable
final class AtlasSprite {
  /// Creates a sprite cut from [source] on [page], page number [pageIndex].
  const AtlasSprite({
    required this.pageIndex,
    required this.page,
    required this.source,
  });

  /// Which page of the atlas this is; sprites with the same index share
  /// [page], so a surface groups its draws by it.
  final int pageIndex;

  /// The page pixels.
  final Image page;

  /// Where the glyph is on [page], in page pixels.
  final Rect source;
}
