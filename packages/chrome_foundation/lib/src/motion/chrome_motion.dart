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

  /// A strip above a catalogue sliding back into view, for instance after a
  /// tap on its page's tab.
  stripReveal,

  /// One icon morphing into another, such as a search glyph into a progress
  /// ring or a back arrow.
  iconMorph,

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

  /// A selection marker moving from one control to the next (the highlight
  /// under the active category of a strip).
  selectionSlide,

  /// One turn of an indeterminate loop, such as a progress ring. Under an
  /// instant speed nothing loops: the component shows its resting frame.
  loop,

  /// The selection menu appearing: the fade in.
  menuEnter,

  /// The selection menu leaving after an action, Escape or Back: the fade out
  /// and the short drift away from the selection.
  menuLeave,

  /// The selection menu turning between its row and its More page. Its
  /// duration is for a full turn; a turn that starts part way, or is thrown
  /// closed by a swipe, takes proportionally less (never under half).
  menuPage,

  /// The circular reveal of a spoiler from the tap point.
  spoilerReveal,
}

/// The **motion role** table: one [MotionSpec] per [MotionRole].
///
/// Immutable; override roles with [copyWith] and supply the result to a
/// `ChromeMotionScope`. There is no `lerp`: curves do not interpolate, and
/// nothing blends two motion tables.
///
/// Durations here are the design durations at normal speed; the scope's
/// `ChromeMotionSpeed` scales them. The values are the ones the previous
/// chrome shipped, except `headerReveal`, a chosen default not yet checked
/// against the reference client, and `popupShow` / `popupHide`, whose 200 ms
/// durations are the reference client's (its curves are not measured here).
/// The `menu*` roles are the composer selection menu's three motions, and
/// `spoilerReveal` is the reference client's spoiler ripple.
@immutable
final class ChromeMotion {
  /// A motion table with every role given.
  const ChromeMotion({
    required this.listTransition,
    required this.panelSlide,
    required this.search,
    required this.headerReveal,
    required this.stripReveal,
    required this.iconMorph,
    required this.press,
    required this.release,
    required this.fade,
    required this.popupShow,
    required this.popupHide,
    required this.presentationSwitch,
    required this.themeSwitch,
    required this.selectionSlide,
    required this.loop,
    required this.menuEnter,
    required this.menuLeave,
    required this.menuPage,
    required this.spoilerReveal,
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
      stripReveal = const MotionSpec(
        Duration(milliseconds: 150),
        Curves.easeOutQuint,
      ),
      iconMorph = const MotionSpec(
        Duration(milliseconds: 350),
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
      popupHide = const MotionSpec(Duration(milliseconds: 200), Curves.easeIn),
      presentationSwitch = const MotionSpec(_quarterSecond, androidListCurve),
      themeSwitch = const MotionSpec(_quarterSecond, Curves.linear),
      selectionSlide = const MotionSpec(
        Duration(milliseconds: 400),
        Curves.easeOutCubic,
      ),
      loop = const MotionSpec(Duration(milliseconds: 900), Curves.linear),
      menuEnter = const MotionSpec(
        Duration(milliseconds: 150),
        Curves.easeOut,
      ),
      menuLeave = const MotionSpec(
        Duration(milliseconds: 220),
        Curves.easeIn,
      ),
      menuPage = const MotionSpec(
        Duration(milliseconds: 300),
        Cubic(0.25, 0.1, 0.25, 1),
      ),
      spoilerReveal = const MotionSpec(
        Duration(milliseconds: 300),
        Curves.linear,
      );

  static const Duration _quarterSecond = Duration(milliseconds: 250);

  /// The cubic the reference client uses for list and panel transitions,
  /// measured from its interpolator rather than approximated by a named
  /// Flutter curve.
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

  /// [MotionRole.stripReveal].
  final MotionSpec stripReveal;

  /// [MotionRole.iconMorph].
  final MotionSpec iconMorph;

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

  /// [MotionRole.selectionSlide]: 400 ms ease-out cubic.
  final MotionSpec selectionSlide;

  /// [MotionRole.loop].
  final MotionSpec loop;

  /// [MotionRole.menuEnter]: 150 ms ease out.
  final MotionSpec menuEnter;

  /// [MotionRole.menuLeave]: 220 ms ease in.
  final MotionSpec menuLeave;

  /// [MotionRole.menuPage]: 300 ms on the CSS ease cubic.
  final MotionSpec menuPage;

  /// [MotionRole.spoilerReveal].
  final MotionSpec spoilerReveal;

  /// The spec playing [role].
  MotionSpec operator [](MotionRole role) => switch (role) {
    MotionRole.listTransition => listTransition,
    MotionRole.panelSlide => panelSlide,
    MotionRole.search => search,
    MotionRole.headerReveal => headerReveal,
    MotionRole.stripReveal => stripReveal,
    MotionRole.iconMorph => iconMorph,
    MotionRole.press => press,
    MotionRole.release => release,
    MotionRole.fade => fade,
    MotionRole.popupShow => popupShow,
    MotionRole.popupHide => popupHide,
    MotionRole.presentationSwitch => presentationSwitch,
    MotionRole.themeSwitch => themeSwitch,
    MotionRole.selectionSlide => selectionSlide,
    MotionRole.loop => loop,
    MotionRole.menuEnter => menuEnter,
    MotionRole.menuLeave => menuLeave,
    MotionRole.menuPage => menuPage,
    MotionRole.spoilerReveal => spoilerReveal,
  };

  /// A copy with the named roles replaced.
  ChromeMotion copyWith({
    MotionSpec? listTransition,
    MotionSpec? panelSlide,
    MotionSpec? search,
    MotionSpec? headerReveal,
    MotionSpec? stripReveal,
    MotionSpec? iconMorph,
    MotionSpec? press,
    MotionSpec? release,
    MotionSpec? fade,
    MotionSpec? popupShow,
    MotionSpec? popupHide,
    MotionSpec? presentationSwitch,
    MotionSpec? themeSwitch,
    MotionSpec? selectionSlide,
    MotionSpec? loop,
    MotionSpec? menuEnter,
    MotionSpec? menuLeave,
    MotionSpec? menuPage,
    MotionSpec? spoilerReveal,
  }) => ChromeMotion(
    listTransition: listTransition ?? this.listTransition,
    panelSlide: panelSlide ?? this.panelSlide,
    search: search ?? this.search,
    headerReveal: headerReveal ?? this.headerReveal,
    stripReveal: stripReveal ?? this.stripReveal,
    iconMorph: iconMorph ?? this.iconMorph,
    press: press ?? this.press,
    release: release ?? this.release,
    fade: fade ?? this.fade,
    popupShow: popupShow ?? this.popupShow,
    popupHide: popupHide ?? this.popupHide,
    presentationSwitch: presentationSwitch ?? this.presentationSwitch,
    themeSwitch: themeSwitch ?? this.themeSwitch,
    selectionSlide: selectionSlide ?? this.selectionSlide,
    loop: loop ?? this.loop,
    menuEnter: menuEnter ?? this.menuEnter,
    menuLeave: menuLeave ?? this.menuLeave,
    menuPage: menuPage ?? this.menuPage,
    spoilerReveal: spoilerReveal ?? this.spoilerReveal,
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
