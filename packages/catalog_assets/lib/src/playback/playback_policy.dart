import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:meta/meta.dart';

/// A reason the host can give for pausing every animation at once. Layers are
/// independent: playback runs only while none of the policy's layers is set.
enum PlaybackPauseLayer {
  /// A route or sheet is moving; the frames are better spent on the motion.
  routeMoving,

  /// A list is scrolling fast.
  fastScroll,

  /// The device is saving power.
  lowPower,

  /// The surface the animations are on is not visible (hidden, covered,
  /// backgrounded).
  surfaceHidden,
}

/// Which layers pause playback and how fast a playing asset advances.
///
/// ## Defaults and where they come from
///
/// Every layer pauses. A small asset runs at 30 fps and a large one at 60:
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
    this.pausingLayers = const {...PlaybackPauseLayer.values},
    this.smallEdgePixels = 270,
    this.smallFps = 30,
    this.largeFps = 60,
    this.cadenceSlack = const Duration(milliseconds: 2),
  }) : assert(smallFps > 0 && largeFps > 0, 'fps caps are positive');

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
