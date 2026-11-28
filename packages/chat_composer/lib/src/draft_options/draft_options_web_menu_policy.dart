import 'dart:ui' show Rect, Size, TextDirection;

import 'package:chat_composer/src/draft_options/draft_link_page_policy.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Alignment;

/// Which way the web's draft options menu extends from its anchor at the
/// strip's top end corner.
enum DraftOptionsMenuSide {
  /// Toward the reading direction's end: right of the anchor in
  /// left-to-right text.
  towardEnd,

  /// Toward the reading direction's start: left of the anchor in
  /// left-to-right text.
  towardStart,
}

/// What the web's draft options menu is drawn on.
enum DraftOptionsMenuSurface {
  /// An opaque raised surface, no blur: the touch style.
  solid,

  /// Menu glass over what is behind: the mouse style.
  glass,
}

/// How the web's draft options menu looks for one input class: its
/// surface, its rows, its presses.
@immutable
final class DraftOptionsMenuStyle {
  /// A menu style; every length in logical pixels.
  const DraftOptionsMenuStyle({
    required this.surface,
    required this.rowMetrics,
    required this.verticalPadding,
    required this.cornerRadius,
    required this.ink,
    this.glass = GlassMaterial.menu,
  });

  /// For a finger: a solid surface, 48 rows with 16 text, ripples on the
  /// rows, 8 above and below them.
  static const DraftOptionsMenuStyle touch = DraftOptionsMenuStyle(
    surface: DraftOptionsMenuSurface.solid,
    rowMetrics: DraftLinkRowMetrics(
      height: 48,
      iconSize: 24,
      iconStart: 17,
      labelStart: 59,
      fontSize: 16,
      minWidthBeyondLabel: 77,
    ),
    verticalPadding: 8,
    cornerRadius: 12,
    ink: ChromeInkKind.ripple,
  );

  /// For a mouse: menu glass, compact rows (36 with 14 text), the hover fill
  /// and no ripple, 4 above and below the rows. **UNVERIFIED**: the compact
  /// row's sizes are a choice, not a measurement.
  static const DraftOptionsMenuStyle mouse = DraftOptionsMenuStyle(
    surface: DraftOptionsMenuSurface.glass,
    rowMetrics: DraftLinkRowMetrics(
      height: 36,
      iconSize: 20,
      iconStart: 12,
      labelStart: 44,
      fontSize: 14,
      minWidthBeyondLabel: 56,
    ),
    verticalPadding: 4,
    cornerRadius: 12,
    ink: ChromeInkKind.pointer,
  );

  /// What the menu is drawn on.
  final DraftOptionsMenuSurface surface;

  /// The glass of a [DraftOptionsMenuSurface.glass] surface.
  final GlassMaterial glass;

  /// Each row's size and placement.
  final DraftLinkRowMetrics rowMetrics;

  /// Above the first row and below the last.
  final double verticalPadding;

  /// The surface's corners.
  final double cornerRadius;

  /// How a row answers a press.
  final ChromeInkKind ink;

  @override
  bool operator ==(Object other) =>
      other is DraftOptionsMenuStyle &&
      other.surface == surface &&
      other.glass == glass &&
      other.rowMetrics == rowMetrics &&
      other.verticalPadding == verticalPadding &&
      other.cornerRadius == cornerRadius &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(
    surface,
    glass,
    rowMetrics,
    verticalPadding,
    cornerRadius,
    ink,
  );
}

/// Where the web's draft options menu goes: its [rect] in the overlay, the
/// [side] it took (the other one when the preferred side has no room) and
/// the [origin] corner it grows from and shrinks back to.
typedef DraftOptionsMenuPlacement = ({
  Rect rect,
  DraftOptionsMenuSide side,
  Alignment origin,
});

