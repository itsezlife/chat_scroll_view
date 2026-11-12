import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:video_native/video_native.dart';

/// The pixel size frames of a clip are decoded at.
///
/// One definition for the decoder, which decodes the still at it, and the
/// paintable, which asks the pool for slots of it: if the two rounded
/// differently, a still and its animation would disagree about the picture's
/// shape.
@immutable
final class VideoFrameSize {
  /// Creates a size of [width] x [height] pixels.
  const VideoFrameSize(this.width, this.height);

  /// The size of [info] with its longer side on [edge] pixels, the aspect
  /// ratio kept and each side rounded, but never below one pixel.
  factory VideoFrameSize.fitting(VideoInfo info, int edge) {
    final longer = math.max(info.width, info.height);
    int scaled(int side) => math.max(1, (side * edge / longer).round());
    return VideoFrameSize(scaled(info.width), scaled(info.height));
  }

  /// The cell edges of the video pool, the display sizes clips are decoded at.
  static const List<int> defaultClasses = [64, 128, 256, 384, 512];

  /// The smallest of [classes] that holds [requested] pixels, or the largest
  /// when none does: a clip is never decoded above the biggest cell.
  static int edgeFor(int requested, {List<int> classes = defaultClasses}) {
    for (final edge in classes) {
      if (requested <= edge) return edge;
    }
    return classes.last;
  }

  /// The width in pixels.
  final int width;

  /// The height in pixels.
  final int height;

  /// The bytes of one BGRA frame of this size.
  int get frameBytes => width * height * 4;

  @override
  bool operator ==(Object other) =>
      other is VideoFrameSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'VideoFrameSize($width x $height)';
}
