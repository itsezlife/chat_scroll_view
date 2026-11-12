import 'dart:ui';

import 'package:meta/meta.dart';

/// A baked glyph or a rendered animation frame ready to draw: the page image it
/// sits on and the rectangle of its pixels on that page.
///
/// This is the optional sprite capability of an `AssetPaintable`. A surface
/// that finds one draws the rectangle of [page] instead of painting the asset
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

  /// Which page of its atlas this is. Two atlases number their pages alike, so
  /// the index does not tell sprites of different atlases apart: a surface
  /// groups its draws by [page] itself, which is one image for every sprite
  /// cut from the same page.
  final int pageIndex;

  /// The page pixels.
  final Image page;

  /// Where the glyph is on [page], in page pixels.
  final Rect source;
}
