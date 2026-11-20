import 'dart:math' as math;

import 'package:attach_sheet/src/policy/attach_panel_style.dart';
import 'package:attach_sheet/src/policy/attach_tab_bar_style.dart';
import 'package:attach_sheet/src/policy/confirm_box_style.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mpx_ui/mpx_ui.dart' show LibraryGridPolicy;
import 'package:viewport_scroll/viewport_scroll.dart' show FastScrollbarPolicy;

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

/// How the sheet grows out of the attach button and back into it: each
/// channel (the position of its middle, its bounds, its corners, its
/// content's opacity) on its own spring or clock, from 0 at the button to 1
/// at the sheet.
@immutable
final class AttachSheetMorph {
  /// A morph.
  const AttachSheetMorph({
    required this.openPosition,
    required this.openPositionVelocity,
    required this.openBounds,
    required this.openCorners,
    required this.openContent,
    required this.closePosition,
    required this.closeBounds,
    required this.closeCorners,
    required this.closeContent,
  });

  /// The middle moving out of the button.
  final SpringDescription openPosition;

  /// The position's starting velocity, in morphs per second.
  final double openPositionVelocity;

  /// The bounds growing.
  final SpringDescription openBounds;

  /// The corners going from the button's to the sheet's.
  final MotionSpec openCorners;

  /// The content fading in.
  final MotionSpec openContent;

  /// The middle moving back into the button.
  final SpringDescription closePosition;

  /// The bounds shrinking.
  final SpringDescription closeBounds;

  /// The corners going back to the button's.
  final SpringDescription closeCorners;

  /// The content fading out.
  final MotionSpec closeContent;
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

  /// The desktop family; see [AttachSheetPolicy$Desktop].
  const factory AttachSheetPolicy.desktop() = AttachSheetPolicy$Desktop;

  /// The web family; see [AttachSheetPolicy$Web].
  const factory AttachSheetPolicy.web() = AttachSheetPolicy$Web;

  /// The family of [platform]: Android and iOS their own, every other system
  /// the desktop family, and a browser ([isWeb] wins) the web family on
  /// every device.
  factory AttachSheetPolicy.forPlatform(
    TargetPlatform platform, {
    required bool isWeb,
  }) {
    if (isWeb) return const AttachSheetPolicy.web();
    return switch (platform) {
      TargetPlatform.android => const AttachSheetPolicy.android(),
      TargetPlatform.iOS => const AttachSheetPolicy.ios(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => const AttachSheetPolicy.desktop(),
    };
  }

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

  /// How the sheet grows out of the attach button and shrinks back into it,
  /// when the host gives the button's rect; null to slide from the bottom
  /// edge instead.
  AttachSheetMorph? get morph => null;

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

  /// How a sheet a pull left low returns to its rest once the discard
  /// question is answered "keep"; null for [holdMotion].
  SpringDescription? get keepSpring => null;

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

  // --- Tabs ---

  /// How the tab bar looks and moves.
  AttachTabBarStyle get tabBar;

  /// The widths of tabs whose labels measure [labelWidths], in a bar that
  /// may be [available] wide.
  List<double> tabWidths(List<double> labelWidths, double available);

  /// How the page area changes on a tab switch.
  AttachTabSwitch get tabSwitch;

  // --- Panel ---

  /// The caption field and send button that take the tab bar's place while
  /// something is selected.
  AttachPanelStyle get panel;

  /// The Gallery page's library grid: columns, cells, checks, swipe select,
  /// camera placement.
  LibraryGridPolicy get libraryGrid => LibraryGridPolicy.$Android;

  /// The Gallery grid's fast scroll thumb and its month label.
  FastScrollbarPolicy get libraryFastScroll => FastScrollbarPolicy.$Android;

  /// The fewest library items that bring the fast scroll thumb; it shows
  /// only while the sheet is at its top too.
  int get libraryFastScrollMinCount => 31;

  // --- Confirm box ---

  /// The confirm box every intake route leads to; null on a family that
  /// picks through the sheet.
  ConfirmBoxStyle? get confirmBox => null;

  /// How a media group's thumbs reorder in the box; null for no reorder.
  ConfirmBoxReorder? get boxReorder => null;
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

  /// None: the sheet's top is the list's, and a fling leaves it wherever
  /// the list stops, the top or the rest included.
  @override
  double? get pinSnapZone => null;

  /// The alert's cancel springs the sheet back: damping ratio 1.5,
  /// stiffness 1500.
  @override
  SpringDescription get keepSpring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1500, ratio: 1.5);

  @override
  bool get panDisabledWithKeyboard => false;

  @override
  double? get discardPanThreshold => null;

  @override
  AttachDiscardWording get discardWording =>
      AttachDiscardWording.discardSelection;

