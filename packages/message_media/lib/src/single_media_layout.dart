import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:message_media/src/media_layout_metrics.dart';

/// The box of a **single** photo, video or animation media item at
/// [maxWidth]: the default media layout's single box size.
///
/// Owns: aspect to pixel [Size] under the single box clamps. Does not own:
/// mosaics ([GroupedMessages.calculate]), loading or paint.
///
/// ## Clamp sequence
///
/// 1. Max box = `maxWidth × (maxWidth + singlePhotoHeightExtra)`, each side
///    soft-capped by [MediaLayoutMetrics.photoSizeCap].
/// 2. Scale the nominal `(aspectRatio, 1)` into that width (truncated to
///    whole pixels).
/// 3. If the height exceeds the max box, clamp it and rescale the width.
/// 4. If the height is below [MediaLayoutMetrics.minMediaHeight], raise it
///    to that floor; shrink the width only when the aspect-scaled width
///    would be narrower than [maxWidth].
///
/// [kind] does not change the box: photo, video and animation share it and
/// differ only in policy values. It MUST be a box kind; a file or custom
/// kind is a file row, not a box.
///
/// [aspectRatio] ≤ 0 or [maxWidth] ≤ 0 gives [Size.zero].
Size computeSingleMediaSize({
  required double aspectRatio,
  required double maxWidth,
  MediaItemKind kind = MediaItemKind.photo,
}) {
  assert(
    kind == MediaItemKind.photo ||
        kind == MediaItemKind.video ||
        kind == MediaItemKind.animation,
    'Only photo, video and animation items are boxes; $kind is a file row.',
  );
  if (maxWidth <= 0 || aspectRatio <= 0) {
    return Size.zero;
  }

  var photoWidth = maxWidth;
  var photoHeight = photoWidth + MediaLayoutMetrics.singlePhotoHeightExtra;

  if (photoWidth > MediaLayoutMetrics.photoSizeCap) {
    photoWidth = MediaLayoutMetrics.photoSizeCap;
  }
  if (photoHeight > MediaLayoutMetrics.photoSizeCap) {
    photoHeight = MediaLayoutMetrics.photoSizeCap;
  }

  // Nominal picture dimensions that keep the aspect (w = ar, h = 1).
  final imageW = aspectRatio;
  const imageH = 1.0;

  final scale = imageW / photoWidth;
  var w = (imageW / scale).truncateToDouble();
  var h = (imageH / scale).truncateToDouble();
  if (w == 0) {
    w = MediaLayoutMetrics.minMediaHeight;
  }
  if (h == 0) {
    h = MediaLayoutMetrics.minMediaHeight;
  }

  if (h > photoHeight) {
    final scale2 = h / photoHeight;
    h = photoHeight;
    w = (w / scale2).truncateToDouble();
  } else if (h < MediaLayoutMetrics.minMediaHeight) {
    h = MediaLayoutMetrics.minMediaHeight;
    final hScale = imageH / h;
    if (imageW / hScale < photoWidth) {
      w = (imageW / hScale).truncateToDouble();
    }
  }

  return Size(w, h);
}