/// The web's draft options: a menu anchored at the strip, no overlay, no
/// scrim, no live preview. A pure-Dart value carried by
/// `DraftOptionsPolicy$Web.menu`; a host overrides a field with [copyWith].
///
/// - **Open**: with a mouse, by resting on the strip for [hoverDelay]; with
///   touch, by a tap on it. A click opens it at once too.
/// - **Rows**: the link page's, each choice reported at once (the host
///   saves the draft) and the menu closed. No row chooses another link:
///   that is a tap on the link in the text.
/// - **Motion**: [reveal], opacity 0 to 1 and scale [revealScaleFrom] to 1
///   about [DraftOptionsMenuPlacement.origin], both ways.
/// - **Dismiss**: a press outside on a transparent catcher; with a mouse
///   also leaving the strip and the menu for [leaveGrace], and a secondary
///   click.
/// - **Layout from the width class** ([sideFor]), **interaction and style
///   from the input class** ([styleFor]).
@immutable
final class DraftOptionsWebMenuPolicy {
  /// A menu policy with every field given.
  const DraftOptionsWebMenuPolicy({
    required this.hoverDelay,
    required this.leaveGrace,
    required this.reveal,
    required this.revealScaleFrom,
    required this.anchorInset,
    required this.anchorGap,
    required this.edgeMargin,
    required this.compactSide,
    required this.widerSide,
    required this.touch,
    required this.mouse,
    this.openGuard = ChromeTapTiming.repeatGuard,
  });

  /// The web's defaults: hover 200 ms, reveal 0.2 s from 0.8, anchored 8 in
  /// from the strip's top end and 8 above it, toward the end in a compact
  /// window and toward the start in a wider one.
  static const DraftOptionsWebMenuPolicy standard = DraftOptionsWebMenuPolicy(
    hoverDelay: ChromeAnchoredMenuTiming.hoverOpen,
    leaveGrace: ChromeAnchoredMenuTiming.leaveGrace,
    reveal: ChromeAnchoredMenuTiming.reveal,
    revealScaleFrom: 0.8,
    anchorInset: 8,
    anchorGap: 8,
    edgeMargin: 8,
    compactSide: DraftOptionsMenuSide.towardEnd,
    widerSide: DraftOptionsMenuSide.towardStart,
    touch: DraftOptionsMenuStyle.touch,
    mouse: DraftOptionsMenuStyle.mouse,
  );

  /// How long a mouse rests on the strip before the menu opens.
  final Duration hoverDelay;

  /// How long a mouse may be off both the strip and the menu before the
  /// menu closes.
  final Duration leaveGrace;

  /// The open and the close.
  final MotionSpec reveal;

  /// The scale the menu opens from and closes to.
  final double revealScaleFrom;

  /// From the strip's end edge in to the anchor.
  final double anchorInset;

  /// Between the strip's top and the menu's bottom (its top when it opens
  /// below the strip).
  final double anchorGap;

  /// The least room between the menu and the window's edges.
  final double edgeMargin;

  /// The preferred side in a compact window.
  final DraftOptionsMenuSide compactSide;

  /// The preferred side in a medium or expanded window.
  final DraftOptionsMenuSide widerSide;

  /// The style for touch input.
  final DraftOptionsMenuStyle touch;

  /// The style for a mouse.
  final DraftOptionsMenuStyle mouse;

  /// Within this of an accepted open, another open is dropped and a press on
  /// the catcher passes through, so a burst of taps on the strip opens one
  /// menu and does not close it again.
  final Duration openGuard;

  /// The preferred side in a window of [widthClass].
  DraftOptionsMenuSide sideFor(ChromeWidthClass widthClass) =>
      switch (widthClass) {
        ChromeWidthClass.compact => compactSide,
        ChromeWidthClass.medium || ChromeWidthClass.expanded => widerSide,
      };

  /// The style for [inputClass].
  DraftOptionsMenuStyle styleFor(ChromeInputClass inputClass) =>
      switch (inputClass) {
        ChromeInputClass.touch => touch,
        ChromeInputClass.mouse => mouse,
      };