  @override
  Duration? get keyboardReopenDelay => const Duration(milliseconds: 200);

  /// The keyboard the caption raises takes the sheet to its top.
  @override
  bool get expandsOnCaptionFocus => true;

  /// A pill 70 tall with radius 28 and 7 inside, 11 from the sides; the
  /// tabs pop in staggered by 32 ms; the bar drops 36 and fades over
  /// 180 ms while something is selected; a badge on a tab whose page lacks
  /// its permission; 8 of fade at a clipped edge; a tapped tab is scrolled
  /// 70 clear of the edge.
  @override
  AttachTabBarStyle get tabBar => const AttachTabBarStyle(
    height: 70,
    radius: 28,
    innerPadding: 7,
    sidePadding: 11,
    hideMotion: MotionSpec(Duration(milliseconds: 180), Curves.decelerate),
    showMotion: MotionSpec(Duration(milliseconds: 180), Curves.decelerate),
    pinnedHide: MotionSpec(Duration(milliseconds: 380), Curves.easeOutQuint),
    hideDrop: 36,
    permissionBadges: true,
    popIn: AttachTabPopIn(
      delay: Duration(milliseconds: 20),
      step: Duration(milliseconds: 32),
      anchorIndex: 3,
      overshoot: 1.1,
      grow: Duration(milliseconds: 200),
      growCurve: Cubic(0, 0, 0.58, 1),
      fadeCurve: Cubic(0.42, 0, 0.58, 1),
      settle: Duration(milliseconds: 100),
      settleCurve: Cubic(0.42, 0, 1, 1),
    ),
    edgeFade: 8,
    scrollClearance: 70,
  );

  /// Each tab is its label plus 16 a side, narrowing to 8 a side as the
  /// label grows from 40 to 56, at most 84; room left over is shared evenly.
  @override
  List<double> tabWidths(List<double> labelWidths, double available) {
    final widths = [
      for (final w in labelWidths)
        math.min<double>(84, w + 2 * (16 - 8 * ((w - 40) / 16).clamp(0, 1))),
    ];
    final total = widths.fold<double>(0, (a, b) => a + b);
    if (widths.isEmpty || available <= total) return widths;
    final add = ((available - total) / widths.length).floorToDouble();
    return [for (final w in widths) w + add];
  }

