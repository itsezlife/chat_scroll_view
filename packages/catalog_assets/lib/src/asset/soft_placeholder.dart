import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';

/// A quiet stand-in for content that has no outline to show yet (a sticker in
/// a message): a faint rounded square on the shorter side of the rectangle,
/// in the context's tint (`0xFF73787B` when there is none).
///
/// The fill's alpha is 25 of 255, a tenth of the placeholder colour's alpha,
/// truncated. The outline comes with the sticker's metadata, which this package
/// never sees, so the shape is a rounded square. [cornerFraction] is this
/// package's own choice, not a traced measure. A sweeping highlight is left
/// out: a message body does not repaint on its own, and a placeholder that
/// needs frames from nobody is the one that costs nothing.
///
/// Synchronous, shared, never disposed; no sprite and no animation. An
/// embed paints it before its content has a thumbnail (`ContentEmbed.placeholder`).
final class SoftPlaceholder extends AssetPaintable {
  /// Creates the placeholder.
  const SoftPlaceholder();

  /// The corner radius as a fraction of the square's side.
  static const double cornerFraction = 0.15;

  static const Color _fallback = Color(0xFF73787B);
  static const double _alpha = 25 / 255;

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
    final side = rect.shortestSide;
    if (side <= 0) return;
    final base = context.tint ?? _fallback;
    _paint.color = base.withValues(alpha: base.a * _alpha * context.opacity);
    canvas.drawRRect(
      RRect.fromRectXY(
        Rect.fromCenter(center: rect.center, width: side, height: side),
        side * cornerFraction,
        side * cornerFraction,
      ),
      _paint,
    );
  }

  @override
  void dispose() {}
}
