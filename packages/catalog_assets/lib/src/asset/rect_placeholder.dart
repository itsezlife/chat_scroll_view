import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';

/// The default stand-in of media (a GIF, a clip, a picture) that has nothing to
/// show yet: the whole rectangle in one quiet colour.
///
/// The reference client draws no shape for media: a grid cell that waits for
/// its image shows `key_sharedMedia_photoPlaceholder` (`0xFFEDF3F7` in the
/// default theme) across the full cell, with no radius of its own
/// (`ContextLinkCell.onDraw`, `canvas.drawRect(0, 0, w, h)`), and the loader
/// sits over it. A corner radius belongs to the surface: a binding clips what
/// it paints to `AssetProfile.cornerRadius`, so the rectangle follows the
/// cell's corners with no radius here. The circle is the stand-in of a glyph
/// (`CirclePlaceholder`), which has a box and no edges.
///
/// The colour is the context's tint, drawn as given (a host passes one of its
/// quiet theme tokens); without one it is the reference's. Synchronous,
/// shared, never disposed; no sprite and no animation.
final class RectPlaceholder extends AssetPaintable {
  /// Creates the placeholder.
  const RectPlaceholder();

  /// `key_sharedMedia_photoPlaceholder` in the default theme.
  static const Color fallbackColor = Color(0xFFEDF3F7);

  // Painting is single-threaded and the paint is set fully on every call.
  static final Paint _paint = Paint();

  @override
  AtlasSprite? get sprite => null;

  @override
  bool get isAnimated => false;

  @override
  bool get isHolding => false;

  @override
  bool restart() => false;

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    if (rect.isEmpty) return;
    final base = context.tint ?? fallbackColor;
    _paint.color = base.withValues(alpha: base.a * context.opacity);
    canvas.drawRect(rect, _paint);
  }

  @override
  void dispose() {}
}
