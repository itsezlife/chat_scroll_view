import 'package:flutter/rendering.dart';
import 'package:mpx_core/mpx_core.dart';

/// How an embed shows a binding whose frames go to a platform texture: the
/// same layering `ContentView` does inside `mpx_core`, which keeps its helper
/// private, so the embed carries its own.
///
/// [composite] advances an animated paintable (which tells it that a surface
/// that composites shows it) and, when it then exposes a texture, adds a
/// texture layer where the profile's fit places the frame. A texture layer
/// cannot crop or fade, so a cover fit or a corner radius gets a clip layer
/// and an opacity below one an opacity layer. When nothing composited the
/// embed paints the binding on the canvas.
///
/// Internal to the package.
abstract final class TextureComposite {
  /// Adds [binding]'s texture to [context] as a layer for [box] at
  /// [opacity], and says whether it did.
  static bool composite(
    PaintingContext context,
    AssetBinding binding,
    Rect box, {
    double opacity = 1,
  }) {
    final paintable = binding.paintable;
    if (!paintable.isAnimated) return false;
    // The texture is taken or given back by the advance, so it is read after
    // it.
    binding.advancePlayback();
    final texture = paintable.texture;
    if (texture == null) return false;
    final profile = binding.profile;
    final placed = profile.fit.placeTexture(texture, box);
    void layer(PaintingContext context, Offset _) => context.addLayer(
      TextureLayer(rect: placed.rect, textureId: texture.id),
    );

    void faded(PaintingContext context, Offset offset) {
      if (opacity >= 1) return layer(context, offset);
      context.pushOpacity(Offset.zero, (opacity * 255).round(), layer);
    }

    void clipped(PaintingContext context, Offset offset) {
      final clip = placed.clip;
      if (clip == null) return faded(context, offset);
      context.pushClipRect(true, Offset.zero, clip, faded);
    }

    final radius = profile.cornerRadius;
    if (radius > 0) {
      context.pushClipRRect(
        true,
        Offset.zero,
        box,
        RRect.fromRectXY(box, radius, radius),
        clipped,
      );
    } else {
      clipped(context, Offset.zero);
    }
    // Content shown opaque lets go of its thumbnail, as a paint would.
    if (opacity >= 1) binding.releaseStandIn();
    return true;
  }
}
