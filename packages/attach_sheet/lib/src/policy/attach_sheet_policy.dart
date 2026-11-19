import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How a sheet motion runs: on a spring (physical, no motion role times it)
/// or over a duration.
@immutable
sealed class AttachSheetMotion {
  const AttachSheetMotion._();

  /// Follows [spring] from the current position and velocity.
  const factory AttachSheetMotion.spring(SpringDescription spring) =
      AttachSheetMotion$Spring;

  /// Runs [spec]'s duration and curve.
  const factory AttachSheetMotion.timed(MotionSpec spec) =
      AttachSheetMotion$Timed;
}

/// [AttachSheetMotion.spring].
final class AttachSheetMotion$Spring extends AttachSheetMotion {
  /// A spring motion.
  const AttachSheetMotion$Spring(this.spring) : super._();

  /// The spring.
  final SpringDescription spring;

  @override
  bool operator ==(Object other) =>
      other is AttachSheetMotion$Spring &&
      other.spring.mass == spring.mass &&
      other.spring.stiffness == spring.stiffness &&
      other.spring.damping == spring.damping;

  @override
  int get hashCode =>
      Object.hash(spring.mass, spring.stiffness, spring.damping);

  @override
  String toString() => 'AttachSheetMotion.spring($spring)';
}

/// [AttachSheetMotion.timed].
final class AttachSheetMotion$Timed extends AttachSheetMotion {
  /// A timed motion.
  const AttachSheetMotion$Timed(this.spec) : super._();

  /// Its duration and curve.
  final MotionSpec spec;

  @override
  bool operator ==(Object other) =>
      other is AttachSheetMotion$Timed && other.spec == spec;

  @override
  int get hashCode => spec.hashCode;

  @override
  String toString() => 'AttachSheetMotion.timed($spec)';
}

/// What a released drag of the sheet does.
enum AttachSheetRelease {
  /// The sheet closes.
  dismiss,

  /// The sheet rises to the top.
  expand,

  /// The sheet falls back to its resting height.
  collapse,

  /// The sheet returns to the top it started from.
  holdExpanded,

  /// The sheet returns to its resting height.
  holdCollapsed,

  /// The sheet keeps the drag's velocity with the page's scroll and rests
  /// where it stops (between the resting height and the top).
  fling,
}

/// Which question the discard guard asks.
enum AttachDiscardWording {
  /// "Discard selection?" with Discard and Cancel.
  discardSelection,

  /// "Cancel selection?" with Yes and No.
  cancelSelection,
}

/// The grabber pill at the sheet's top edge.
@immutable
final class AttachSheetGrabber {
  /// A pill of [size], [top] below the sheet's edge.
  const AttachSheetGrabber({
    required this.size,
    required this.top,
    required this.fadesWithHeader,
  });

  /// The pill's size.
  final Size size;

  /// Its distance below the sheet's top edge.
  final double top;

  /// Whether it fades out as the pinned header fades in.
  final bool fadesWithHeader;

  @override
  bool operator ==(Object other) =>
      other is AttachSheetGrabber &&
      other.size == size &&
      other.top == top &&
      other.fadesWithHeader == fadesWithHeader;

  @override
  int get hashCode => Object.hash(size, top, fadesWithHeader);
}

/// What a released drag knows: where the sheet is, where it rests, the
/// release velocity (logical pixels per second, positive downward) and
/// where the drag started.
@immutable
final class AttachSheetReleaseInput {
  /// A release of the sheet at [top].
  const AttachSheetReleaseInput({
    required this.top,
    required this.collapsedTop,
    required this.expandedTop,
    required this.velocity,
    required this.startedExpanded,
    required this.devicePixelRatio,
  });

  /// The sheet's top edge from the top of the screen.
  final double top;

  /// The top at the resting height.
  final double collapsedTop;

  /// The top when expanded.
  final double expandedTop;

  /// The release velocity, positive downward.
  final double velocity;

  /// Whether the drag started with the sheet expanded.
  final bool startedExpanded;

  /// Physical pixels per logical pixel, for thresholds a platform states in
  /// physical pixels.
  final double devicePixelRatio;
}

