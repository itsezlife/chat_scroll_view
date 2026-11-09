import 'package:catalog_assets/src/asset/asset_fit.dart';
import 'package:meta/meta.dart';

/// The frame a playback that does not loop rests on once its pass is over.
///
/// The reference clients differ: two go back to the first frame, one is read
/// to stay on the last (unverified). It is a per-attach value so a host can
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
    this.fit = AssetFit.contain,
    this.halfFrameRate = false,
    this.foreground = false,
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

  /// How the content fills the rectangle it is painted in: whole ([AssetFit.contain],
  /// the default) or filling it and cut at the edge ([AssetFit.cover]). Applies
  /// to the content and to its thumbnail alike, so the two never differ in
  /// crop when one replaces the other.
  final AssetFit fit;

  /// Whether a playing asset shows only every second frame of a source
  /// authored above [halfFrameRateAbove] fps: 30 fps for a 60 fps animation.
  ///
  /// For a surface that draws assets small (a cell of a content grid), where
  /// 60 fps is not visibly smoother and each frame costs a render and a post
  /// per asset: a grid of 25 playing stickers posts 1500 frames a second at
  /// full rate. The reference client does the same for stickers drawn at up
  /// to 90 dp (`limitFps`, every second frame). Unlike the fps cap of the
  /// playback policy, which only spaces a binding's repaints, this changes
  /// the frames asked for, so a surface that repaints every frame for other
  /// reasons still renders half of them. A source at 30 fps or below plays
  /// every frame. An entry shared by a surface at half rate and one at full
  /// rate shows the frames of whichever painted last.
  final bool halfFrameRate;

  /// Whether the surface stands over the others, as a content preview does
  /// over the grid it was opened from.
  ///
  /// Two things follow, both the reference mobile client's preview:
  ///
  /// - Each attach plays its own pass from the first frame
  ///   (`AssetPaintable.rewind` when the binding starts to play;
  ///   `setCurrentFrame(0)` as `ContentPreviewViewer` opens). Without it a
  ///   preview opened again on content it showed before would go on from the
  ///   frame its entry stopped at, which the entry's cache keeps: the still
  ///   first, then a jump to that frame once the frame lands.
  /// - A background hold of the scope (`AssetCacheScope.holdBackground`)
  ///   does not hold it: the others keep their frames while it plays, as
  ///   every image below the preview's layer stops its animation
  ///   (`stopAllHeavyOperations`).
  ///
  /// The decoded asset is one playback for every binding of its entry, so a
  /// foreground surface that shares its entry with another restarts that one
  /// too; a preview is drawn at a size of its own, and so has its own entry.
  final bool foreground;

  /// The source frame rate above which [halfFrameRate] skips every second
  /// frame.
  static const double halfFrameRateAbove = 30;

  @override
  bool operator ==(Object other) =>
      other is AssetProfile &&
      other.animate == animate &&
      other.loop == loop &&
      other.restFrame == restFrame &&
      other.autoplayFirstFrame == autoplayFirstFrame &&
      other.cornerRadius == cornerRadius &&
      other.fit == fit &&
      other.halfFrameRate == halfFrameRate &&
      other.foreground == foreground;

  @override
  int get hashCode => Object.hash(
    animate,
    loop,
    restFrame,
    autoplayFirstFrame,
    cornerRadius,
    fit,
    halfFrameRate,
    foreground,
  );

  @override
  String toString() =>
      'AssetProfile(animate: $animate, loop: $loop, '
      'restFrame: ${restFrame.name}, autoplayFirstFrame: $autoplayFirstFrame, cornerRadius: $cornerRadius, fit: ${fit.name}, '
      'halfFrameRate: $halfFrameRate, foreground: $foreground)';
}
