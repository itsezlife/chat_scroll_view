import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:flutter/rendering.dart';

/// How a surface that pushes layers shows a binding whose frames go to a
/// platform texture (ADR 043, "Paint capability"): the one place `ContentView`
/// and `ContentEmbed` composite.
///
/// [composite] advances an animated paintable (which is what tells it that a
/// surface that composites shows it) and, when it then exposes a texture,
/// adds a texture layer where the profile's fit places the frame. A texture
/// layer cannot crop or fade, so a cover fit or a corner radius gets a clip
/// layer and an opacity below one an opacity layer. When nothing composited
/// the surface paints the binding on the canvas as before; that paint, at the
/// same time, adds nothing played.
///
/// Layers go after what the context recorded so far: a surface reads
/// `context.canvas` again after a call, since adding a layer starts a new
/// picture.
abstract final class AssetTextureLayer {
  /// Adds [binding]'s texture to [context] as a layer for [box] (in the
  /// context's coordinates) at [opacity], and says whether it did.
  ///
  /// False for a paintable that does not animate or exposes no texture after
  /// the advance; [context] is then untouched.
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
    // Nothing fades in over the thumbnail here: content shown opaque lets go
    // of it, as a paint would.
    if (opacity >= 1) binding.releaseStandIn();
    return true;
  }
}
