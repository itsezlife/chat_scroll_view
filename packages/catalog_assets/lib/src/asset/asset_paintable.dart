import 'dart:ui';

import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:meta/meta.dart';

/// What a surface passes to [AssetPaintable.paint] besides the rectangle.
@immutable
final class AssetPaintContext {
  /// Creates a context; the default paints in the asset's own colours, fully
  /// opaque, at the first frame.
  const AssetPaintContext({
    this.tint,
    this.opacity = 1,
    this.time = Duration.zero,
  }) : assert(opacity >= 0 && opacity <= 1, 'opacity must be within 0..1');

  /// Colour a template asset (`AssetDecodeMode.template`) is drawn in, and the
  /// colour of a placeholder. Null leaves an asset in its own colours.
  final Color? tint;

  /// Opacity of the whole paint, 0 to 1.
  final double opacity;

  /// Playback time of the shared clock. An animated paintable derives its frame
  /// from it, so every visible animation advances together; a still ignores it.
  final Duration time;
}

/// The thing a surface paints for an asset: the best stage the entry has
/// reached, behind one method.
///
/// The adapter that made it chooses the representation (a decoded image or
/// frame, a vector composition, a baked glyph sprite); a surface neither knows
/// nor cares. A paintable never schedules timers: its frame follows
/// [AssetPaintContext.time].
///
/// ## Sprite capability
///
/// A paintable may expose [sprite], an atlas page handle plus a source
/// rectangle. A surface that batches (the catalogue viewport draws every
/// sprite of one page in a single atlas draw) uses it instead of [paint]; a
/// paintable without a sprite paints itself, and [paint] always works whether
/// or not there is one.
///
/// ## Ownership
///
/// The cache owns a paintable it was handed through `AssetProgress.advance`
/// and calls [dispose] once when the entry drops it (superseded by a better
/// stage, evicted, or the scope going away). Eviction never touches an entry
/// with a live binding, so a binding's [paint] never reaches a disposed
/// paintable; a surface still must not keep a paintable or a sprite across
/// frames, because the stage behind a binding can improve.
abstract interface class AssetPaintable {
  /// The sprite to draw, or null when this paintable paints itself.
  ///
  /// Read it when painting and never keep it: the page behind it can be
  /// released. Allocation-free once a sprite exists.
  AtlasSprite? get sprite;

  /// Whether the picture changes with [AssetPaintContext.time]. A still is
  /// never registered with the playback clock, so it costs no ticks.
  bool get isAnimated;

  /// Paints into [rect] of [canvas].
  void paint(Canvas canvas, Rect rect, AssetPaintContext context);

  /// Releases what this paintable holds (decoded images, frame buffers).
  /// Called by the cache once.
  void dispose();
}
