import 'package:lottie_decoder/src/cache/frame_cache_key.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:meta/meta.dart';

/// What a frame job renders: a loaded animation, and where its frames are
/// cached.
///
/// The `FrameJob.source` of `LottieFrameRenderer`, in place of the bare
/// [LottieHandle]: a handle is the engine's name for the animation and says
/// nothing of its content, so the renderer could not tell which cached frames
/// are its own. [frameCount] is here for the same reason: the cache stores
/// frames of an animation of known length, and the renderer holds no
/// `LottieInfo`.
@immutable
final class LottieSource {
  /// Creates the source of [handle], an animation of [frameCount] frames.
  ///
  /// A null [cacheKey] is an animation that is not cached (above the cap, or
  /// a host without a cache): the renderer then always renders it.
  const LottieSource(this.handle, {required this.frameCount, this.cacheKey});

  /// The engine's handle of the loaded animation.
  final LottieHandle handle;

  /// The animation's length in frames.
  final int frameCount;

  /// Where its rendered frames are cached, or null for none.
  final FrameCacheKey? cacheKey;

  @override
  bool operator ==(Object other) =>
      other is LottieSource &&
      other.handle == handle &&
      other.frameCount == frameCount &&
      other.cacheKey == cacheKey;

  @override
  int get hashCode => Object.hash(handle, frameCount, cacheKey);

  @override
  String toString() => 'LottieSource($handle, $frameCount frames, $cacheKey)';
}
