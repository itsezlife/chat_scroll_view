import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How the tab bar of the attach sheet looks and moves on one platform
/// family: plain values the sheet policy carries.
///
/// A host restyles the bar without forking it: a policy subclass returns
/// `super.tabBar.copyWith(...)` (its glass, colours, tab layout, motion).
/// Colours otherwise come from the chrome theme's `AttachTokens`.
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
    this.bottomPadding = 8,
    this.hideDrop = 0,
    this.pinnedDrop,
    this.hideScale = 1,
    this.popIn,
    this.edgeFade = 0,
    this.scrollClearance = 0,
    this.lens,
    this.pinnedHide,
    this.glass = GlassMaterial.island,
    this.glassColors,
    this.colors = AttachTabColors.fromTokens,
    this.tab = const AttachTabStyle(),
  });

  /// The height of the bar's glass.
  final double height;

  /// Its corner radius.
  final double radius;

  /// The space between the glass's edge and the tabs.
  final double innerPadding;

  /// The space between the screen's sides and the glass.
  final double sidePadding;

  /// The space between the glass and the bottom safe inset.
  final double bottomPadding;

  /// How the bar leaves while the attach selection is not empty.
  final MotionSpec hideMotion;

  /// How it comes back when the selection empties.
  final MotionSpec showMotion;

  /// How the bar leaves while the sheet is at its top, and comes back as it
  /// leaves the top; null for a bar that stays at the top.
  final MotionSpec? pinnedHide;

  /// How far the bar drops as it leaves for the selection.
  final double hideDrop;

  /// How far it drops as it leaves for the sheet's top; null for
  /// [hideDrop].
  final double? pinnedDrop;

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

  /// The glass lens under the shown tab, which slides between tabs and
  /// follows a drag across them; null to mark the shown tab with
  /// [AttachTabStyle.indicator].
  final AttachTabLens? lens;

  /// The bar's glass; its corner radius is [radius].
  final GlassMaterial glass;

  /// The glass's colours of the bar's own; null for the theme's for
  /// [glass]'s role.
  final GlassMaterialColors? glassColors;

  /// The tabs' colours, from the palette and the attach tokens.
  final AttachTabColorsOf colors;

  /// How one tab is laid out and marked.
  final AttachTabStyle tab;

  /// A copy with the given fields replaced.
  AttachTabBarStyle copyWith({
    double? height,
    double? radius,
    double? innerPadding,
    double? sidePadding,
    double? bottomPadding,
    MotionSpec? hideMotion,
    MotionSpec? showMotion,
    MotionSpec? pinnedHide,
    double? hideDrop,
    double? pinnedDrop,
    double? hideScale,
    bool? permissionBadges,
    AttachTabPopIn? popIn,
    double? edgeFade,
    double? scrollClearance,
    AttachTabLens? lens,
    GlassMaterial? glass,
    GlassMaterialColors? glassColors,
    AttachTabColorsOf? colors,
    AttachTabStyle? tab,
  }) => AttachTabBarStyle(
    height: height ?? this.height,
    radius: radius ?? this.radius,
    innerPadding: innerPadding ?? this.innerPadding,
    sidePadding: sidePadding ?? this.sidePadding,
    bottomPadding: bottomPadding ?? this.bottomPadding,
    hideMotion: hideMotion ?? this.hideMotion,
    showMotion: showMotion ?? this.showMotion,
    pinnedHide: pinnedHide ?? this.pinnedHide,
    hideDrop: hideDrop ?? this.hideDrop,
    pinnedDrop: pinnedDrop ?? this.pinnedDrop,
    hideScale: hideScale ?? this.hideScale,
    permissionBadges: permissionBadges ?? this.permissionBadges,
    popIn: popIn ?? this.popIn,
    edgeFade: edgeFade ?? this.edgeFade,
    scrollClearance: scrollClearance ?? this.scrollClearance,
    lens: lens ?? this.lens,
    glass: glass ?? this.glass,
    glassColors: glassColors ?? this.glassColors,
    colors: colors ?? this.colors,
    tab: tab ?? this.tab,
  );
}

/// The tabs' colours of a palette and its attach tokens.
typedef AttachTabColorsOf =
    AttachTabColors Function(ChromePalette palette, AttachTokens tokens);

/// The colours of the tab bar's tabs.
@immutable
final class AttachTabColors {
  /// Colours with every one given.
  const AttachTabColors({
    required this.selected,
    required this.selectedLabel,
    required this.unselected,
    required this.indicator,
    required this.pressed,
  });

