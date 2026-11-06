import 'dart:math' as math;

import 'package:lottie_native/lottie_native.dart';
import 'package:meta/meta.dart';

/// The pixel size a frame of an animation is rendered at.
///
/// One definition for the decoder, which draws the first frame into a
/// temporary buffer, and the paintable, which asks the pool for slots of the
/// same size: if the two rounded differently, a still and its animation would
/// disagree about the picture's shape.
@immutable
final class LottieFrameSize {
  /// Creates a size of [width] x [height] pixels.
  const LottieFrameSize(this.width, this.height);

  /// The size of [info] with its longer side on [edge] pixels, the aspect
  /// ratio kept and each side rounded, but never below one pixel.
  factory LottieFrameSize.fitting(LottieInfo info, int edge) {
    final longer = math.max(info.width, info.height);
    int scaled(int side) => math.max(1, (side * edge / longer).round());
    return LottieFrameSize(scaled(info.width), scaled(info.height));
  }

  /// The width in pixels.
  final int width;

  /// The height in pixels.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is LottieFrameSize &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'LottieFrameSize($width x $height)';
}
