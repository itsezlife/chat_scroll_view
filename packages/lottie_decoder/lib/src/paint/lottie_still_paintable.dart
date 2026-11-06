import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/painting.dart';

/// A decoded still, painted contain-fitted in its rectangle: the thumbnail
/// and first-frame stages of a Lottie asset, and what the animation shows
/// until its first frame is rendered.
///
/// It never animates, so a binding of it costs the clock nothing. A copy of
/// the idea in `image_decoder`, which this package does not depend on.
final class LottieStillPaintable implements AssetPaintable {
  /// Paints [image], which it owns from now on.
  LottieStillPaintable(this._image);

  final ui.Image _image;

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
    final source = Size(_image.width.toDouble(), _image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, source, rect.size);
    canvas.drawImageRect(
      _image,
      Alignment.center.inscribe(fitted.source, Offset.zero & source),
      Alignment.center.inscribe(fitted.destination, rect),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, context.opacity),
    );
  }

  @override
  void dispose() => _image.dispose();
}
