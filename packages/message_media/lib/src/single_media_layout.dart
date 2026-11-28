import 'dart:ui';

import 'package:message_media/src/media_layout_metrics.dart';

/// The box of a **single** photo, video or animation media item: the
/// default media layout's single box size.
///
/// Owns: aspect to pixel [Size] under the single box clamps. Does not own:
/// mosaics ([GroupedMessages.calculate]), loading or paint. Photo, video and
/// animation share the box and differ only in policy values; a file or
/// custom kind is a file row, not a box.
abstract final class SingleMediaLayout {
  /// The box at [maxWidth] of a picture of [aspectRatio].
  ///
  /// ## Clamp sequence
  ///
  /// 1. Max box = `maxWidth × (maxWidth + singlePhotoHeightExtra)`, each
  ///    side soft-capped by [MediaLayoutMetrics.photoSizeCap]; [maxHeight],
  ///    when given, is the max box height as is (a policy that computes it
  ///    from a width before its deductions passes it).
  /// 2. Scale the nominal `(aspectRatio, 1)` into that width (truncated to
  ///    whole pixels).
  /// 3. If the height exceeds the max box, clamp it and rescale the width.
  /// 4. If the height is below [minHeight], raise it to that floor; shrink
  ///    the width only when the aspect-scaled width would be narrower than
  ///    [maxWidth].
  ///
  /// A side that truncates to zero takes [zeroSide] (default
  /// [MediaLayoutMetrics.noDimensionsSide], 150).
  ///
  /// [aspectRatio] ≤ 0 or [maxWidth] ≤ 0 gives [Size.zero].
  static Size compute({
    required double aspectRatio,
    required double maxWidth,
    double? maxHeight,
    double minHeight = MediaLayoutMetrics.minMediaHeight,
    double zeroSide = MediaLayoutMetrics.noDimensionsSide,
  }) {
    if (maxWidth <= 0 || aspectRatio <= 0) return Size.zero;

    var photoWidth = maxWidth;
    var photoHeight =
        maxHeight ?? photoWidth + MediaLayoutMetrics.singlePhotoHeightExtra;

    if (photoWidth > MediaLayoutMetrics.photoSizeCap) {
      photoWidth = MediaLayoutMetrics.photoSizeCap;
    }
    if (maxHeight == null && photoHeight > MediaLayoutMetrics.photoSizeCap) {
      photoHeight = MediaLayoutMetrics.photoSizeCap;
    }

    // Nominal picture dimensions that keep the aspect (w = ar, h = 1).
    final imageW = aspectRatio;
    const imageH = 1.0;

    final scale = imageW / photoWidth;
    var w = (imageW / scale).truncateToDouble();
    var h = (imageH / scale).truncateToDouble();
    if (w == 0) w = zeroSide;
    if (h == 0) h = zeroSide;

    if (h > photoHeight) {
      final scale2 = h / photoHeight;
      h = photoHeight;
      w = (w / scale2).truncateToDouble();
    } else if (h < minHeight) {
      h = minHeight;
      final hScale = imageH / h;
      if (imageW / hScale < photoWidth) {
        w = (imageW / hScale).truncateToDouble();
      }
    }

    return Size(w, h);
  }
}
