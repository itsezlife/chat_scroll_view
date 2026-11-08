import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart';

/// The reference client's download indicator for media: a translucent dark
/// disc holding a white arc that turns and grows with the fraction of the
/// content downloaded.
///
/// One indicator is one download on one surface, and it is stateful, as the
/// reference's drawable is: the arc's start angle turns frame by frame, and a
/// new fraction eases in from the arc the surface is showing. A surface makes
/// one when a download starts for what it shows (`AssetBinding.
/// downloadProgress` turns non-null), gives it each fraction with
/// [setProgress], steps it once per frame it paints with [advance] and drops
/// it when the download ends. A surface shows none for content that needs no
/// download.
///
/// | Measure | Value | Reference |
/// | ------- | ----- | --------- |
/// | disc radius | the caller's: 12 in a panel cell | `ContextLinkCell.onMeasure` |
/// | arc radius | disc radius less [arcInset] | `MediaActionDrawable.draw` |
/// | stroke | [strokeWidth], [thinStrokeWidth] below 0.7 of [referenceDiameter] | `MediaActionDrawable.setBounds` |
/// | start | [initialDegrees] for a new indicator | `setIcon`, `downloadRadOffset = 112` |
/// | turn | 360 degrees per [turnPeriod], a frame counting at most [maxFrameStep] | `MediaActionDrawable.draw` |
/// | sweep | `max(4°, 360° * shownProgress)` | `MediaActionDrawable.draw` |
/// | a higher fraction | eases from the arc shown over [easeDuration], [easeCurve] | `MediaActionDrawable.draw` |
/// | a lower fraction | shown at once | `setProgress` |
///
/// The indicator of a loading grid cell is the reference's `ICON_EMPTY`: a
/// bare arc, without the cross of a message's cancel button.
///
/// ## What it leaves out
///
/// The reference fades the disc out over 400 ms when the download ends; the
/// surface's own content fade ends the indicator here, so [paint] takes the
/// `opacity` the surface fades it with.
final class RadialProgress {
  /// Creates the indicator of a download that has [progress] done, shown at
  /// once: the reference starts a cell's arc from the file's known progress,
  /// not animated (`ContextLinkCell.updateButtonState`).
  RadialProgress({double progress = 0}) {
    setProgress(progress, animated: false);
  }

  /// The disc: `key_chat_mediaLoaderPhoto`.
  static const Color discColor = Color(0x66000000);

  /// The arc: `key_chat_mediaLoaderPhotoIcon`.
  static const Color inkColor = Color(0xFFFFFFFF);

  /// The disc's box is inset this much (logical pixels) for the arc.
  static const double arcInset = 4;

  /// The stroke of the arc.
  static const double strokeWidth = 3;

  /// The stroke below [thinThreshold] of the reference size.
  static const double thinStrokeWidth = 2;

  /// The reference icon box (`MediaActionDrawable.getIntrinsicWidth`), the
  /// size the thin stroke scales against.
  static const double referenceDiameter = 48;

  /// A disc narrower than this fraction of [referenceDiameter] draws the thin
  /// stroke.
  static const double thinThreshold = 0.7;

  /// Where the arc of a new indicator starts, in degrees clockwise from three
  /// o'clock.
  static const double initialDegrees = 112;

  /// One full turn of the arc.
  static const Duration turnPeriod = Duration(milliseconds: 2500);

  /// The most one frame advances the turn and the ease: a frame after a
  /// pause (a hidden surface, a jank) moves the arc one frame on, not by the
  /// whole gap.
  static const Duration maxFrameStep = Duration(milliseconds: 17);

  /// How long a higher fraction takes to reach the arc.
  static const Duration easeDuration = Duration(milliseconds: 200);

  /// How a higher fraction eases in: decelerating, `1 - (1 - t)^2`.
  static const Curve easeCurve = Curves.decelerate;

  /// The shortest the arc gets, in degrees: a dot that is already turning.
  static const double minSweepDegrees = 4;

  // Painting is single-threaded and the paint is set fully on every call, so
  // one shared object saves an allocation per indicator per frame.
  static final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  double _progress = 0;
  double _shown = 0;
  // Where the running ease started, and how long it has run.
  double _easeFrom = 0;
  Duration _eased = Duration.zero;
  double _startDegrees = initialDegrees;
  Duration? _lastFrame;

  /// The fraction downloaded, 0 to 1, as last set.
  double get progress => _progress;

  /// The fraction the arc sweeps now: [progress], or on its way to it.
  double get shownProgress => _shown;

  /// Where the arc starts now, in degrees from 0 to 360 clockwise from three
  /// o'clock.
  double get startDegrees => _startDegrees;

  /// Sets the fraction downloaded to [value] (clamped to 0..1).
  ///
  /// Animated, a higher value eases in from the arc shown and a lower one
  /// (a download that started again) is shown at once; not animated, the arc
  /// shows [value] at once.
  void setProgress(double value, {bool animated = true}) {
    final next = value.clamp(0.0, 1.0);
    if (next == _progress) return;
    if (!animated || _shown > next) _shown = next;
    _easeFrom = _shown;
    _progress = next;
    _eased = Duration.zero;
  }

  /// Steps the turn and the ease to the frame at [frameTime]: by the time
  /// since the previous call, at most [maxFrameStep]. The first call only
  /// sets the clock, and a time before the previous one steps nothing.
  void advance(Duration frameTime) {
    final last = _lastFrame;
    _lastFrame = frameTime;
    if (last == null || frameTime <= last) return;
    final step = frameTime - last;
    final dt = step > maxFrameStep ? maxFrameStep : step;
    _startDegrees =
        (_startDegrees + 360 * dt.inMicroseconds / turnPeriod.inMicroseconds) %
        360;
    final gap = _progress - _easeFrom;
    if (gap <= 0) return;
    _eased += dt;
    if (_eased >= easeDuration) {
      _shown = _easeFrom = _progress;
      _eased = Duration.zero;
    } else {
      _shown =
          _easeFrom +
          gap *
              easeCurve.transform(
                _eased.inMicroseconds / easeDuration.inMicroseconds,
              );
    }
  }

  /// Paints the indicator, a disc of [radius] around [center], on [canvas];
  /// [opacity] fades the whole of it.
  void paint(
    Canvas canvas,
    Offset center, {
    required double radius,
    double opacity = 1,
  }) {
    if (opacity <= 0 || radius <= 0) return;
    final scale = 2 * radius / referenceDiameter;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = _faded(discColor, opacity),
    );
    _paint
      ..color = _faded(inkColor, opacity)
      ..strokeWidth = scale < thinThreshold ? thinStrokeWidth : strokeWidth;
    final sweep = math.max(minSweepDegrees, 360 * _shown);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - arcInset),
      _startDegrees * math.pi / 180,
      sweep * math.pi / 180,
      false,
      _paint,
    );
  }

  static Color _faded(Color color, double opacity) => opacity >= 1
      ? color
      : color.withValues(alpha: color.a * opacity.clamp(0.0, 1.0));
}
