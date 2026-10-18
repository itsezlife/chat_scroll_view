import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:meta/meta.dart';

/// A reason the host can give for pausing every animation at once. Layers are
/// independent: playback runs only while none of the policy's layers is set.
///
/// Every layer is a plain on/off signal. The ones a `PlaybackActivity` drives
/// ([appInactive], [surfaceHidden], [lowPower], [reducedMotion],
/// [overlayShown]) are set by it from its inputs; [routeMoving] and
/// [fastScroll] belong to the host (a route transition, the scroll physics).
enum PlaybackPauseLayer {
  /// A route or sheet is moving; the frames are better spent on the motion.
  routeMoving,

  /// A list is scrolling fast.
  fastScroll,

  /// The device is saving power.
  lowPower,

  /// The surface the animations are on is not visible (hidden, minimised,
  /// backgrounded).
  surfaceHidden,

  /// The app is visible but is not the one the user is working in: its window
  /// lost focus (on desktop another app took it; on a phone a call or a
  /// system sheet is on top). The reference desktop client freezes stickers,
  /// emoji and spoiler dust the same moment its window deactivates.
  appInactive,

  /// The user asked the system for less motion. Not in the standard pausing
  /// set ([PlaybackPolicy.standardPausingLayers]): the reference desktop
  /// client does not read the setting at all, and animated emoji are content
  /// rather than interface motion. A host that wants it to stop playback adds
  /// it to [PlaybackPolicy.pausingLayers].
  reducedMotion,

  /// Something sits over the chat that is not part of it: a dialog, a sheet, a
  /// full-screen route. The reference desktop client pauses the chat under
  /// any box layer. Raised by holds (`PlaybackActivity.holdOverlay`) so that
  /// nested overlays do not clear each other.
  overlayShown,
}

/// Which layers pause playback and how fast a playing asset advances.
///
/// ## Defaults and where they come from
///
/// Every layer pauses except [PlaybackPauseLayer.reducedMotion] (see
/// [standardPausingLayers]). A small asset runs at 30 fps and a large one at 60:
/// the reference client caps emoji up to 90 dp at about 30 fps on mobile and
/// repaints no faster than every 33 ms on desktop, because a small animation
/// is not visibly smoother at 60 and costs a repaint of its surface each
/// frame.
/// Specs are in pixels, so the threshold [smallEdgePixels] (270) is 90 dp at
/// the common density of 3. The cap derives from the spec, not from a surface
/// name, so the same asset at two sizes is capped separately. 60 fps is a
/// ceiling, not a target: on a display at 120 Hz an animation still advances
/// at most every 1/60 s.
@immutable
final class PlaybackPolicy {
  /// Creates a policy.
  const PlaybackPolicy({
    this.pausingLayers = standardPausingLayers,
    this.smallEdgePixels = 270,
    this.smallFps = 30,
    this.largeFps = 60,
    this.cadenceSlack = const Duration(milliseconds: 2),
  }) : assert(smallFps > 0 && largeFps > 0, 'fps caps are positive');

  /// The layers that pause playback unless a host says otherwise: all of
  /// them but [PlaybackPauseLayer.reducedMotion].
  ///
  /// Spelled out rather than `{...PlaybackPauseLayer.values}` so that a layer
  /// added later pauses only after someone decided it should.
  static const Set<PlaybackPauseLayer> standardPausingLayers = {
    PlaybackPauseLayer.routeMoving,
    PlaybackPauseLayer.fastScroll,
    PlaybackPauseLayer.lowPower,
    PlaybackPauseLayer.surfaceHidden,
    PlaybackPauseLayer.appInactive,
    PlaybackPauseLayer.overlayShown,
  };

  /// The layers that pause playback when set.
  final Set<PlaybackPauseLayer> pausingLayers;

  /// Largest edge, in pixels, of an asset that counts as small.
  final int smallEdgePixels;

  /// Frames per second cap of a small asset.
  final int smallFps;

  /// Frames per second cap of every other asset.
  final int largeFps;

  /// How early before its interval a frame may still advance a binding, so a
  /// 30 fps cap on a 120 Hz display runs every fourth frame (33.3 ms) rather
  /// than every fifth.
  final Duration cadenceSlack;

  /// The frames per second cap of an asset decoded as [spec].
  int fpsCapFor(AssetSpec spec) {
    final edge = spec.pixelWidth > spec.pixelHeight
        ? spec.pixelWidth
        : spec.pixelHeight;
    return edge <= smallEdgePixels ? smallFps : largeFps;
  }

  /// The shortest time between two advances of an asset decoded as [spec].
  Duration frameIntervalFor(AssetSpec spec) =>
      Duration(microseconds: Duration.microsecondsPerSecond ~/ fpsCapFor(spec));
}
