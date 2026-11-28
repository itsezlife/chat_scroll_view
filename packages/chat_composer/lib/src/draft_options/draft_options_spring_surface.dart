import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/physics.dart';

/// How the draft options content springs out of the strip and back: the
/// motion of `DraftOptionsSpringSurface`.
///
/// On open the content fades in over [contentShowFade] while it moves from
/// the strip's centre and scales up from [startScale] on [spring], cut at
/// [springCut]; the actions scale on the same spring and fade in over
/// [actionsShowFade]. On close both go back toward the strip and down to
/// [startScale] over [close], the content fading out over
/// [contentHideFade]. A change of what the preview shows resizes the
/// content over [change].
///
/// Durations play at the chrome motion speed: under reduce motion
/// (`ChromeMotionSpeed.instant`) every phase lands on its end state.
@immutable
final class DraftOptionsSpringMotion {
  /// A spring motion; every value has the iOS default.
  const DraftOptionsSpringMotion({
    this.spring = AppearMotion$Spring.spring,
    this.springCut = AppearMotion$Spring.show,
    this.startScale = AppearMotion$Spring.startScale,
    this.contentShowFade = ChromeSourceSpringTiming.contentShowFade,
    this.actionsShowFade = const MotionSpec(
      AppearMotion$Spring.showFade,
      AppearMotion$Spring.ease,
    ),
    this.close = const MotionSpec(
      AppearMotion$Spring.hide,
      AppearMotion$Spring.ease,
    ),
    this.contentHideFade = ChromeSourceSpringTiming.contentHideFade,
    this.change = ChromeSourceSpringTiming.change,
  });

  /// The spring the open scales and moves on (damping 104).
  final SpringDescription spring;

  /// How long the open runs: the spring is cut here, at rest or not.
  final Duration springCut;

  /// The scale the content and the actions grow from and shrink back to.
  final double startScale;

  /// The content's fade in on open.
  final MotionSpec contentShowFade;

  /// The actions' fade in on open.
  final MotionSpec actionsShowFade;

  /// The close: scale and position back toward the strip.
  final MotionSpec close;

  /// The content's fade out on close.
  final MotionSpec contentHideFade;

  /// The content's height following a change of the preview.
  final MotionSpec change;

  /// How far the open has grown [elapsed] into it, from 0 to 1: the
  /// spring's position, 1 from [springCut] on.
  double grownAt(Duration elapsed) {
    if (elapsed >= springCut) return 1;
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    return SpringSimulation(spring, 0, 1, 0).x(seconds);
  }

  @override
  bool operator ==(Object other) =>
      other is DraftOptionsSpringMotion &&
      other.spring.mass == spring.mass &&
      other.spring.stiffness == spring.stiffness &&
      other.spring.damping == spring.damping &&
      other.springCut == springCut &&
      other.startScale == startScale &&
      other.contentShowFade == contentShowFade &&
      other.actionsShowFade == actionsShowFade &&
      other.close == close &&
      other.contentHideFade == contentHideFade &&
      other.change == change;

  @override
  int get hashCode => Object.hash(
    spring.mass,
    spring.stiffness,
    spring.damping,
    springCut,
    startScale,
    contentShowFade,
    actionsShowFade,
    close,
    contentHideFade,
    change,
  );
}

/// Where the draft options content and its actions stand: the content's
/// rect and the actions' top-left, in the window.
typedef DraftOptionsSpringFrame = ({Rect content, Offset actions});

/// The iOS presentation of the draft options overlay: the live preview in a
/// rounded content rect that springs out of the strip, the link page's
/// actions as a context list under it, right-aligned to it.
///
/// A pure value carried by `DraftOptionsPolicy$IOS.surface`: [phone] for a
/// compact window, [iPad] for a regular-width one. The layout is two pure
/// steps the skin runs around its children's sizes:
/// [contentHeightBounds] before the content is laid out, [place] after.
@immutable
final class DraftOptionsSpringSurface {
  /// A spring surface; every value has the phone default.
  const DraftOptionsSpringSurface({
    this.cornerRadius = 30,
    this.sideMargin = 12,
    this.verticalMargin = 24,
    this.topInsetExtra = 8,
    this.maxHeight = 460,
    this.previewExtra = 3,
    this.minHeight = 200,
    this.maxWidth,
    this.centredOnStrip = false,
    this.actionsSpacing = 10,
    this.actionsEdgeInset = 12,
    this.actionsMinWidth = 250,
    this.actionsCornerRadius = 14,
    this.motion = const DraftOptionsSpringMotion(),
    this.hapticOnOpen = true,
  });

  /// A compact window: the content as wide as the window less the margins,
  /// centred.
  static const DraftOptionsSpringSurface phone = DraftOptionsSpringSurface();

  /// A regular-width window: the content at most 400 wide, centred on the
  /// strip.
  static const DraftOptionsSpringSurface iPad = DraftOptionsSpringSurface(
    maxWidth: 400,
    centredOnStrip: true,
  );

  /// The content's corner radius; the preview is clipped to it.
  final double cornerRadius;

  /// Between the window's sides and the content (W − 2 × this wide).
  final double sideMargin;

