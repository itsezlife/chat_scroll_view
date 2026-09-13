import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// --- ChatSpanFeedback Model ------------------------------------------------

/// Transient tactile visual feedback for a pressed actionable inline element
/// (hyperlink, inline code snippet, mention, or fenced copy chrome).
///
/// ## Overview
///
/// Ink arms on pointer **down**, holds while pressed, and fades on **up** /
/// cancel — Telegram `LinkSpanDrawable` press tracking. Short tap and
/// long-press share this lifecycle; host long-press actions are a separate
/// side channel.
///
/// Encapsulates:
/// - [messageId]: Containing message row.
/// - [contourPath]: Closed vector-smoothed path from `ChatSmoothContour`.
/// - [touchOrigin]: Content-local pointer coordinates at press down.
/// - [pressController]: Expand clock (`pressT` 0→1).
/// - [releaseController]: Fade clock (`releaseT` 1→0); stays at 0 while held.
///
/// ## Lifecycle & Timing Invariants
///
/// 1. **Expand ([pressT]):** Ripple expands from [touchOrigin] with
///    \( R(t) = \text{pressT} \cdot R_{\max} \) clipped to [contourPath] over
///    [pressDuration] (60 ms), ease-out.
/// 2. **Hold:** While the pointer is down, [pressController] stays at 1.0 and
///    [releaseController] stays at 0.0 (`releaseT == 1`).
/// 3. **Release ([releaseT]):** After up (and after expand completes for quick
///    taps), [releaseController] runs [releaseDuration] (120 ms); opacity fades
///    with ease-out. Quick taps still get a full expand before fade so the
///    flash remains visible.
///
/// [listenable] merges both controllers for canvas repaint without widget
/// rebuilds.
class ChatSpanFeedback {
  /// Creates an active span feedback descriptor.
  ChatSpanFeedback({
    required this.messageId,
    required this.contourPath,
    required this.touchOrigin,
    required this.pressController,
    required this.releaseController,
    this.color,
  });

  /// The message ID whose body contains the pressed span.
  final int messageId;

  /// The vector-smoothed contour path wrapping the span's bounding boxes.
  final Path contourPath;

  /// Content-local coordinates of the initial pointer-down within the body.
  final Offset touchOrigin;

  /// Expand clock: 0→1 over [pressDuration].
  final AnimationController pressController;

  /// Release clock: 0 while held; 0→1 over [releaseDuration] while fading.
  final AnimationController releaseController;

  /// Optional highlight accent. Falls back to the ambient theme link color.
  final Color? color;

  /// Expand duration (60 ms) — also the minimum visibility before fade.
  static const int pressDurationMs = 60;

  /// Release fade duration (120 ms).
  static const int releaseDurationMs = 120;

  /// Expand duration as a [Duration].
  static const Duration pressDuration = Duration(milliseconds: pressDurationMs);

  /// Release duration as a [Duration].
  static const Duration releaseDuration = Duration(
    milliseconds: releaseDurationMs,
  );

  /// Legacy total of expand + release (quick-tap end-to-end).
  static const Duration totalDuration = Duration(
    milliseconds: pressDurationMs + releaseDurationMs,
  );

  /// Minimum visibility hold — same as [pressDurationMs].
  static const int minHoldDurationMs = pressDurationMs;

  /// Release fade-out duration — same as [releaseDurationMs].
  static const int releaseFadeDurationMs = releaseDurationMs;

  /// Merged listenable for [ChatSpanFeedbackPainter] repaints.
  Listenable get listenable =>
      Listenable.merge(<Listenable>[pressController, releaseController]);

  /// Expansion progress of the circular ripple (0.0 to 1.0).
  double get pressT {
    final t = pressController.value;
    if (t <= 0.0) return 0;
    if (t >= 1.0) return 1;
    return Curves.easeOut.transform(t).clamp(0.0, 1.0);
  }

  /// Opacity multiplier (1.0 while expanding/held → 0.0 after release fade).
  double get releaseT {
    final t = releaseController.value;
    if (t <= 0.0) return 1;
    if (t >= 1.0) return 0;
    return (1.0 - Curves.easeOut.transform(t)).clamp(0.0, 1.0);
  }

  /// Whether the release fade has started (including completed).
  bool get isReleasing =>
      releaseController.value > 0.0 || releaseController.isAnimating;

  /// Whether expand has finished and release has not started.
  bool get isHeld =>
      pressController.value >= 1.0 &&
      !releaseController.isAnimating &&
      releaseController.value == 0.0;
}

// --- ChatSpanFeedbackPainter -----------------------------------------------

/// Canvas painter for press-lifecycle contour plate and expanding ripple.
///
/// Paints two layered components:
/// 1. **Base Contour Fill:** Tint \(\alpha \approx 0.15 \times \text{releaseT}\)
///    over [ChatSpanFeedback.contourPath].
/// 2. **Radial Ripple:** Circle at [ChatSpanFeedback.touchOrigin] with radius
///    \( R = \text{pressT} \cdot R_{\max} \), clipped to the contour, at
///    \(\alpha \approx 0.20 \times \text{releaseT}\).
///
/// Repaints from [repaint] (typically [ChatSpanFeedback.listenable]) only.
class ChatSpanFeedbackPainter extends CustomPainter {
  /// Creates a span feedback canvas painter.
  ChatSpanFeedbackPainter({required this.feedback, super.repaint});

  /// The active span feedback, or null when idle.
  final ChatSpanFeedback? feedback;

  @override
  void paint(Canvas canvas, Size size) {
    final fb = feedback;
    if (fb == null) return;
    final release = fb.releaseT;
    if (release <= 0.0) return;

    final color = fb.color ?? const Color(0xFF007AFF);
    final path = fb.contourPath;
    final origin = fb.touchOrigin;
    final press = fb.pressT;

    // 1. Base contour plate fill
    final baseAlpha = (0.15 * release).clamp(0.0, 1.0);
    if (baseAlpha > 0.0) {
      final basePaint = Paint()
        ..color = color.withValues(alpha: baseAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, basePaint);
    }

    // 2. Expanding circular ripple clipped to smooth contour path
    if (press > 0.0) {
      final bounds = path.getBounds();
      final dx = math.max(
        (origin.dx - bounds.left).abs(),
        (origin.dx - bounds.right).abs(),
      );
      final dy = math.max(
        (origin.dy - bounds.top).abs(),
        (origin.dy - bounds.bottom).abs(),
      );
      final maxRadius = math.sqrt(dx * dx + dy * dy);
      final currentRadius = maxRadius * press;

      final rippleAlpha = (0.20 * release).clamp(0.0, 1.0);
      if (rippleAlpha > 0.0 && currentRadius > 0.0) {
        canvas.save();
        canvas.clipPath(path);
        final ripplePaint = Paint()
          ..color = color.withValues(alpha: rippleAlpha)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(origin, currentRadius, ripplePaint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChatSpanFeedbackPainter oldDelegate) =>
      oldDelegate.feedback != feedback;
}