  /// The old page drops 78 and fades over 180 ms; the new one springs up
  /// from 78 (damping ratio 0.75, stiffness 500).
  @override
  AttachTabSwitch get tabSwitch => AttachTabSwitch.slide(
    distance: 78,
    out: const MotionSpec(
      Duration(milliseconds: 180),
      Cubic(0.25, 0.1, 0.25, 1),
    ),
    inSpring: SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: 500,
      ratio: 0.75,
    ),
  );

  /// The counter at 100 left, a key tap on a refused send; the caption and a
  /// send button growing from 0.2 come in over 180 ms (decelerate); the count
  /// bounces from 0.9 over 180 ms (overshoot). The send menu: without sound,
  /// schedule, caption above; the header menu: open in an external app, send
  /// as files, without grouping, spoiler, quality, caption above.
  @override
  AttachPanelStyle get panel => const AttachPanelStyle(
    counterRemaining: 100,
    overLimitHaptic: AttachHaptic.keyboardTap,
    reveal: MotionSpec(Duration(milliseconds: 180), Curves.decelerate),
    revealRise: 0,
    sendButtonFromScale: 0.2,
    countBounce: AttachCountBounce(
      up: 0.9,
      down: 0.9,
      back: MotionSpec(Duration(milliseconds: 180), OvershootCurve()),
    ),
    sendMenu: [
      AttachSendMenuItem.silent,
      AttachSendMenuItem.schedule,
      AttachSendMenuItem.captionAbove,
    ],
    overflow: [
      AttachOverflowItem.openExternal,
      AttachOverflowItem.sendAsFiles,
      AttachOverflowItem.withoutGrouping,
      AttachOverflowItem.spoiler,
      AttachOverflowItem.quality,
      AttachOverflowItem.captionAbove,
    ],
    sendButtonSize: 56,
  );
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

  /// Out of the attach button: the position on a spring of damping 110
  /// starting at 1.1, the bounds on a spring of damping 110, the corners over
  /// 0.2 s, the content fading in over 0.2 s; back in: the position on
  /// damping 110, the bounds and corners on damping 124, the content out over
  /// 0.12 s.
  @override
  AttachSheetMorph? get morph => const AttachSheetMorph(
    openPosition: SpringDescription(mass: 5, stiffness: 900, damping: 110),
    openPositionVelocity: 1.1,
    openBounds: SpringDescription(mass: 5, stiffness: 900, damping: 110),
    openCorners: MotionSpec(Duration(milliseconds: 200), Curves.easeInOut),
    openContent: MotionSpec(Duration(milliseconds: 200), Curves.linear),
    closePosition: SpringDescription(mass: 5, stiffness: 900, damping: 110),
    closeBounds: SpringDescription(mass: 5, stiffness: 900, damping: 124),
    closeCorners: SpringDescription(mass: 5, stiffness: 900, damping: 124),
    closeContent: MotionSpec(Duration(milliseconds: 120), Curves.linear),
  );

  /// A slide from the bottom on a spring of damping 110, when there is no
  /// attach button to grow out of.
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

  /// A capsule 62 tall; it fades over 0.1 s and shrinks to 0.85 while
  /// something is selected, and fades back over 0.25 s.
  @override
  AttachTabBarStyle get tabBar => const AttachTabBarStyle(
    height: 62,
    radius: 31,
    innerPadding: 0,
    sidePadding: 22,
    hideMotion: MotionSpec(Duration(milliseconds: 100), Curves.linear),
    showMotion: MotionSpec(Duration(milliseconds: 250), Curves.easeInOut),
    hideScale: 0.85,
    permissionBadges: false,
    lens: AttachTabLens(
      inset: 3,
      radius: 28,
      spring: SpringDescription(mass: 5, stiffness: 900, damping: 88),
    ),
  );

  /// The bar is 160 wide for two tabs, 240 for three, 300 for four, else the
  /// screen less 22 a side; the tabs share it evenly.
  @override
  List<double> tabWidths(List<double> labelWidths, double available) {
    final n = labelWidths.length;
    final bar = switch (n) {
      2 => 160.0,
      3 => 240.0,
      4 => 300.0,
      _ => available,
    };
    final inner = bar - 2 * tabBar.innerPadding;
    return [for (var i = 0; i < n; i++) inner / n];
  }

  /// A 0.23 s cross-fade while the new page rises 10 on a spring of
  /// damping 70.
  @override
  AttachTabSwitch get tabSwitch => const AttachTabSwitch.crossFade(
    fade: MotionSpec(Duration(milliseconds: 230), Curves.easeInOut),
    dip: 10,
    inSpring: SpringDescription(mass: 5, stiffness: 900, damping: 70),
  );

  @override
  LibraryGridPolicy get libraryGrid => LibraryGridPolicy.$IOS;

  /// The thin thumb that shows while the grid scrolls, hidden while most
  /// of the grid is in view.
  @override
  FastScrollbarPolicy get libraryFastScroll => FastScrollbarPolicy.$IOS;

  @override
  int get libraryFastScrollMinCount => 0;

  /// The counter under 5 left, the error haptic on a refused send; the
  /// panel rises 44 and fades in over 0.25 s; the count bumps to 1.2 (up) or
  /// 0.8 (down) over 0.1 s and back over 0.1 s. The send menu: without
  /// sound, schedule, when online, caption above; the header menu: send as
  /// files, in HD, without grouping, caption up or down, spoiler.
  @override
  AttachPanelStyle get panel => const AttachPanelStyle(
    counterRemaining: 4,
    overLimitHaptic: AttachHaptic.error,
    reveal: MotionSpec(Duration(milliseconds: 250), Curves.easeInOut),
    revealRise: 44,
    sendButtonFromScale: 1,
    countBounce: AttachCountBounce(
      up: 1.2,
      down: 0.8,
      out: MotionSpec(Duration(milliseconds: 100), Curves.easeOut),
      back: MotionSpec(Duration(milliseconds: 100), Curves.easeIn),
    ),
    sendMenu: [
      AttachSendMenuItem.silent,
      AttachSendMenuItem.schedule,
      AttachSendMenuItem.whenOnline,
      AttachSendMenuItem.captionAbove,
    ],
    overflow: [
      AttachOverflowItem.sendAsFiles,
      AttachOverflowItem.highQuality,
      AttachOverflowItem.withoutGrouping,
      AttachOverflowItem.captionAbove,
      AttachOverflowItem.spoiler,
    ],
    sendButtonSize: 34,
  );
}

