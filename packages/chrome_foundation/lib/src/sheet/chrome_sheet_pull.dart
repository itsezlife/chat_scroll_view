import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// What a release does to a bottom sheet that a drag pulled down.
enum ChromeSheetRelease {
  /// The pull went past the dismiss distance, or the finger flicked down
  /// fast: the sheet closes.
  dismiss,

  /// The sheet was pulled a little: it slides back up.
  springBack,

  /// The sheet holds no pull (the drag gave it all back): nothing to settle.
  rest,
}

/// How a bottom sheet's pull closes it: past [dismissDistance] logical
/// pixels, or on a downward flick of [dismissVelocity] physical pixels per
/// second; a shorter, slower pull springs back over [springBack] scaled by
/// the share of the distance it holds, on [springBackCurve], from wherever
/// the finger left the sheet.
@immutable
final class ChromeSheetDragSpec {
  /// A spec closing past [dismissDistance] or on [dismissVelocity].
  const ChromeSheetDragSpec({
    required this.dismissDistance,
    required this.dismissVelocity,
    required this.springBack,
    this.springBackCurve = Curves.ease,
  });

  /// How far a pull closes the sheet, in logical pixels.
  final double dismissDistance;

  /// The downward flick, in physical pixels per second, that closes the
  /// sheet whatever the pull.
  final double dismissVelocity;

  /// How long springing back from a pull of [dismissDistance] takes; a
  /// shorter pull takes its share of it, on an ease out.
  final Duration springBack;

  /// The spring back's curve: by default the standard ease
  /// (`Cubic(0.25, 0.1, 0.25, 1)`), the curve a picker sheet returns to
  /// its rest on, so every bottom sheet a pull leaves low settles alike.
  final Curve springBackCurve;
}

/// The one owner of a bottom sheet's pull: how far a finger has pulled the
/// sheet below where it rests, and what a release does with that.
///
/// Every drag that moves the sheet reaches it (from the content's scroll
/// past its top and from a header band alike), so a pull from either place
/// is one pull: it can start on the content and be undone from the header,
/// and it closes the sheet by the same rule.
///
/// Pixels and velocities are in the finger's sign (positive is down).
final class ChromeSheetPull {
  /// An owner at rest, closing by [spec].
  ChromeSheetPull(this.spec);

  /// The dismiss rule.
  final ChromeSheetDragSpec spec;

  double _translation = 0;

  /// How far below its rest the sheet is, never negative.
  double get translation => _translation;

  /// The sheet's own animation (springing back) moved it, not a finger.
  set translation(double value) => _translation = math.max(0, value);

  /// Offers [pixels] of a drag and returns how many the sheet took: all of a
  /// pull down, and of a push up only what undoes the pull.
  double take(double pixels) {
    final taken = math.max(pixels, -_translation);
    _translation += taken;
    return taken;
  }

  /// What a release does when the pull was moving at [velocity] physical
  /// px/s: the speed of the sheet's own pull, not of the finger's whole drag.
  ///
  /// Only a sheet that holds a pull settles: one that gave it all back leaves
  /// the release to the content. The flick closes it however short the pull.
  ChromeSheetRelease release(double velocity) {
    if (_translation <= 0) return ChromeSheetRelease.rest;
    if (_translation > spec.dismissDistance ||
        velocity >= spec.dismissVelocity) {
      return ChromeSheetRelease.dismiss;
    }
    return ChromeSheetRelease.springBack;
  }
}

/// Where a bottom sheet's content hands it the drags that move it:
/// `ChromeSheetDrag.maybeOf(context)`.
abstract interface class ChromeSheetDragSink {
  /// A drag started: the sheet stops springing back.
  void start();

  /// Offers [pixels] of a drag (finger sign) and returns how many the sheet
  /// took.
  double take(double pixels);

  /// The finger lifted, the sheet's own share of the drag moving at
  /// [velocity] logical px/s; true when the sheet takes the release (it
  /// springs back or closes).
  bool release(double velocity);
}
