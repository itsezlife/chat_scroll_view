import 'package:lottie_native/src/lottie_binding.dart';
import 'package:lottie_native/src/lottie_features.dart';
import 'package:meta/meta.dart';

/// The outcome of [LottieBinding.load]: a closed set, so a caller handles
/// both and a bad file is a value, never an exception.
sealed class LottieLoadResult {
  const LottieLoadResult();
}

/// The file loaded; [handle] renders it until it is disposed.
final class LottieLoaded extends LottieLoadResult {
  /// Creates the result of a successful load.
  const LottieLoaded(this.handle, this.info);

  /// The loaded animation.
  final LottieHandle handle;

  /// What the file declares.
  final LottieInfo info;
}

/// The file did not load; nothing is held.
final class LottieRejected extends LottieLoadResult {
  /// Creates the result of a refused file.
  const LottieRejected(this.reason);

  /// Why it was refused.
  final LottieRejection reason;
}

/// Why a file was refused, mirroring the wrapper's load statuses.
enum LottieRejection {
  /// The encoded input, or its inflated form, is over the size cap.
  tooLarge,

  /// Not gzip, not JSON, or a parse error.
  malformed,

  /// The file is over a renderer limit (layers, nesting, ...).
  limitExceeded,

  /// Nothing to show: no pixels, no frames, or a non-finite frame rate.
  unsupported,
}

/// What a loaded file declares about itself.
@immutable
final class LottieInfo {
  /// Creates the description of a loaded file.
  const LottieInfo({
    required this.width,
    required this.height,
    required this.frameCount,
    required this.frameRate,
    required this.features,
  });

  /// The design width in pixels.
  final int width;

  /// The design height in pixels.
  final int height;

  /// The number of frames; valid frames are `[0, frameCount)`.
  final int frameCount;

  /// Frames per second.
  final double frameRate;

  /// What the file uses that the renderer does not draw.
  final LottieFeatures features;

  @override
  bool operator ==(Object other) =>
      other is LottieInfo &&
      other.width == width &&
      other.height == height &&
      other.frameCount == frameCount &&
      other.frameRate == frameRate &&
      other.features == features;

  @override
  int get hashCode =>
      Object.hash(width, height, frameCount, frameRate, features);

  @override
  String toString() =>
      'LottieInfo(${width}x$height, $frameCount frames at '
      '$frameRate fps, features ${features.bits})';
}
