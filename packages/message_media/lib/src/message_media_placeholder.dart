import 'package:flutter/widgets.dart';
import 'package:message_media/src/media_layout_metrics.dart';
import 'package:message_media/src/mosaic_layout.dart';
import 'package:message_media/src/single_media_layout.dart';

/// Default muted fill for media placeholders (no network images).
///
/// Opaque mid-gray on dark chat chrome so mosaic seams and radii stay visible
/// without implying a decoded bitmap.
const Color kMessageMediaPlaceholderColor = Color(0xFF3A3A40);

/// Paints a single media placeholder or a multi-cell mosaic with TRACE’d
/// gaps and outer/inner radii.
///
/// Owns: solid fills in geometry rects for judging layout. Does not own:
/// image-receiver bind, downloads, captions, or chat-list fan-out.
///
/// ## Sizing
///
/// Painted size is fixed by layout math — not by incoming box constraints:
/// - **Single:** [computeSingleMediaSize] at [maxWidth] (default 300).
/// - **Mosaic:** [MosaicLayout.size] from a prior [MosaicLayout.project].
///
/// Outer/inner radii for mosaics are baked into that [MosaicLayout]; the
/// mosaic constructor does not take a separate bubble radius.
class MessageMediaPlaceholder extends StatelessWidget {
  /// Single photo/video placeholder sized like Telegram at [maxWidth].
  const MessageMediaPlaceholder.single({
    super.key,
    required this.aspectRatio,
    this.maxWidth = 300,
    this.bubbleRadius = 17,
    this.color = kMessageMediaPlaceholderColor,
  }) : mosaic = null;

  /// Grouped mosaic placeholder from a precomputed [MosaicLayout].
  ///
  /// Radii and gaps come from [MosaicLayout.project]; this widget only paints.
  const MessageMediaPlaceholder.mosaic({
    super.key,
    required MosaicLayout this.mosaic,
    this.color = kMessageMediaPlaceholderColor,
  }) : aspectRatio = null,
       maxWidth = null,
       bubbleRadius = 17;

  /// Aspect for the single-media path; `null` when [mosaic] is set.
  final double? aspectRatio;

  /// Max width for [computeSingleMediaSize]; unused on the mosaic path.
  final double? maxWidth;

  /// Precomputed mosaic; `null` on the single-media path.
  final MosaicLayout? mosaic;

  /// Host bubble radius → outer media corner on the **single** path only
  /// ([MediaLayoutMetrics.mediaOuterRadius]).
  final double bubbleRadius;

  /// Solid fill for every media rect.
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (mosaic case final layout?) {
      return CustomPaint(
        size: layout.size,
        painter: _MediaPlaceholderPainter(
          mosaic: layout,
          single: null,
          color: color,
        ),
      );
    }

    final width = maxWidth ?? 300;
    final size = computeSingleMediaSize(
      aspectRatio: aspectRatio ?? 1,
      maxWidth: width,
    );
    final outer = MediaLayoutMetrics.mediaOuterRadius(
      bubbleRadius: bubbleRadius,
    );
    return CustomPaint(
      size: size,
      painter: _MediaPlaceholderPainter(
        mosaic: null,
        single: _SinglePlaceholder(
          size: size,
          radius: BorderRadius.circular(outer),
        ),
        color: color,
      ),
    );
  }
}

/// Single-rect paint payload for [_MediaPlaceholderPainter].
final class _SinglePlaceholder {
  const _SinglePlaceholder({required this.size, required this.radius});

  final Size size;
  final BorderRadius radius;
}

/// Draws either one rounded rect or every [MosaicCellLayout] with [color].
///
/// Does not hit-test cells; the parent [CustomPaint] size is the only layout
/// contribution.
final class _MediaPlaceholderPainter extends CustomPainter {
  _MediaPlaceholderPainter({
    required this.mosaic,
    required this.single,
    required this.color,
  });

  final MosaicLayout? mosaic;
  final _SinglePlaceholder? single;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (mosaic case final layout?) {
      for (final cell in layout.cells) {
        final rrect = cell.borderRadius.toRRect(cell.rect);
        canvas.drawRRect(rrect, paint);
      }
      return;
    }
    if (single case final s?) {
      final rect = Offset.zero & s.size;
      canvas.drawRRect(s.radius.toRRect(rect), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MediaPlaceholderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.mosaic != mosaic ||
      oldDelegate.single != single;
}
