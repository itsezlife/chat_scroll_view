import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/rendering.dart';

/// One leaf's texture as a paint pass placed it.
typedef _TextureCell = ({int id, Rect rect, Rect? clip, double opacity});

/// The platform textures of one paint pass, composited as layers after the
/// pass's picture (ADR 043, "Compositing").
///
/// A leaf whose asset exposes `AssetPaintable.texture` is not drawn on the
/// canvas: [add] places its texture as the leaf's fit says and queues it, and
/// [composite] adds one texture layer per queued leaf, in the order they were
/// added, inside the viewport clip. What the leaf painted on the canvas (its
/// hover, focus and press washes, a placeholder fading out under content that
/// fades in) is in the picture before the layers, so it stays under the
/// texture, as it stays under a batched sprite. Nothing this viewport paints
/// goes over a cell's content; a mark over it would be a picture after the
/// layers.
///
/// Opacity below one wraps the texture layer in an opacity layer; a cover fit
/// crops through a clip layer of the box, since a texture layer always shows
/// its whole texture (`AssetFit.placeTexture`).
final class CatalogTextureLayers {
  final List<_TextureCell> _cells = [];

  /// Whether the pass queued any texture.
  bool get isEmpty => _cells.isEmpty;

  /// Queues [texture] drawn into [box] as [fit] says, scaled by [pressScale]
  /// about [anchor] (the cell centre), at [opacity].
  void add(
    AssetTexture texture, {
    required Rect box,
    required AssetFit fit,
    required Offset anchor,
    double pressScale = 1,
    double opacity = 1,
  }) {
    final placed = fit.placeTexture(texture, _scaled(box, anchor, pressScale));
    _cells.add((
      id: texture.id,
      rect: placed.rect,
      clip: placed.clip,
      opacity: opacity,
    ));
  }

  /// Adds the queued textures as layers to [context] inside [clipRect] (in
  /// the coordinates of [offset]) and empties the queue.
  void composite(
    PaintingContext context,
    Offset offset,
    Rect clipRect, {
    required bool needsCompositing,
  }) {
    if (_cells.isEmpty) return;
    final cells = List<_TextureCell>.of(_cells);
    _cells.clear();
    context.pushClipRect(needsCompositing, offset, clipRect, (inner, _) {
      for (final cell in cells) {
        _addCell(inner, cell);
      }
    });
  }

  /// Forgets the queued textures without compositing them.
  void clear() => _cells.clear();

  static void _addCell(PaintingContext context, _TextureCell cell) {
    void texture(PaintingContext context, Offset _) =>
        context.addLayer(TextureLayer(rect: cell.rect, textureId: cell.id));

    void faded(PaintingContext context, Offset offset) {
      if (cell.opacity >= 1) {
        texture(context, offset);
        return;
      }
      context.pushOpacity(
        Offset.zero,
        (cell.opacity.clamp(0.0, 1.0) * 255).round(),
        texture,
      );
    }

    final clip = cell.clip;
    if (clip == null) {
      faded(context, Offset.zero);
    } else {
      context.pushClipRect(true, Offset.zero, clip, faded);
    }
  }

  static Rect _scaled(Rect box, Offset anchor, double scale) => scale == 1
      ? box
      : Rect.fromLTRB(
          anchor.dx + (box.left - anchor.dx) * scale,
          anchor.dy + (box.top - anchor.dy) * scale,
          anchor.dx + (box.right - anchor.dx) * scale,
          anchor.dy + (box.bottom - anchor.dy) * scale,
        );
}
