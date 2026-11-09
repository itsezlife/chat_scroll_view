import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_fit.dart';
import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/asset/asset_texture.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:meta/meta.dart';

/// What a surface passes to [AssetPaintable.paint] besides the rectangle.
@immutable
final class AssetPaintContext {
  /// Creates a context; the default paints in the asset's own colours, fully
  /// opaque, at the first frame, for a surface that animates.
  const AssetPaintContext({
    this.tint,
    this.opacity = 1,
    this.time = Duration.zero,
    this.animate = true,
    this.loop = true,
    this.restFrame = AssetRestFrame.first,
    this.fit = AssetFit.contain,
    this.halfFrameRate = false,
  }) : assert(opacity >= 0 && opacity <= 1, 'opacity must be within 0..1');

  /// Colour a template asset (`AssetDecodeMode.template`) is drawn in, and the
  /// colour of a placeholder. Null leaves an asset in its own colours.
  final Color? tint;

  /// Opacity of the whole paint, 0 to 1.
  final double opacity;

  /// Playback time of the shared clock. An animated paintable derives its frame
  /// from it, so every visible animation advances together; a still ignores it.
  final Duration time;

  /// Whether the surface painting animates (`AssetProfile.animate`).
  ///
  /// A paintable whose frame follows [time] alone needs nothing more: a
  /// surface that does not animate paints at one time. A paintable that keeps
  /// its playback state, and is shared by every surface of its entry, does
  /// not step for a paint that does not animate and shows the frame it is at.
  final bool animate;

  /// Whether the surface wants another pass after the last frame
  /// (`AssetProfile.loop`). A paintable that plays a frame sequence holds its
  /// rest frame at the end of a pass instead of wrapping when this is false.
  final bool loop;

  /// The frame a pass rests on when [loop] is false (`AssetProfile.restFrame`).
  final AssetRestFrame restFrame;

  /// How a picture fills the rectangle (`AssetProfile.fit`). A paintable that
  /// draws a picture places it with [AssetFit.place]; one that has no
  /// proportions of its own (a placeholder) ignores it.
  final AssetFit fit;

  /// Whether the surface plays at half rate (`AssetProfile.halfFrameRate`).
  /// A paintable that plays a frame sequence reads it through [frameStepFor].
  final bool halfFrameRate;

  /// How many source frames a playing paintable moves by between the frames
  /// it shows, for a source authored at [sourceFrameRate] fps: 2 at half rate
  /// above `AssetProfile.halfFrameRateAbove`, else 1. An unknown rate (0)
  /// plays every frame.
  int frameStepFor(double sourceFrameRate) =>
      halfFrameRate && sourceFrameRate > AssetProfile.halfFrameRateAbove
      ? 2
      : 1;
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
/// or not there is one. A paintable whose sprite exists only once it has
/// been advanced (an animation) is advanced through [advancePlayback] before
/// [sprite] is read.
///
/// ## Texture capability
///
/// A paintable that plays may expose [texture], a platform texture its
/// render worker writes each frame into (ADR 043). A surface that composites
/// (a render object that pushes layers) adds a texture layer for it instead
/// of drawing the sprite or calling [paint]; a surface that only has a
/// canvas ignores it and calls [paint], which keeps drawing through the
/// pages. A paintable exposes it only after [advancePlayback] and only once a
/// first frame was posted to it; until then it exposes its sprite or paints
/// its still. No surface is required to support textures.
///
/// ## Ownership
///
/// The cache owns a paintable it was handed through `AssetProgress.advance`
/// and calls [dispose] once when the entry drops it (superseded by a better
/// stage, evicted, or the scope going away). Eviction never touches an entry
/// with a live binding, so a binding's [paint] never reaches a disposed
/// paintable; a surface still must not keep a paintable or a sprite across
/// frames, because the stage behind a binding can improve.
abstract class AssetPaintable {
  /// For subclasses; a paintable extends this to inherit the no-op
  /// [advancePlayback].
  const AssetPaintable();

  /// The sprite to draw, or null when this paintable paints itself.
  ///
  /// Read it when painting and never keep it: the page behind it can be
  /// released. Allocation-free once a sprite exists.
  AtlasSprite? get sprite;

  /// Whether the picture changes with [AssetPaintContext.time]. A still is
  /// never registered with the playback clock, so it costs no ticks.
  bool get isAnimated;