/// The **attach sheet policy**: geometry, motion, gestures, thresholds and
/// the discard rule of the attach sheet on one platform family. Plain
/// values with no widgets and no platform reads.
///
/// Two stock families: [AttachSheetPolicy.android] (a sheet that rises with
/// its page's scroll, pins at the top behind a header and is pulled down to
/// dismiss) and [AttachSheetPolicy.ios] (a sheet panned between a collapsed
/// inset and the top, released by a velocity table, and a card on a wide
/// screen). [AttachSheetPolicy.forPlatform] picks one. Not sealed: a host
/// changes one value by extending a stock family and overriding it.
@immutable
abstract base class AttachSheetPolicy {
  /// A policy; for subclasses.
  const AttachSheetPolicy();

  /// The Android family; see [AttachSheetPolicy$Android].
  const factory AttachSheetPolicy.android() = AttachSheetPolicy$Android;

  /// The iOS family; see [AttachSheetPolicy$IOS].
  const factory AttachSheetPolicy.ios() = AttachSheetPolicy$IOS;

  /// The family of [platform]: iOS its own, every other system the Android
  /// family. Desktop and web pick through a confirm box rather than a
  /// sheet; until their own families exist they get the Android values.
  factory AttachSheetPolicy.forPlatform(
    TargetPlatform platform, {
    required bool isWeb,
  }) => switch (platform) {
    TargetPlatform.iOS when !isWeb => const AttachSheetPolicy.ios(),
    _ => const AttachSheetPolicy.android(),
  };

  /// The family of the running app.
  factory AttachSheetPolicy.current() =>
      AttachSheetPolicy.forPlatform(defaultTargetPlatform, isWeb: kIsWeb);

  // --- Geometry ---

  /// The sheet's top edge at its resting height, for a screen of [size]
  /// with the safe [padding]. A page may move it (its top offset).
  double collapsedTop(Size size, EdgeInsets padding);

  /// The sheet's top edge when expanded.
  double expandedTop(EdgeInsets padding);

  /// The radius of the sheet's top corners at rest.
  double get cornerRadius;

  /// The top corners' radius on a screen of [size].
  double cornerRadiusFor(Size size) => cornerRadius;

  /// Whether the corners square off as the pinned header fades in.
  bool get squaresCornersWhenPinned;

  /// The grabber pill; null for none.
  AttachSheetGrabber? get grabber;

  /// How dark the scrim behind the sheet gets, 0 to 1.
  double get dimOpacity;

  /// The card a wide screen shows instead of a sheet, anchored to the
  /// attach button's [anchor] rect; null to show the sheet.
  Rect? cardFor(Size size, EdgeInsets padding, {required Rect anchor}) => null;

  /// How dark the scrim gets behind a card.
  double get cardDimOpacity => dimOpacity;

  // --- Motion ---

  /// How the sheet rises from the bottom edge to its resting height.
  AttachSheetMotion get openMotion;

  /// How the sheet falls off the bottom edge when it closes.
  AttachSheetMotion get closeMotion;

  /// The scrim fading in.
  MotionSpec get dimIn;

  /// The wait before the scrim starts to fade in.
  Duration get dimDelay => Duration.zero;

  /// The scrim fading out.
  MotionSpec get dimOut;

  /// The pinned header fading in and out; null when the sheet has no
  /// pinned header.
  MotionSpec? get headerFade;

  /// How the sheet moves when a page asks it to expand.
  AttachSheetMotion get expandMotion;

  /// How a released drag that [release] decided settles.
  AttachSheetMotion settleMotion(AttachSheetRelease release);

  // --- Gestures ---

  /// What a released drag does; null when the sheet is not the one moving
  /// (the page scrolls under a pinned sheet).
  AttachSheetRelease? release(AttachSheetReleaseInput input);

  /// How the sheet returns to its rest from [distance] below it.
  MotionSpec holdMotion(double distance);

  /// How far below the top a sheet left by a fling still snaps to the top;
  /// null for no snap.
  double? get pinSnapZone;

  /// Whether the sheet stops following drags while the keyboard is up.
  bool get panDisabledWithKeyboard;

  /// Whether a tap on the scrim above the sheet dismisses it.
  bool get dismissesOnTapAbove => true;

  /// How far below its rest a drag with a selection goes before it is
  /// cancelled into the discard question; null to ask only on release.
  double? get discardPanThreshold;

  /// Which question the discard guard asks.
  AttachDiscardWording get discardWording;

  // --- Keyboard ---

  /// How long after the sheet closes the keyboard returns, when it was up
  /// at open; null for never.
  Duration? get keyboardReopenDelay;

  /// Whether focusing the caption expands the sheet.
  bool get expandsOnCaptionFocus;
}

// --- Stock families ---

