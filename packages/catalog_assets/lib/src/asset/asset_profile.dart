import 'package:meta/meta.dart';

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
  final bool loop;

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
      other.autoplayFirstFrame == autoplayFirstFrame &&
      other.cornerRadius == cornerRadius;

  @override
  int get hashCode =>
      Object.hash(animate, loop, autoplayFirstFrame, cornerRadius);

  @override
  String toString() =>
      'AssetProfile(animate: $animate, loop: $loop, '
      'autoplayFirstFrame: $autoplayFirstFrame, cornerRadius: $cornerRadius)';
}
