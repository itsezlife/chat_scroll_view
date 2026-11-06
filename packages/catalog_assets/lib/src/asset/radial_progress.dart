import 'dart:math' as math;
import 'dart:ui';

/// The reference client's loading indicator for media: a translucent dark disc
/// holding a white arc that turns while the content downloads, with a cross
/// (cancel) in the middle.
///
/// A surface paints it over the content's thumbnail for as long as the content
/// is not there, and passes the frame time of its pass: the arc is a function
/// of time, so a pass that already runs for another reason (the viewport's
/// loading wash) animates every indicator on screen from one clock, with no
/// controller of its own per cell.
///
/// | Measure | Value | Reference |
/// | ------- | ----- | --------- |
/// | disc radius | the caller's: 12 in a panel cell, 22 in a message | `ContextLinkCell` / `RadialProgress2` |
/// | arc radius | disc radius less [arcInset] | `MediaActionDrawable.draw` |
/// | stroke | [strokeWidth], [thinStrokeWidth] below 0.7 of [referenceDiameter] | `MediaActionDrawable.setBounds` |
/// | turn | one circle per [turnPeriod], linear | `downloadRadOffset` |
/// | sweep | `max(4°, 360° * progress)` | `MediaActionDrawable.draw` |
/// | cross | 7 * disc diameter / 48 from the centre | `ICON_CANCEL` |
///
/// ## What it leaves out
///
/// The reference eases a progress change over 200 ms and fades the cross and
/// the disc over 400 ms when the download ends; this package knows no byte
/// progress (the cache reports stages, not fractions) and the surface's own
/// content fade ends the indicator, so [paint] takes the `opacity` the surface
/// fades it with instead. When no fraction is known it sweeps
/// [indeterminateProgress], which the reference never needs: it always knows
/// how much arrived.
abstract final class RadialProgress {
  /// The disc: `key_chat_mediaLoaderPhoto`.
  static const Color discColor = Color(0x66000000);

  /// The arc and the cross: `key_chat_mediaLoaderPhotoIcon`.
  static const Color inkColor = Color(0xFFFFFFFF);

  /// The disc's box is inset this much (logical pixels) for the arc.
  static const double arcInset = 4;

  /// The stroke of the arc and the cross.
  static const double strokeWidth = 3;

  /// The stroke below [thinThreshold] of the reference size.
  static const double thinStrokeWidth = 2;

  /// The reference icon box (`MediaActionDrawable.getIntrinsicWidth`), the
  /// size the cross and the thin stroke scale against.
  static const double referenceDiameter = 48;

  /// A disc narrower than this fraction of [referenceDiameter] draws the thin
  /// stroke.
  static const double thinThreshold = 0.7;

  /// How far the cross reaches from the centre at [referenceDiameter].
  static const double crossReach = 7;

  /// One full turn of the arc.
  static const Duration turnPeriod = Duration(milliseconds: 2500);

  /// The shortest the arc gets, in degrees: a dot that is already turning.
  static const double minSweepDegrees = 4;

  /// The fraction the arc sweeps when none is known.
  static const double indeterminateProgress = 0.25;

  // Painting is single-threaded and the paint is set fully on every call, so
  // one shared object saves an allocation per indicator per frame.
  static final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// Paints the indicator of a disc of [radius] around [center] at [time] on
  /// [canvas]. [progress] is the fraction done from 0 to 1, or null when not
  /// known; [opacity] fades the whole indicator.
  static void paint(
    Canvas canvas,
    Offset center, {
    required double radius,
    required Duration time,
    double? progress,
    double opacity = 1,
  }) {
    if (opacity <= 0 || radius <= 0) return;
    final scale = 2 * radius / referenceDiameter;
    final stroke = scale < thinThreshold ? thinStrokeWidth : strokeWidth;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = _faded(discColor, opacity),
    );
    _paint
      ..color = _faded(inkColor, opacity)
      ..strokeWidth = stroke;
    final turn =
        (time.inMicroseconds % turnPeriod.inMicroseconds) /
        turnPeriod.inMicroseconds;
    final sweep = math.max(
      minSweepDegrees,
      360 * (progress ?? indeterminateProgress).clamp(0.0, 1.0),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - arcInset),
      turn * 2 * math.pi,
      sweep * math.pi / 180,
      false,
      _paint,
    );
    final reach = crossReach * scale;
    canvas
      ..drawLine(
        center - Offset(reach, reach),
        center + Offset(reach, reach),
        _paint,
      )
      ..drawLine(
        center + Offset(reach, -reach),
        center + Offset(-reach, reach),
        _paint,
      );
  }

  static Color _faded(Color color, double opacity) => opacity >= 1
      ? color
      : color.withValues(alpha: color.a * opacity.clamp(0.0, 1.0));
}