/// The desktop family: no sheet; the file dialog, a drop and a paste all
/// lead to one confirm box 364 wide with 308 previews, its options as
/// checkboxes, thumbs that reorder by drag, a counter only past the limit.
/// Its sheet values are the Android family's (no desktop sheet exists).
base class AttachSheetPolicy$Desktop extends AttachSheetPolicy$Android {
  /// The desktop family.
  const AttachSheetPolicy$Desktop();

  /// The counter only on overflow, no haptic; the send menu: without sound,
  /// schedule, high quality, spoiler, caption above.
  @override
  AttachPanelStyle get panel => const AttachPanelStyle(
    counterRemaining: -1,
    overLimitHaptic: AttachHaptic.none,
    reveal: MotionSpec(Duration(milliseconds: 180), Curves.decelerate),
    revealRise: 0,
    sendButtonFromScale: 1,
    countBounce: AttachCountBounce(
      up: 1,
      down: 1,
      back: MotionSpec(Duration.zero, Curves.linear),
    ),
    sendMenu: [
      AttachSendMenuItem.silent,
      AttachSendMenuItem.schedule,
      AttachSendMenuItem.highQuality,
      AttachSendMenuItem.spoiler,
      AttachSendMenuItem.captionAbove,
    ],
    overflow: [],
    sendButtonSize: 40,
  );

  /// 364 wide, previews 308, blocks 10 apart, at most 1280 tall, a click
  /// outside does nothing, 200 ms in and out; checkboxes; an edit / delete
  /// pill and a right-click menu per thumb; single media at most
  /// min(1.5 w, 245); file rows 64 with 44 thumbs.
  @override
  ConfirmBoxStyle? get confirmBox => const ConfirmBoxStyle(
    width: 364,
    previewWidth: 308,
    blockSpacing: 10,
    maxHeight: 1280,
    radius: 12,
    dimOpacity: 0.4,
    open: MotionSpec(Duration(milliseconds: 200), Curves.easeOut),
    close: MotionSpec(Duration(milliseconds: 200), Curves.easeIn),
    rise: 0,
    dismissesOnOutsideTap: false,
    options: ConfirmBoxOptions.checkboxes,
    itemActions: ConfirmBoxItemActions.pillAndMenu,
    titles: ConfirmBoxTitles.selected,
    reorders: true,
    singleMediaMaxHeight: (widthShare: 1.5, cap: 245),
    fileRowHeight: 64,
    fileThumb: 44,
    dedupesByFacts: false,
    printableKeyFocusesCaption: false,
    analysedAtOnce: 10,
  );

  /// The dragged thumb shrinks 5 a side over 150 ms, neighbours slide over
  /// 150 ms, the drop settles over 200 ms.
  @override
  ConfirmBoxReorder? get boxReorder => const ConfirmBoxReorder(
    shrink: 5,
    lift: MotionSpec(Duration(milliseconds: 150), Curves.easeOut),
    neighbours: MotionSpec(Duration(milliseconds: 150), Curves.easeOut),
    settle: MotionSpec(Duration(milliseconds: 200), Curves.easeOut),
  );
}

/// The web family: no sheet; the file input, a drop and a paste all lead to
/// one popup 420 wide with radius 40 and 384 previews, its options in a More
/// menu, no reorder, no counter (an over-long caption is a toast).
base class AttachSheetPolicy$Web extends AttachSheetPolicy$Android {
  /// The web family.
  const AttachSheetPolicy$Web();

  /// No counter, no haptic; the send menu: without sound, schedule, when
  /// online.
  @override
  AttachPanelStyle get panel => const AttachPanelStyle(
    counterRemaining: null,
    overLimitHaptic: AttachHaptic.none,
    reveal: MotionSpec(Duration(milliseconds: 150), Cubic(0.4, 0, 0.2, 1)),
    revealRise: 0,
    sendButtonFromScale: 1,
    countBounce: AttachCountBounce(
      up: 1,
      down: 1,
      back: MotionSpec(Duration.zero, Curves.linear),
    ),
    sendMenu: [
      AttachSendMenuItem.silent,
      AttachSendMenuItem.schedule,
      AttachSendMenuItem.whenOnline,
    ],
    overflow: [],
    sendButtonSize: 40,
  );

  /// 420 wide, radius 40, previews 384, groups 8 apart, a 30 % overlay that
  /// closes it, a 3rem rise over 0.15 s (0.4, 0, 0.2, 1); a More menu; a
  /// hover pill per item; single media fitted into 384 x 320; document rows
  /// 56 with 48 icons; an item already in the box is not added again.
  @override
  ConfirmBoxStyle? get confirmBox => const ConfirmBoxStyle(
    width: 420,
    previewWidth: 384,
    blockSpacing: 8,
    maxHeight: null,
    radius: 40,
    dimOpacity: 0.3,
    open: MotionSpec(Duration(milliseconds: 150), Cubic(0.4, 0, 0.2, 1)),
    close: MotionSpec(Duration(milliseconds: 150), Cubic(0.4, 0, 0.2, 1)),
    rise: 48,
    dismissesOnOutsideTap: true,
    options: ConfirmBoxOptions.moreMenu,
    itemActions: ConfirmBoxItemActions.hoverPill,
    titles: ConfirmBoxTitles.sendCount,
    reorders: false,
    singleMediaMaxHeight: (widthShare: 320 / 384, cap: 320),
    fileRowHeight: 56,
    fileThumb: 48,
    dedupesByFacts: true,
    printableKeyFocusesCaption: true,
    analysedAtOnce: 10,
  );
}
