import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// What a release does to a pack sheet that a drag moved.
enum PackSheetRelease {
  /// The pull went past the dismiss distance, or the finger flicked down
  /// fast: the sheet closes.
  dismiss,

  /// The sheet was pulled a little: it slides back up.
  springBack,

  /// The sheet holds no pull (the drag gave it all back): nothing to settle.
  rest,
}

/// The one owner of a bottom pack sheet's drag: how far a finger has pulled
/// the sheet below where it rests, and what a release does with that.
///
/// Every drag that moves the sheet reaches it, from the grid (the part past
/// its top, through a [CatalogOverscrollSink]) and from the header band
/// alike, so a pull from either place is one pull: it can start on the grid
/// and be undone from the header's drag, and closes the sheet by the same
/// rule. Rising with the grid is not this owner's: that is the grid's own
/// scroll, which the card follows.
///
/// Pixels and velocities are in the finger's sign (positive is down).
final class PackSheetDrag {
  /// An owner at rest, closing past [dismissDistance] logical pixels or on a
  /// flick of [dismissVelocity] physical pixels per second.
  PackSheetDrag({required this.dismissDistance, required this.dismissVelocity});

  /// How far a pull closes the sheet.
  final double dismissDistance;

  /// The downward flick, in physical pixels per second, that closes the
  /// sheet whatever the pull.
  final double dismissVelocity;

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
  /// px/s: the speed of the sheet's own pull, not of the finger's whole drag
  /// (a fast scroll that only runs a little past the grid's top is a slow
  /// pull).
  ///
  /// Only a sheet that holds a pull settles: one that gave it all back leaves
  /// the release to the grid. The flick closes it however short the pull.
  PackSheetRelease release(double velocity) {
    if (_translation <= 0) return PackSheetRelease.rest;
    if (_translation > dismissDistance || velocity >= dismissVelocity) {
      return PackSheetRelease.dismiss;
    }
    return PackSheetRelease.springBack;
  }
}

/// Hands a bottom pack sheet's drag owner to the sheet's body: the grid
/// passes [sink] to its viewport, and the header band drives the same sink.
///
/// Absent in the box under a pointer, which no drag moves.
class PackSheetDragScope extends InheritedWidget {
  /// Puts [sink] above [child].
  const PackSheetDragScope({
    required this.sink,
    required super.child,
    super.key,
  });

  /// The owner's sink.
  final CatalogOverscrollSink sink;

  /// The nearest owner's sink, or null where no drag moves the sheet.
  static CatalogOverscrollSink? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PackSheetDragScope>()?.sink;

  @override
  bool updateShouldNotify(PackSheetDragScope oldWidget) =>
      !identical(sink, oldWidget.sink);
}
