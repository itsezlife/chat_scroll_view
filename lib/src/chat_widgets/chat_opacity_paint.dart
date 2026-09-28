import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// Opacity at or below which [paintChildWithOpacity] paints nothing.
@internal
const kChatOpacityPaintSkip = 0.001;

/// Paints [child] at [offset] and [opacity]: directly at `>= 0.999`, not at
/// all at `<=` [kChatOpacityPaintSkip], and through [layer]'s retained
/// [OpacityLayer] in between. The snaps keep a fade from creating and
/// disposing a layer every frame at its ends.
@internal
void paintChildWithOpacity(
  PaintingContext context,
  RenderBox child,
  Offset offset,
  double opacity,
  LayerHandle<OpacityLayer> layer,
) {
  if (opacity >= 0.999) {
    layer.layer = null;
    context.paintChild(child, offset);
  } else if (opacity <= kChatOpacityPaintSkip) {
    layer.layer = null;
  } else {
    layer.layer = context.pushOpacity(
      offset,
      (opacity * 255).round().clamp(0, 255),
      (innerContext, innerOffset) =>
          innerContext.paintChild(child, innerOffset),
      oldLayer: layer.layer,
    );
  }
}
