import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// How the tab bar of the attach sheet looks and moves on one platform
/// family: plain values the sheet policy carries.
@immutable
final class AttachTabBarStyle {
  /// A tab bar style.
  const AttachTabBarStyle({
    required this.height,
    required this.radius,
    required this.innerPadding,
    required this.sidePadding,
    required this.hideMotion,
    required this.showMotion,
    required this.permissionBadges,
    this.hideDrop = 0,
    this.hideScale = 1,
    this.popIn,
    this.edgeFade = 0,
    this.scrollClearance = 0,
  });

  /// The bar's height.
  final double height;

  /// Its corner radius.
  final double radius;

  /// The space between the bar's edge and its tabs.
  final double innerPadding;

  /// The space between the screen's sides and the bar.
  final double sidePadding;

  /// How the bar leaves while the attach selection is not empty.
  final MotionSpec hideMotion;

  /// How it comes back when the selection empties.
  final MotionSpec showMotion;

  /// How far the bar drops as it leaves.
  final double hideDrop;

  /// The scale it shrinks to as it leaves.
  final double hideScale;

  /// Whether a tab whose page lacks a permission shows a badge, and a tap
  /// on it asks for the permission instead of switching.
  final bool permissionBadges;

  /// How the tabs pop in when the sheet opens; null for no pop-in.
  final AttachTabPopIn? popIn;

  /// The width of the fade at an edge where a tab is clipped; 0 for none.
  final double edgeFade;

  /// How much room a tapped tab is scrolled clear of the bar's edge.
  final double scrollClearance;
}

/// The staggered pop-in of the tabs: each tab starts [step] later than the
/// one after it (counted from [anchorIndex]), grows to [overshoot] over
/// [grow] while fading in, then settles to 1 over [settle].
@immutable
final class AttachTabPopIn {
  /// A pop-in.
  const AttachTabPopIn({
    required this.delay,
    required this.step,
    required this.anchorIndex,
    required this.overshoot,
    required this.grow,
    required this.growCurve,
    required this.fadeCurve,
    required this.settle,
    required this.settleCurve,
  });

  /// The wait before the first tab moves.
  final Duration delay;

  /// The stagger between neighbouring tabs.
  final Duration step;

  /// The tab that starts last; tabs past it start before the first.
  final int anchorIndex;

  /// The scale the grow reaches.
  final double overshoot;

  /// How long the grow takes.
  final Duration grow;

  /// The grow's curve.
  final Curve growCurve;

  /// The fade's curve, over the grow.
  final Curve fadeCurve;

  /// How long the settle back to 1 takes.
  final Duration settle;

  /// The settle's curve.
  final Curve settleCurve;

  /// When tab [index] starts, after [delay]; negative for one that starts
  /// ahead.
  Duration startOf(int index) => step * (anchorIndex - index);

  /// The whole run, from the first start to the last settle.
  Duration get total => step * anchorIndex + grow + settle;

  /// Tab [index]'s scale and opacity [elapsed] after [delay].
  ({double scale, double opacity}) at(int index, Duration elapsed) {
    final t = elapsed - startOf(index);
    if (t <= Duration.zero) return (scale: 0, opacity: 0);
    if (t <= grow) {
      final f = t.inMicroseconds / grow.inMicroseconds;
      return (
        scale: overshoot * growCurve.transform(f),
        opacity: fadeCurve.transform(f),
      );
    }
    final s = t - grow;
    if (s <= settle) {
      final f = s.inMicroseconds / settle.inMicroseconds;
      return (
        scale: overshoot - (overshoot - 1) * settleCurve.transform(f),
        opacity: 1,
      );
    }
    return (scale: 1, opacity: 1);
  }
}

/// How the page area changes when a tab is switched.
@immutable
sealed class AttachTabSwitch {
  const AttachTabSwitch._();

  /// The old page drops [distance] and fades over [out]; then the new page,
  /// starting [distance] low and transparent, rises and fades in on
  /// [inSpring].
  const factory AttachTabSwitch.slide({
    required double distance,
    required MotionSpec out,
    required SpringDescription inSpring,
  }) = AttachTabSwitch$Slide;

  /// The pages cross-fade over [fade] while the new one rises [dip] on
  /// [inSpring].
  const factory AttachTabSwitch.crossFade({
    required MotionSpec fade,
    required double dip,
    required SpringDescription inSpring,
  }) = AttachTabSwitch$CrossFade;
}

/// [AttachTabSwitch.slide].
final class AttachTabSwitch$Slide extends AttachTabSwitch {
  /// A slide.
  const AttachTabSwitch$Slide({
    required this.distance,
    required this.out,
    required this.inSpring,
  }) : super._();

  /// How far the pages travel.
  final double distance;

  /// The old page leaving.
  final MotionSpec out;

  /// The new page arriving.
  final SpringDescription inSpring;
}

/// [AttachTabSwitch.crossFade].
final class AttachTabSwitch$CrossFade extends AttachTabSwitch {
  /// A cross-fade.
  const AttachTabSwitch$CrossFade({
    required this.fade,
    required this.dip,
    required this.inSpring,
  }) : super._();

  /// The fade of both pages.
  final MotionSpec fade;

  /// How far the new page rises.
  final double dip;

  /// The new page's rise.
  final SpringDescription inSpring;
}
