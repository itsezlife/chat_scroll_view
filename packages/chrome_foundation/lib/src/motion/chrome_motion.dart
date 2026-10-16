import 'package:chrome_foundation/src/motion/motion_spec.dart';
import 'package:chrome_foundation/src/motion/overshoot_curve.dart';
import 'package:flutter/animation.dart';
import 'package:meta/meta.dart';

/// The named things chrome animates. Components ask for a role, never for a
/// duration.
enum MotionRole {
  /// A list item changing size or position.
  listTransition,

  /// The panel opening or closing under the composer.
  panelSlide,

  /// The search field opening, closing or expanding the panel.
  search,

  /// A bar or header sliding in or out of view.
  headerReveal,

  /// A pointer going down on a pressable target.
  press,

  /// A pressable target settling after the pointer leaves.
  release,

  /// A cross-fade or appearance change.
  fade,

  /// A popup presentation appearing.
  popupShow,

  /// A popup presentation disappearing.
  popupHide,

  /// Switching between presentations (keyboard replacement, popup, docked).
  presentationSwitch,

  /// Interpolating between two chrome themes.
  themeSwitch,
}

/// The **motion role** table: one [MotionSpec] per [MotionRole].
///
/// Immutable; override roles with [copyWith] and supply the result to a
/// `ChromeMotionScope`. There is no `lerp`: curves do not interpolate, and
/// nothing blends two motion tables.
///
/// Durations here are the design durations at normal speed; the scope's
/// `ChromeMotionSpeed` scales them. The values are the ones the previous
/// chrome shipped, except `popupShow`, `popupHide` and `headerReveal`, which
/// are chosen defaults not yet checked against the Telegram clients.
@immutable
final class ChromeMotion {
  /// A motion table with every role given.
  const ChromeMotion({
    required this.listTransition,
    required this.panelSlide,
    required this.search,
    required this.headerReveal,
    required this.press,
    required this.release,
    required this.fade,
    required this.popupShow,
    required this.popupHide,
    required this.presentationSwitch,
    required this.themeSwitch,
  });

  /// The shipped defaults.
  const ChromeMotion.standard()
    : listTransition = const MotionSpec(_quarterSecond, androidListCurve),
      panelSlide = const MotionSpec(_quarterSecond, androidListCurve),
      search = const MotionSpec(Duration(milliseconds: 220), androidListCurve),
      headerReveal = const MotionSpec(
        Duration(milliseconds: 380),
        Curves.easeOutQuint,
      ),
      press = const MotionSpec(Duration(milliseconds: 80), Curves.linear),
      release = const MotionSpec(
        Duration(milliseconds: 350),
        OvershootCurve(1.5),
      ),
      fade = const MotionSpec(Duration(milliseconds: 200), Curves.easeOut),
      popupShow = const MotionSpec(
        Duration(milliseconds: 200),
        Curves.easeOutQuint,
      ),
      popupHide = const MotionSpec(Duration(milliseconds: 150), Curves.easeIn),
      presentationSwitch = const MotionSpec(_quarterSecond, androidListCurve),
      themeSwitch = const MotionSpec(_quarterSecond, Curves.linear);

  static const Duration _quarterSecond = Duration(milliseconds: 250);

  /// The cubic Telegram Android uses for list and panel transitions, measured
  /// from its interpolator rather than approximated by a named Flutter curve.
  static const Cubic androidListCurve = Cubic(
    0.19919472913616398,
    0.010644531250000006,
    0.27920937042459737,
    0.91025390625,
  );

  /// [MotionRole.listTransition]: 250 ms on [androidListCurve].
  final MotionSpec listTransition;

  /// [MotionRole.panelSlide].
  final MotionSpec panelSlide;

  /// [MotionRole.search].
  final MotionSpec search;

  /// [MotionRole.headerReveal].
  final MotionSpec headerReveal;

  /// [MotionRole.press].
  final MotionSpec press;

  /// [MotionRole.release]; overshoots.
  final MotionSpec release;

  /// [MotionRole.fade].
  final MotionSpec fade;

  /// [MotionRole.popupShow].
  final MotionSpec popupShow;

  /// [MotionRole.popupHide].
  final MotionSpec popupHide;

  /// [MotionRole.presentationSwitch].
  final MotionSpec presentationSwitch;

  /// [MotionRole.themeSwitch].
  final MotionSpec themeSwitch;

  /// The spec playing [role].
  MotionSpec operator [](MotionRole role) => switch (role) {
    MotionRole.listTransition => listTransition,
    MotionRole.panelSlide => panelSlide,
    MotionRole.search => search,
    MotionRole.headerReveal => headerReveal,
    MotionRole.press => press,
    MotionRole.release => release,
    MotionRole.fade => fade,
    MotionRole.popupShow => popupShow,
    MotionRole.popupHide => popupHide,
    MotionRole.presentationSwitch => presentationSwitch,
    MotionRole.themeSwitch => themeSwitch,
  };

  /// A copy with the named roles replaced.
  ChromeMotion copyWith({
    MotionSpec? listTransition,
    MotionSpec? panelSlide,
    MotionSpec? search,
    MotionSpec? headerReveal,
    MotionSpec? press,
    MotionSpec? release,
    MotionSpec? fade,
    MotionSpec? popupShow,
    MotionSpec? popupHide,
    MotionSpec? presentationSwitch,
    MotionSpec? themeSwitch,
  }) => ChromeMotion(
    listTransition: listTransition ?? this.listTransition,
    panelSlide: panelSlide ?? this.panelSlide,
    search: search ?? this.search,
    headerReveal: headerReveal ?? this.headerReveal,
    press: press ?? this.press,
    release: release ?? this.release,
    fade: fade ?? this.fade,
    popupShow: popupShow ?? this.popupShow,
    popupHide: popupHide ?? this.popupHide,
    presentationSwitch: presentationSwitch ?? this.presentationSwitch,
    themeSwitch: themeSwitch ?? this.themeSwitch,
  );

  @override
  bool operator ==(Object other) =>
      other is ChromeMotion &&
      MotionRole.values.every((role) => other[role] == this[role]);

  @override
  int get hashCode => Object.hashAll(MotionRole.values.map((r) => this[r]));

  @override
  String toString() =>
      'ChromeMotion(${MotionRole.values.map((r) => '${r.name}: ${this[r]}').join(', ')})';
}