/// The Android family: a sheet that springs up from the bottom, rises with
/// its page's scroll and pins at the top under a header, and is pulled down
/// past 0.8 cm (or flung) to dismiss.
base class AttachSheetPolicy$Android extends AttachSheetPolicy {
  /// The Android family.
  const AttachSheetPolicy$Android();

  /// 0.8 cm in logical pixels (160 per inch).
  static const double dismissDistance = 0.8 / 2.54 * 160;

  /// The downward fling, in physical pixels per second, that dismisses.
  static const double dismissFlingVelocity = 3500;

  /// The resting top: the page's top padding (2/5 of the height below the
  /// status bar in portrait, 1/3.5 in landscape), plus the header line
  /// (56) less 52 plus 48, less the 13 between the sheet's edge and the
  /// first row.
  @override
  double collapsedTop(Size size, EdgeInsets padding) {
    final available = size.height - padding.vertical;
    final share = size.width > size.height
        ? available / 3.5
        : available * 2 / 5;
    return padding.top + share + 56 - 52 + 48 - 13;
  }

  @override
  double expandedTop(EdgeInsets padding) => padding.top;

  @override
  double get cornerRadius => 12;

  @override
  bool get squaresCornersWhenPinned => true;

  /// A 36 x 4 pill 20 below the edge, gone once the header shows.
  @override
  AttachSheetGrabber? get grabber => const AttachSheetGrabber(
    size: Size(36, 4),
    top: 20,
    fadesWithHeader: true,
  );

  /// The bottom sheet's scrim alpha, 51 of 255.
  @override
  double get dimOpacity => 51 / 255;

  @override
  AttachSheetMotion get openMotion => AttachSheetMotion.spring(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 350, ratio: 0.75),
  );

  /// 250 ms on an ease out (0, 0, 0.58, 1).
  @override
  AttachSheetMotion get closeMotion => const AttachSheetMotion.timed(
    MotionSpec(Duration(milliseconds: 250), Cubic(0, 0, 0.58, 1)),
  );

  @override
  MotionSpec get dimIn =>
      const MotionSpec(Duration(milliseconds: 400), OvershootCurve(0.7));

  @override
  Duration get dimDelay => const Duration(milliseconds: 20);

  @override
  MotionSpec get dimOut =>
      const MotionSpec(Duration(milliseconds: 250), Cubic(0, 0, 0.58, 1));

  @override
  MotionSpec? get headerFade =>
      const MotionSpec(Duration(milliseconds: 380), Curves.easeOutQuint);

  /// The page scrolling the first row to the header line.
  @override
  AttachSheetMotion get expandMotion => const AttachSheetMotion.timed(
    MotionSpec(Duration(milliseconds: 250), Cubic(0.25, 0.1, 0.25, 1)),
  );

  @override
  AttachSheetMotion settleMotion(AttachSheetRelease release) =>
      switch (release) {
        AttachSheetRelease.dismiss => closeMotion,
        _ => expandMotion,
      };

  @override
  AttachSheetRelease? release(AttachSheetReleaseInput input) {
    final below = input.top - input.collapsedTop;
    if (below > 0) {
      final fling = dismissFlingVelocity / input.devicePixelRatio;
      return below >= dismissDistance || input.velocity >= fling
          ? AttachSheetRelease.dismiss
          : AttachSheetRelease.holdCollapsed;
    }
    if (input.top > input.expandedTop) return AttachSheetRelease.fling;
    return null;
  }

  /// 250 ms for every 0.8 cm, on the default cubic (0.25, 0.1, 0.25, 1).
  @override
  MotionSpec holdMotion(double distance) => MotionSpec(
    Duration(
      microseconds: (250000 * math.max(0, distance) / dismissDistance).round(),
    ),
    const Cubic(0.25, 0.1, 0.25, 1),
  );

  /// The header line: a sheet left within one header height of the top
  /// scrolls the rest of the way.
  @override
  double? get pinSnapZone => 56;

  @override
  bool get panDisabledWithKeyboard => false;

  @override
  double? get discardPanThreshold => null;

  @override
  AttachDiscardWording get discardWording =>
      AttachDiscardWording.discardSelection;

  @override
  Duration? get keyboardReopenDelay => const Duration(milliseconds: 200);

  @override
  bool get expandsOnCaptionFocus => false;
}

