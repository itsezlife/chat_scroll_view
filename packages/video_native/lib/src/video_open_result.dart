import 'package:meta/meta.dart';
import 'package:video_native/src/video_handle.dart';

/// The outcome of `VideoBinding.open`: a closed set, so a caller handles both
/// and a bad file is a value, never an exception.
sealed class VideoOpenResult {
  const VideoOpenResult();
}

/// The file opened; [handle] yields frames until it is disposed.
final class VideoOpened extends VideoOpenResult {
  /// Creates the result of a successful open.
  const VideoOpened(this.handle, this.info);

  /// The open video.
  final VideoHandle handle;

  /// What the file declares.
  final VideoInfo info;
}

/// The file did not open; nothing is held.
final class VideoRejected extends VideoOpenResult {
  /// Creates the result of a refused file.
  const VideoRejected(this.reason);

  /// Why it was refused.
  final VideoRejection reason;
}

/// Why a file was refused, mirroring the wrapper's open statuses.
enum VideoRejection {
  /// The input is over the byte cap.
  tooLarge,

  /// Not a container the build reads, or damaged beyond opening.
  malformed,

  /// The source or a decode budget is over a cap (dimensions, packets).
  limitExceeded,

  /// A readable container with nothing this build decodes: no video stream,
  /// or a codec that is not built in.
  unsupported,

  /// The requested target size is zero or over the cap.
  badSize,

  /// The wrapper failed on its own (allocation, an FFmpeg internal error).
  /// Not a verdict on the file: a host must not cache it as one.
  internal,
}

/// What an open video declares about itself.
@immutable
final class VideoInfo {
  /// Creates the description of an open video.
  const VideoInfo({
    required this.width,
    required this.height,
    required this.duration,
    required this.frameRate,
    required this.hasAlpha,
  });

  /// The source width in pixels (frames are delivered at the target size).
  final int width;

  /// The source height in pixels.
  final int height;

  /// The container's duration, or null when it declares none.
  final Duration? duration;

  /// Frames per second the stream declares, 0 when unknown.
  final double frameRate;

  /// Whether the stream declares an alpha channel (WebM `alpha_mode`, or a
  /// pixel format with alpha). A GIF is reported without it even though its
  /// frames may hold transparent pixels; every frame is premultiplied
  /// regardless.
  final bool hasAlpha;

  @override
  bool operator ==(Object other) =>
      other is VideoInfo &&
      other.width == width &&
      other.height == height &&
      other.duration == duration &&
      other.frameRate == frameRate &&
      other.hasAlpha == hasAlpha;

  @override
  int get hashCode => Object.hash(width, height, duration, frameRate, hasAlpha);

  @override
  String toString() =>
      'VideoInfo(${width}x$height, $duration, $frameRate fps, '
      'alpha $hasAlpha)';
}
