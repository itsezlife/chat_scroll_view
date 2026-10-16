import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';

/// The default placeholder: a soft circle filling the shorter side of the
/// rectangle, in the context's tint (grey when there is none).
///
/// Always synchronous, shared by every binding of a scope, never disposed. It
/// has no sprite and does not animate.
final class CirclePlaceholder implements AssetPaintable {
  /// Creates the placeholder.
  const CirclePlaceholder();

  static const Color _fallback = Color(0xFF9E9E9E);
  static const double _alpha = 0.35;

  // Painting is single-threaded and the paint is set fully on every call, so
  // one shared object saves an allocation per placeholder per frame.
  static final Paint _paint = Paint();

  @override
  AtlasSprite? get sprite => null;

  @override
  bool get isAnimated => false;

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    final base = context.tint ?? _fallback;
    _paint.color = base.withValues(alpha: _alpha * context.opacity);
    canvas.drawCircle(
      rect.center,
      (rect.shortestSide / 2).clamp(0, double.infinity),
      _paint,
    );
  }

  @override
  void dispose() {}
}
