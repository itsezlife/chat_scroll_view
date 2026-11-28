import 'package:flutter/widgets.dart';
import 'package:message_media/src/chrome/media_chrome_slots.dart';
import 'package:mpx_core/mpx_core.dart';

/// The per-item sent check: a check on the status control's disc, drawn
/// while the item's upload has finished and its message is not yet
/// published (`AssetTransfer.sent`).
///
/// The disc and the check take the status control's look from the nearest
/// `MediaLoadingStyleScope` (its diameter, disc and icon colours), so the
/// check sits where the upload ring was. Once the content is published
/// under its server identity the transfer reads `none` and the check goes;
/// the picture stays the local one until the cache holds the server's.
class MediaSentCheck extends StatelessWidget {
  /// The check, sized and coloured as the status control.
  const MediaSentCheck({super.key});

  /// The default `MediaChromeSlots.sentCheck` slot: the check in place of
  /// the stock control (which shows nothing for a sent upload).
  static Widget builder(
    BuildContext context,
    MediaChromeData data,
    AssetLoadState state,
    Widget stock,
  ) => const MediaSentCheck();

  @override
  Widget build(BuildContext context) {
    final style = MediaLoadingStyleScope.resolve(context).status;
    return SizedBox.square(
      dimension: style.diameter,
      child: CustomPaint(
        painter: _SentCheckPainter(
          disc: style.discColor,
          check: style.iconColor,
        ),
      ),
    );
  }
}

class _SentCheckPainter extends CustomPainter {
  const _SentCheckPainter({required this.disc, required this.check});

  final Color disc;
  final Color check;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final centre = size.center(Offset.zero);
    canvas.drawCircle(centre, radius, Paint()..color = disc);
    // A check across the middle half of the disc: the short stroke down to
    // the left of centre, the long one up to the right.
    final unit = radius / 2;
    final path = Path()
      ..moveTo(centre.dx - unit, centre.dy)
      ..lineTo(centre.dx - unit * 0.3, centre.dy + unit * 0.7)
      ..lineTo(centre.dx + unit, centre.dy - unit * 0.6);
    canvas.drawPath(
      path,
      Paint()
        ..color = check
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SentCheckPainter oldDelegate) =>
      oldDelegate.disc != disc || oldDelegate.check != check;
}