  /// Where a menu of [size] goes for [strip] inside [bounds], preferring
  /// [side].
  ///
  /// The anchor is [anchorInset] in from the strip's end edge. Toward the
  /// end the menu's start edge is at the anchor; toward the start its end
  /// edge is. A side without room within [edgeMargin] of [bounds] gives way
  /// to the other. The menu's bottom is [anchorGap] above the strip, or its
  /// top as far below it when there is no room above. A menu that still
  /// overflows is pushed inside the margin.
  DraftOptionsMenuPlacement place({
    required Rect strip,
    required Size size,
    required Rect bounds,
    required DraftOptionsMenuSide side,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final rtl = textDirection == TextDirection.rtl;
    final anchor = rtl ? strip.left + anchorInset : strip.right - anchorInset;
    final minLeft = bounds.left + edgeMargin;
    final maxRight = bounds.right - edgeMargin;
    // Whether the menu lies right of the anchor for a side.
    bool rightOf(DraftOptionsMenuSide side) =>
        (side == DraftOptionsMenuSide.towardEnd) != rtl;
    double leftFor(DraftOptionsMenuSide side) =>
        rightOf(side) ? anchor : anchor - size.width;
    bool fits(DraftOptionsMenuSide side) {
      final left = leftFor(side);
      return left >= minLeft && left + size.width <= maxRight;
    }

    final other = switch (side) {
      DraftOptionsMenuSide.towardEnd => DraftOptionsMenuSide.towardStart,
      DraftOptionsMenuSide.towardStart => DraftOptionsMenuSide.towardEnd,
    };
    final taken = !fits(side) && fits(other) ? other : side;
    final maxLeft = maxRight - size.width;
    final left = maxLeft < minLeft
        ? minLeft
        : leftFor(taken).clamp(minLeft, maxLeft);
    final aboveTop = strip.top - anchorGap - size.height;
    final above = aboveTop >= bounds.top + edgeMargin;
    final top = above ? aboveTop : strip.bottom + anchorGap;
    final origin = switch ((above, rightOf(taken))) {
      (true, true) => Alignment.bottomLeft,
      (true, false) => Alignment.bottomRight,
      (false, true) => Alignment.topLeft,
      (false, false) => Alignment.topRight,
    };
    return (
      rect: Rect.fromLTWH(left, top, size.width, size.height),
      side: taken,
      origin: origin,
    );
  }

  /// This policy with the fields given replaced.
  DraftOptionsWebMenuPolicy copyWith({
    Duration? hoverDelay,
    Duration? leaveGrace,
    MotionSpec? reveal,
    double? revealScaleFrom,
    double? anchorInset,
    double? anchorGap,
    double? edgeMargin,
    DraftOptionsMenuSide? compactSide,
    DraftOptionsMenuSide? widerSide,
    DraftOptionsMenuStyle? touch,
    DraftOptionsMenuStyle? mouse,
    Duration? openGuard,
  }) => DraftOptionsWebMenuPolicy(
    hoverDelay: hoverDelay ?? this.hoverDelay,
    leaveGrace: leaveGrace ?? this.leaveGrace,
    reveal: reveal ?? this.reveal,
    revealScaleFrom: revealScaleFrom ?? this.revealScaleFrom,
    anchorInset: anchorInset ?? this.anchorInset,
    anchorGap: anchorGap ?? this.anchorGap,
    edgeMargin: edgeMargin ?? this.edgeMargin,
    compactSide: compactSide ?? this.compactSide,
    widerSide: widerSide ?? this.widerSide,
    touch: touch ?? this.touch,
    mouse: mouse ?? this.mouse,
    openGuard: openGuard ?? this.openGuard,
  );

  @override
  bool operator ==(Object other) =>
      other is DraftOptionsWebMenuPolicy &&
      other.hoverDelay == hoverDelay &&
      other.leaveGrace == leaveGrace &&
      other.reveal == reveal &&
      other.revealScaleFrom == revealScaleFrom &&
      other.anchorInset == anchorInset &&
      other.anchorGap == anchorGap &&
      other.edgeMargin == edgeMargin &&
      other.compactSide == compactSide &&
      other.widerSide == widerSide &&
      other.touch == touch &&
      other.mouse == mouse &&
      other.openGuard == openGuard;

  @override
  int get hashCode => Object.hash(
    hoverDelay,
    leaveGrace,
    reveal,
    revealScaleFrom,
    anchorInset,
    anchorGap,
    edgeMargin,
    compactSide,
    widerSide,
    touch,
    mouse,
    openGuard,
  );
}