  /// Taken from the window's height, beside the insets, for the content's
  /// tallest (H − this − top inset − bottom safe area).
  final double verticalMargin;

  /// Added to the window's top padding: the top inset.
  final double topInsetExtra;

  /// The content is never taller than this.
  final double maxHeight;

  /// Added to the preview's own height for the content's.
  final double previewExtra;

  /// The content is never shorter than this, even to fit the actions.
  final double minHeight;

  /// The content's widest; null for no bound beyond the margins.
  final double? maxWidth;

  /// Whether the content is centred on the strip across the window, as far
  /// as the margins allow; otherwise centred in the window.
  final bool centredOnStrip;

  /// From the content's bottom to the actions' top.
  final double actionsSpacing;

  /// The actions keep at least this from the window's edges.
  final double actionsEdgeInset;

  /// The actions are at least this wide.
  final double actionsMinWidth;

  /// The actions list's corner radius.
  final double actionsCornerRadius;

  /// How the content and the actions spring in and out.
  final DraftOptionsSpringMotion motion;

  /// Whether opening plays a haptic impact.
  final bool hapticOnOpen;

  /// The top inset of a window with [padding]: the padding's top and
  /// [topInsetExtra].
  double topInset(EdgeInsets padding) => padding.top + topInsetExtra;

  /// The content's width in a [window].
  double contentWidth(Size window) {
    final width = math.max<double>(0, window.width - 2 * sideMargin);
    return switch (maxWidth) {
      final most? => math.min(width, most),
      null => width,
    };
  }

  /// The content's height bounds in a [window] with [padding], under
  /// actions [actionsHeight] tall: the content takes the preview's height
  /// and [previewExtra] within them.
  ///
  /// The top is the lesser of [maxHeight] and the window less
  /// [verticalMargin] and the insets, lowered further so the actions fit
  /// under the content, and never under [minHeight].
  ({double min, double max}) contentHeightBounds(
    Size window,
    EdgeInsets padding, {
    required double actionsHeight,
  }) {
    final top = topInset(padding);
    final fits = math.min(
      maxHeight,
      window.height - verticalMargin - top - padding.bottom,
    );
    final withActions =
        window.height - top - padding.bottom - actionsSpacing - actionsHeight;
    final most = math.max(minHeight, math.min(fits, withActions));
    return (min: minHeight, max: most);
  }

  /// Places [content] and [actions] (their laid-out sizes) in a [window]
  /// with [padding]; [strip] is the strip's rect, the origin of the spring.
  ///
  /// The content and the actions under it stand centred as a group between
  /// the top inset and the bottom safe area, the content across the window
  /// (or on the strip, [centredOnStrip]) within [sideMargin]. The actions
  /// are right-aligned to the content, [actionsSpacing] under it, at least
  /// [actionsEdgeInset] from the window's edges.
  DraftOptionsSpringFrame place(
    Size window,
    EdgeInsets padding, {
    required Size content,
    required Size actions,
    Rect? strip,
  }) {
    final top = topInset(padding);
    final group = content.height + actionsSpacing + actions.height;
    final room = window.height - top - padding.bottom;
    final contentTop = top + math.max(0.0, (room - group) / 2);
    final centreX = switch (strip) {
      final strip? when centredOnStrip => strip.center.dx,
      _ => window.width / 2,
    };
    final contentLeft = _clamp(
      centreX - content.width / 2,
      sideMargin,
      window.width - sideMargin - content.width,
    );
    final contentRect = Rect.fromLTWH(
      contentLeft,
      contentTop,
      content.width,
      content.height,
    );
    final actionsLeft = _clamp(
      contentRect.right - actions.width,
      actionsEdgeInset,
      window.width - actionsEdgeInset - actions.width,
    );
    return (
      content: contentRect,
      actions: Offset(actionsLeft, contentRect.bottom + actionsSpacing),
    );
  }

  // A clamp that keeps [low] when the bounds cross (too narrow a window).
  static double _clamp(double value, double low, double high) =>
      math.max(low, math.min(value, high));

  @override
  bool operator ==(Object other) =>
      other is DraftOptionsSpringSurface &&
      other.cornerRadius == cornerRadius &&
      other.sideMargin == sideMargin &&
      other.verticalMargin == verticalMargin &&
      other.topInsetExtra == topInsetExtra &&
      other.maxHeight == maxHeight &&
      other.previewExtra == previewExtra &&
      other.minHeight == minHeight &&
      other.maxWidth == maxWidth &&
      other.centredOnStrip == centredOnStrip &&
      other.actionsSpacing == actionsSpacing &&
      other.actionsEdgeInset == actionsEdgeInset &&
      other.actionsMinWidth == actionsMinWidth &&
      other.actionsCornerRadius == actionsCornerRadius &&
      other.motion == motion &&
      other.hapticOnOpen == hapticOnOpen;

  @override
  int get hashCode => Object.hash(
    cornerRadius,
    sideMargin,
    verticalMargin,
    topInsetExtra,
    maxHeight,
    previewExtra,
    minHeight,
    maxWidth,
    centredOnStrip,
    actionsSpacing,
    actionsEdgeInset,
    actionsMinWidth,
    actionsCornerRadius,
    motion,
    hapticOnOpen,
  );
}
