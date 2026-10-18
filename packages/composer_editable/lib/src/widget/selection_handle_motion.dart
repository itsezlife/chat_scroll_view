import 'dart:ui' show Offset, Rect, lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart' show MagnifierInfo;

/// Android `OvershootInterpolator` with the default tension of `2.0`.
///
/// Used when scaling selection handles in via appear progress.
class OvershootCurve extends Curve {
  /// Creates an overshoot curve.
  ///
  /// [tension] matches `OvershootInterpolator(float tension)`; default
  /// tension is `2.0`.
  const OvershootCurve([this.tension = 2.0]);

  /// Amount of overshoot; higher values bounce further past 1.0.
  final double tension;

  @override
  double transformInternal(double t) {
    final shifted = t - 1.0;
    return shifted * shifted * ((tension + 1.0) * shifted + tension) + 1.0;
  }
}

/// Duration for handle appear and handle settle on release (~250ms).
const Duration kTelegramHandleMotionDuration = Duration(milliseconds: 250);

/// Alias for settle duration (same as appear).
const Duration kHandleSettleDuration = kTelegramHandleMotionDuration;

/// AOSP `MagnifierMotionAnimator` settle time constant (~100ms).
///
/// Touch editable path uses this for **both** X and Y (unified rate).
const double kAospMagnifierSettleMs = 100;

/// @nodoc Kept for callers that still name the old X constant.
const double kTelegramMagnifierXSettleMs = kAospMagnifierSettleMs;

/// @nodoc Legacy Y rate alias — equals [kAospMagnifierSettleMs].
const double kTelegramMagnifierYSettleMs = kAospMagnifierSettleMs;

/// Smooths [MagnifierInfo] toward [target] with AOSP-like ~100ms X/Y rates.
///
/// Both axes use [kAospMagnifierSettleMs] (editable / `MagnifierMotionAnimator`
/// parity — unified rate, not a split X/Y path).
MagnifierInfo smoothMagnifierInfo({
  required MagnifierInfo? previous,
  required MagnifierInfo target,
  required Duration elapsed,
}) {
  if (previous == null || previous == MagnifierInfo.empty) {
    return target;
  }

  final ms = elapsed.inMicroseconds / 1000.0;
  if (ms <= 0) {
    return previous;
  }

  final alpha = (ms / kAospMagnifierSettleMs).clamp(0.0, 1.0);

  final gesture = Offset(
    lerpDouble(
      previous.globalGesturePosition.dx,
      target.globalGesturePosition.dx,
      alpha,
    )!,
    lerpDouble(
      previous.globalGesturePosition.dy,
      target.globalGesturePosition.dy,
      alpha,
    )!,
  );

  final caret = Rect.fromLTRB(
    lerpDouble(previous.caretRect.left, target.caretRect.left, alpha)!,
    lerpDouble(previous.caretRect.top, target.caretRect.top, alpha)!,
    lerpDouble(previous.caretRect.right, target.caretRect.right, alpha)!,
    lerpDouble(previous.caretRect.bottom, target.caretRect.bottom, alpha)!,
  );

  final line = Rect.fromLTRB(
    lerpDouble(
      previous.currentLineBoundaries.left,
      target.currentLineBoundaries.left,
      alpha,
    )!,
    lerpDouble(
      previous.currentLineBoundaries.top,
      target.currentLineBoundaries.top,
      alpha,
    )!,
    lerpDouble(
      previous.currentLineBoundaries.right,
      target.currentLineBoundaries.right,
      alpha,
    )!,
    lerpDouble(
      previous.currentLineBoundaries.bottom,
      target.currentLineBoundaries.bottom,
      alpha,
    )!,
  );

  // Field bounds snap — they rarely change during a handle drag.
  return MagnifierInfo(
    globalGesturePosition: gesture,
    caretRect: caret,
    currentLineBoundaries: line,
    fieldBounds: target.fieldBounds,
  );
}

/// Whether [a] and [b] are close enough that further smoothing is unnecessary.
bool magnifierInfoSettled(
  MagnifierInfo a,
  MagnifierInfo b, {
  double epsilon = 0.5,
}) {
  bool near(double x, double y) => (x - y).abs() < epsilon;
  bool nearOffset(Offset x, Offset y) => near(x.dx, y.dx) && near(x.dy, y.dy);
  bool nearRect(Rect x, Rect y) =>
      near(x.left, y.left) &&
      near(x.top, y.top) &&
      near(x.right, y.right) &&
      near(x.bottom, y.bottom);

  return nearOffset(a.globalGesturePosition, b.globalGesturePosition) &&
      nearRect(a.caretRect, b.caretRect) &&
      nearRect(a.currentLineBoundaries, b.currentLineBoundaries);
}

/// Maps settle elapsed time to a `0…1` fraction for [computeHandleDragChrome].
///
/// Uses [kHandleSettleDuration] (~250ms). Callers pass the result as `settleT`.
double settleTForElapsed(Duration elapsed) {
  if (elapsed <= Duration.zero) {
    return 0;
  }
  return (elapsed.inMicroseconds / kHandleSettleDuration.inMicroseconds).clamp(
    0.0,
    1.0,
  );
}
