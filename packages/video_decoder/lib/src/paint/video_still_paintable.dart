import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/painting.dart';

/// A decoded still, painted contain-fitted in its rectangle: the thumbnail
/// and first-frame stages of a video asset, and what the clip shows until its
/// first frame is drawn from the pool.
///
/// It never animates, so a binding of it costs the clock nothing. The same
/// idea as the still of `image_decoder` and `lottie_decoder`, which this
/// package depends on neither of.
final class VideoStillPaintable extends AssetPaintable {
  /// Paints [image], which it owns from now on.
  VideoStillPaintable(this._image);

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