  /// Whether a pass that was painted with `AssetPaintContext.loop` false has
  /// played its last frame and the paintable now holds its rest frame.
  ///
  /// A holding paintable changes nothing on later paints that do not loop.
  /// Always false for a paintable that does not animate.
  bool get isHolding;

  /// Plays another pass from the first frame if the paintable is holding, and
  /// says whether it did. Does nothing, returning false, while a pass is
  /// running: a pass in progress is never rewound.
  bool restart();

  /// Lets a paintable that plays advance before a surface reads [sprite], for
  /// a surface that draws the sprite itself and so never calls [paint].
  ///
  /// A paintable that keeps playback state (a lease on a frame, a played
  /// time) does there what [paint] does before it draws: it works out the
  /// frame [context] names and asks for it. The surface calls it once per
  /// animated paintable per pass, then reads [sprite]; a surface that calls
  /// [paint] instead needs no call, because [paint] does the same. Calling both
  /// in one pass is harmless: the same [AssetPaintContext.time] adds no time
  /// played. Does nothing by default, which is right for a still and for a
  /// baked glyph.
  void advancePlayback(AssetPaintContext context) {}

  /// The platform texture that holds the current frame, or null when this
  /// paintable draws through [sprite] or [paint].
  ///
  /// Read it after [advancePlayback], when compositing, and never keep it: a
  /// paintable can give its texture back between two frames (it stopped
  /// playing, or its locks failed) and draw through its pages again. Null by
  /// default, which is right for every paintable that does not play.
  AssetTexture? get texture => null;

  /// The first frame of this animation as a still, or null.
  ///
  /// Owned by this paintable and alive until its [dispose]; whoever paints it
  /// never disposes it. A binding that borrows a sibling entry's stage paints
  /// it instead of the playing paintable: the sibling may be in the middle of
  /// a loop, and the borrower's own entry starts from frame 0, so the live
  /// frame would show a jump back when the entry's own frame arrives. Null by
  /// default, which is right for a still and for an animation that keeps no
  /// still of its first frame (it is then not lent at all).
  AssetPaintable? get firstFrame => null;

  /// Keeps the frame on show while [keep] is true, though no surface paints
  /// or advances this paintable: a surface that holds its playback
  /// (`AssetBinding.held`) still shows that frame.
  ///
  /// A paintable that leases where its frame lives (a page slot, a platform
  /// texture) gives an unpainted lease back after an idle period, because a
  /// paint is its only sign of being on screen. A held surface paints nothing
  /// new, yet the frame it last composited is on screen: given back, a texture
  /// would be written by its next holder under that surface's layer. While
  /// kept, the lease stays. The binding sets it from the holds of every
  /// binding of the entry. Does nothing by default, which is right for a
  /// paintable that holds its own pixels.
  void keepFrame({required bool keep}) {}

  /// Says that no surface played this paintable for a while (held, hidden,
  /// off screen) and one plays it again now.
  ///
  /// The shared clock keeps running for other surfaces meanwhile, so a
  /// paintable that adds up the time between paints would add the whole stop
  /// at its next paint and jump ahead by it: a sticker panel shut for 300 ms
  /// came back 20 frames on. One that keeps its playback takes the next paint
  /// as the start of its timing instead, and goes on from the frame it is at
  /// ("freeze and continue"). Does nothing by default, which is right for a
  /// still or a paintable whose frame follows the time alone.
  void playbackResumed() {}

  /// Says that no surface shows this paintable any more: every binding of its
  /// entry is hidden or detached.
  ///
  /// A paintable that leases where its frame lives (a page slot, a platform
  /// texture) gives the lease back now, unless it keeps its frame
  /// ([keepFrame]): the pool those come from is shared and capped, and a
  /// lease left to the idle sweep held its place for one to two seconds,
  /// so the cells a fling brought in found the pool full of cells that had
  /// flown past and showed their stills (the reference client gives a
  /// cell's drawable back the moment the cell detaches). A surface may
  /// still paint a binding it hides for the rest of the frame (a cell at
  /// the edge of a scrolling window), so the lease goes once
  /// the frame is over, and only if nothing painted it meanwhile. Painted
  /// again later, the paintable takes a new lease. Does nothing by default,
  /// which is right for a paintable that holds its own pixels.
  void leftScreen() {}

  /// Paints into [rect] of [canvas].
  void paint(Canvas canvas, Rect rect, AssetPaintContext context);

  /// Releases what this paintable holds (decoded images, frame buffers).
  /// Called by the cache once.
  void dispose();
}
