import 'package:meta/meta.dart';

/// The frame a playback that does not loop rests on once its pass is over.
///
/// The reference clients differ: Android and Desktop go back to the first
/// frame, iOS is read to stay on the last (its player is not in the checked
/// source, so that is unverified). It is a per-attach value so a host can
/// follow either.
enum AssetRestFrame {
  /// The pass ends back on the first frame.
  first,

  /// The pass ends on the last frame.
  last,
}

/// How one surface behaves with an asset it attached: whether it plays, loops,
/// shows the first frame early and rounds its corners.
///
/// A profile is per attach. It never splits a cache entry (that is the
/// `AssetSpec`'s job), so one decoded asset serves a looping surface and a
/// still one at once.
@immutable
final class AssetProfile {
  /// Creates a profile; the default is a still surface.
  const AssetProfile({
    this.animate = false,
    this.loop = true,
    this.restFrame = AssetRestFrame.first,
    this.autoplayFirstFrame = true,
    this.cornerRadius = 0,
  }) : assert(cornerRadius >= 0, 'A corner radius cannot be negative.');

  /// Whether the surface wants the asset to play when it is visible and no
  /// pause layer is set.
  ///
  /// A surface that does not animate never moves the asset: its binding
  /// paints at the playback time of its first paint, however the shared clock
  /// moves for the others, and says it does not animate
  /// (`AssetPaintContext.animate`). Alone on its entry it shows one frame.
  /// Sharing the entry with a playing surface, it shows the frame that
  /// surface is at whenever it repaints, because a decoded frame sequence is
  /// one playback per entry; a surface that must hold the first frame asks
  /// for `AssetVariant.firstFrame`, which is an entry of its own.
  final bool animate;

  /// Whether a playing asset starts again after its last frame.
  ///
  /// When false the binding plays one pass, holds the [restFrame] and says it
  /// ended (`AssetBinding.playback`); `AssetBinding.replay` plays another.
  final bool loop;

  /// The frame a pass that does not [loop] rests on. Read only when [loop] is
  /// false; a loop never rests.
  final AssetRestFrame restFrame;

  /// Whether the surface shows the first frame as soon as it exists, before
  /// the full asset is ready or while it is not playing. When false the
  /// binding keeps its placeholder until the full stage.
  final bool autoplayFirstFrame;

  /// Logical corner radius the binding clips what it paints to; 0 for none.
  final double cornerRadius;

  @override
  bool operator ==(Object other) =>
      other is AssetProfile &&
      other.animate == animate &&
      other.loop == loop &&
      other.restFrame == restFrame &&
      other.autoplayFirstFrame == autoplayFirstFrame &&
      other.cornerRadius == cornerRadius;

  @override
  int get hashCode =>
      Object.hash(animate, loop, restFrame, autoplayFirstFrame, cornerRadius);

  @override
  String toString() =>
      'AssetProfile(animate: $animate, loop: $loop, '
      'restFrame: ${restFrame.name}, autoplayFirstFrame: $autoplayFirstFrame, cornerRadius: $cornerRadius)';
}
