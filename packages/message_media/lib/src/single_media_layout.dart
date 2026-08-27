import 'dart:ui';

import 'package:message_media/src/media_kind.dart';
import 'package:message_media/src/media_layout_metrics.dart';

/// Computes the layout box for a **single** photo or video at [maxWidth].
///
/// Owns: aspect → pixel [Size] under Telegram `ChatMessageCell.getMessageSize`
/// clamps. Does not own: grouped mosaics ([GroupedMessages.calculate]),
/// downloads, or paint.
///
/// ## Clamp sequence
///
/// 1. Max box = `[maxWidth] × (maxWidth + [MediaLayoutMetrics.singlePhotoHeightExtra])`,
///    soft-capped by [MediaLayoutMetrics.photoSizeCap].
/// 2. Scale nominal `(aspectRatio, 1)` into that width (integer truncate).
/// 3. If height exceeds the max box, clamp height and rescale width.
/// 4. If height is below [MediaLayoutMetrics.minMediaHeight], raise height to
///    that floor; shrink width only when the aspect-scaled width would be
///    narrower than [maxWidth].
///
/// [kind] does not change geometry — photo and video share the box.
///
/// Edge modes: [aspectRatio] ≤ 0 or [maxWidth] ≤ 0 → [Size.zero]. Callers MUST
/// pass `aspectRatio > 0` for real media.
Size computeSingleMediaSize({
  required double aspectRatio,
  required double maxWidth,
  MediaKind kind = MediaKind.photo,
}) {
  // Exhaustiveness / API surface; geometry ignores kind.
  assert(kind == MediaKind.photo || kind == MediaKind.video);
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

  // Nominal image dimensions that preserve aspect (w = ar, h = 1).
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