  /// The theme's: the tab colours of [tokens].
  // A tear-off of the [AttachTabColorsOf] shape, the style's default.
  // ignore: prefer_constructors_over_static_methods
  static AttachTabColors fromTokens(
    ChromePalette palette,
    AttachTokens tokens,
  ) => AttachTabColors(
    selected: tokens.tabSelected,
    selectedLabel: tokens.tabSelectedLabel,
    unselected: tokens.tabUnselected,
    indicator: tokens.tabIndicator,
    pressed: tokens.tabPressed,
  );

  /// The shown tab's icon.
  final Color selected;

  /// The shown tab's label.
  final Color selectedLabel;

  /// The icon and label of a tab not shown.
  final Color unselected;

  /// The mark behind the shown tab at its full strength.
  final Color indicator;

  /// The wash over a tab held down.
  final Color pressed;
}

/// How one tab of the bar is laid out and marked: its icon and label in a
/// tab as tall as the bar's glass less its inner padding.
@immutable
final class AttachTabStyle {
  /// A tab style; the defaults are the Android family's.
  const AttachTabStyle({
    this.iconSize = 24,
    this.iconTop = 4,
    this.labelTop = 28.33,
    this.labelSize = 11,
    this.measuredLabelSize = 12,
    this.labelWeight = FontWeight.w500,
    this.selectedLabelWeight = FontWeight.w800,
    this.labelPadding = 8,
    this.selectMotion = const MotionSpec(
      Duration(milliseconds: 320),
      Curves.decelerate,
    ),
    this.indicator = const AttachTabIndicator(),
    this.pressFade = const Duration(milliseconds: 150),
  });

  /// The icon's size.
  final double iconSize;

  /// The icon's top, from the tab's.
  final double iconTop;

  /// The label's top, from the tab's.
  final double labelTop;

  /// The label's text size.
  final double labelSize;

  /// The text size a label is measured at for its tab's width.
  final double measuredLabelSize;

  /// The label's weight on a tab not shown, and the one it is measured at.
  final FontWeight labelWeight;

  /// The label's weight on the shown tab.
  final FontWeight selectedLabelWeight;

  /// The label's space from the tab's sides.
  final double labelPadding;

  /// How a tab turns shown or not: its colours and its mark, from one
  /// factor.
  final MotionSpec selectMotion;

  /// The mark behind the shown tab; null for none.
  final AttachTabIndicator? indicator;

  /// How long the wash over a tab held down takes to clear once it lifts;
  /// null for no wash.
  final Duration? pressFade;

  /// A copy with the given fields replaced.
  AttachTabStyle copyWith({
    double? iconSize,
    double? iconTop,
    double? labelTop,
    double? labelSize,
    double? measuredLabelSize,
    FontWeight? labelWeight,
    FontWeight? selectedLabelWeight,
    double? labelPadding,
    MotionSpec? selectMotion,
    AttachTabIndicator? indicator,
    Duration? pressFade,
  }) => AttachTabStyle(
    iconSize: iconSize ?? this.iconSize,
    iconTop: iconTop ?? this.iconTop,
    labelTop: labelTop ?? this.labelTop,
    labelSize: labelSize ?? this.labelSize,
    measuredLabelSize: measuredLabelSize ?? this.measuredLabelSize,
    labelWeight: labelWeight ?? this.labelWeight,
    selectedLabelWeight: selectedLabelWeight ?? this.selectedLabelWeight,
    labelPadding: labelPadding ?? this.labelPadding,
    selectMotion: selectMotion ?? this.selectMotion,
    indicator: indicator ?? this.indicator,
    pressFade: pressFade ?? this.pressFade,
  );
}

/// The mark behind the shown tab: a stadium filling the tab in
/// [AttachTabColors.indicator], growing from [fromScale] as it fades in.
///
/// With the select factor `f`, it is drawn at scale `fromScale + (1 -
/// fromScale) * f` and at `decelerate(f)` of its colour's strength.
@immutable
final class AttachTabIndicator {
  /// A mark growing from [fromScale].
  const AttachTabIndicator({this.fromScale = 0.6});

  /// The scale it grows from.
  final double fromScale;
}

/// The glass lens that marks the shown tab.
@immutable
final class AttachTabLens {
  /// A lens [inset] inside its tab, of corner [radius], sliding on [spring].
  const AttachTabLens({
    required this.inset,
    required this.radius,
    required this.spring,
  });

  /// The space between the lens and its tab's edges.
  final double inset;

  /// The lens's corner radius.
  final double radius;

  /// The spring it slides to a new tab on.
  final SpringDescription spring;
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