/// The iOS family: a card-like sheet with a grabber, panned between a
/// collapsed inset and the top and released by a velocity table, that
/// becomes a card anchored to the attach button on a wide screen.
base class AttachSheetPolicy$IOS extends AttachSheetPolicy {
  /// The iOS family.
  const AttachSheetPolicy$IOS();

  /// The shortest side from which a screen is wide enough for the card.
  static const double regularWidth = 600;

  static const SpringDescription _settleSpring = SpringDescription(
    mass: 5,
    stiffness: 900,
    damping: 124,
  );

  /// `floor(max(w, h) * 0.2488)`, 0.15 on a screen 320 wide or narrower,
  /// and none in landscape.
  @override
  double collapsedTop(Size size, EdgeInsets padding) {
    if (size.width > size.height) return 0;
    final share = size.width <= 320 ? 0.15 : 0.2488;
    return (math.max(size.width, size.height) * share).floorToDouble();
  }

  @override
  double expandedTop(EdgeInsets padding) => padding.top;

  @override
  double get cornerRadius => 38;

  @override
  double cornerRadiusFor(Size size) =>
      size.width > size.height ? 0 : cornerRadius;

  @override
  bool get squaresCornersWhenPinned => false;

  @override
  AttachSheetGrabber? get grabber => const AttachSheetGrabber(
    size: Size(36, 5),
    top: 5,
    fadesWithHeader: false,
  );

  @override
  double get dimOpacity => 0.25;

  /// 390 x min(670, available), centred on the button's middle and above
  /// it, kept 28 from the sides and 54 above the bottom inset.
  @override
  Rect? cardFor(Size size, EdgeInsets padding, {required Rect anchor}) {
    if (size.shortestSide < regularWidth) return null;
    const width = 390.0;
    final height = math.min(670, size.height - padding.vertical).toDouble();
    final x = math.max(
      28,
      math.min(size.width - width - 28, anchor.center.dx - width / 2 - 2),
    );
    final y = math.max(
      padding.top,
      math.min(size.height - height - padding.bottom - 54, anchor.top - height),
    );
    return Rect.fromLTWH(x.toDouble(), y, width, height);
  }

  @override
  double get cardDimOpacity => 0.1;

  /// A slide from the bottom on a spring of damping 110.
  @override
  AttachSheetMotion get openMotion => const AttachSheetMotion.spring(
    SpringDescription(mass: 5, stiffness: 900, damping: 110),
  );

  @override
  AttachSheetMotion get closeMotion => const AttachSheetMotion.spring(
    SpringDescription(mass: 5, stiffness: 900, damping: 110),
  );

  @override
  MotionSpec get dimIn =>
      const MotionSpec(Duration(milliseconds: 300), Curves.linear);

  @override
  MotionSpec get dimOut =>
      const MotionSpec(Duration(milliseconds: 250), Curves.easeInOut);

  @override
  MotionSpec? get headerFade => null;

  /// A spring of 0.5 s.
  @override
  AttachSheetMotion get expandMotion =>
      const AttachSheetMotion.spring(_settleSpring);

  @override
  AttachSheetMotion settleMotion(AttachSheetRelease release) =>
      switch (release) {
        AttachSheetRelease.dismiss => const AttachSheetMotion.spring(
          SpringDescription(mass: 5, stiffness: 900, damping: 180),
        ),
        AttachSheetRelease.expand ||
        AttachSheetRelease.collapse ||
        AttachSheetRelease.fling => const AttachSheetMotion.spring(
          _settleSpring,
        ),
        AttachSheetRelease.holdExpanded ||
        AttachSheetRelease.holdCollapsed => const AttachSheetMotion.timed(
          MotionSpec(Duration(milliseconds: 300), Curves.easeInOut),
        ),
      };

  /// The release table: from rest, past 60 down (or down at over 300 pt/s)
  /// dismisses and up at over 300 pt/s (or past half the inset) expands;
  /// from the top, down at over 1800 pt/s dismisses and down at over 300
  /// pt/s (or past half the inset) collapses. Anything left more than 60
  /// below the rest dismisses whichever way the drag started.
  @override
  AttachSheetRelease? release(AttachSheetReleaseInput input) {
    final inset = input.collapsedTop - input.expandedTop;
    final v = input.velocity;
    if (input.top - input.collapsedTop > 60) return AttachSheetRelease.dismiss;
    if (input.startedExpanded) {
      if (v > 1800) return AttachSheetRelease.dismiss;
      if (v > 300 || input.top - input.expandedTop > inset / 2) {
        return AttachSheetRelease.collapse;
      }
      return AttachSheetRelease.holdExpanded;
    }
    final below = input.top - input.collapsedTop;
    if (below > 0 && v > 300) return AttachSheetRelease.dismiss;
    if (v < -300 || input.collapsedTop - input.top > inset / 2) {
      return AttachSheetRelease.expand;
    }
    return AttachSheetRelease.holdCollapsed;
  }

  @override
  MotionSpec holdMotion(double distance) =>
      const MotionSpec(Duration(milliseconds: 300), Curves.easeInOut);

  @override
  double? get pinSnapZone => null;

  @override
  bool get panDisabledWithKeyboard => true;

  @override
  double? get discardPanThreshold => 40;

  @override
  AttachDiscardWording get discardWording =>
      AttachDiscardWording.cancelSelection;

  @override
  Duration? get keyboardReopenDelay => null;

  @override
  bool get expandsOnCaptionFocus => true;
}
