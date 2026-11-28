import 'dart:math' as math;
import 'dart:ui';

import 'package:chrome_foundation/src/backdrop/backdrop_snapshot.dart';
import 'package:chrome_foundation/src/motion/motion_spec.dart';
import 'package:chrome_foundation/src/motion/scrim_motion.dart';
import 'package:meta/meta.dart';

/// When a press outside the surface closes a chrome scrim.
enum ChromeScrimCloseOn {
  /// On contact: the pointer going down closes it, and the press goes no
  /// further.
  down,

  /// On lift: a press that went down on the scrim closes it as it comes up;
  /// a press that is cancelled does not.
  up,
}

/// A tone for a scrim's still, on [BackdropSnapshot.toneMatrix]'s scale: 0
/// leaves the colour as it is.
@immutable
final class ChromeScrimTone {
  /// A tone changing saturation by [saturation] and brightness by
  /// [brightness].
  const ChromeScrimTone({this.saturation = 0, this.brightness = 0});

  /// A tone whose saturation is given as a [scale] of the colour's distance
  /// from grey (1 leaves it, 2 doubles it, 0 is grey), the way a platform
  /// colour matrix's saturation is, and brightness by [brightness].
  ///
  /// [BackdropSnapshot.toneMatrix] writes each channel as `w * (1 - x) + x`
  /// on its own weight and `w * (1 - x)` on the others, with `x = 1 +
  /// saturation`. A platform saturation matrix has the same form with `x =
  /// scale`, so the two agree at `saturation = scale - 1`. What remains
  /// apart are the luminance weights: 0.3086, 0.6094 and 0.0820 here, Rec.
  /// 709's 0.213, 0.715 and 0.072 on a platform matrix. A grey is the same
  /// under both (each row sums to 1); a saturated colour comes out a little
  /// different, by at most `0.106 * |1 - scale|` of full scale per channel
  /// before clamping (0.106 is the green weights' gap, which the red and
  /// blue gaps balance). The values are matched on a device.
  const ChromeScrimTone.saturationScale(double scale, {this.brightness = 0})
    : saturation = scale - 1;

  /// The saturation change: 0 leaves it, positive is more vivid.
  final double saturation;

  /// The brightness change, a fraction of full scale added to each channel.
  final double brightness;

  /// The colour matrix of this tone.
  List<double> get matrix => BackdropSnapshot.toneMatrix(
    saturation: saturation,
    brightness: brightness,
  );

  @override
  bool operator ==(Object other) =>
      other is ChromeScrimTone &&
      other.saturation == saturation &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(saturation, brightness);
}

/// How a scrim's still is made from the window: its downscale, blur and
/// tone (see [BackdropSnapshot.capture]).
@immutable
final class ChromeScrimStill {
  /// A still at 1/[downscale], stack-blurred by [blurRadius] (at least, see
  /// [blurWindowDivisor]) and toned by [toneDark] or [toneLight].
  const ChromeScrimStill({
    this.downscale = 15,
    this.blurRadius = 15,
    this.blurWindowDivisor,
    this.toneDark,
    this.toneLight,
  });

  /// The glass source of the Android overlay: a second still that glass
  /// surfaces on the scrim frost, so they sample the window as it was before
  /// the dim. 1/15, blurred by `max(15, max(w, h) / 180)`, saturation scaled
  /// by 2 (dark) and 3 (light) and brightness lowered (-0.2 dark, -0.07
  /// light); see [ChromeScrimTone.saturationScale] for how the scale maps
  /// onto the tone. The values are to be matched on a device.
  static const ChromeScrimStill androidGlassSource = ChromeScrimStill(
    blurWindowDivisor: 180,
    toneDark: ChromeScrimTone.saturationScale(2, brightness: -0.2),
    toneLight: ChromeScrimTone.saturationScale(3, brightness: -0.07),
  );

  /// How many device pixels of the window make one pixel of the still.
  final double downscale;

  /// The stack blur's radius in the still's pixels; the least one when
  /// [blurWindowDivisor] is set.
  final int blurRadius;

  /// When set, the radius grows with the window: the larger of [blurRadius]
  /// and the window's longer side in device pixels over this.
  final double? blurWindowDivisor;

  /// The tone over a dark theme; null leaves the still's colours.
  final ChromeScrimTone? toneDark;

  /// The tone over a light theme; null leaves the still's colours.
  final ChromeScrimTone? toneLight;

  /// The blur radius for a window of [devicePixels].
  int radiusFor(Size devicePixels) => switch (blurWindowDivisor) {
    final divisor? => math.max(
      blurRadius,
      (devicePixels.longestSide / divisor).round(),
    ),
    null => blurRadius,
  };

  /// The tone for a theme of [brightness].
  ChromeScrimTone? toneFor(Brightness brightness) => switch (brightness) {
    Brightness.dark => toneDark,
    Brightness.light => toneLight,
  };

  @override
  bool operator ==(Object other) =>
      other is ChromeScrimStill &&
      other.downscale == downscale &&
      other.blurRadius == blurRadius &&
      other.blurWindowDivisor == blurWindowDivisor &&
      other.toneDark == toneDark &&
      other.toneLight == toneLight;

  @override
  int get hashCode => Object.hash(
    downscale,
    blurRadius,
    blurWindowDivisor,
    toneDark,
    toneLight,
  );
}

/// What a chrome scrim looks like and how it closes on one platform: its
/// still, its dim, its fades and its dismissal.
///
/// A value: a host picks a preset by platform and may copy it with fields of
/// its own ([copyWith]).
@immutable
final class ChromeScrimPreset {
  /// A preset; see the fields.
  const ChromeScrimPreset({
    required this.name,
    required this.dimDark,
    required this.dimLight,
    required this.dimFade,
    required this.closeOn,
    this.still,
    this.dimOpacity = 1,
    MotionSpec? stillFade,
    this.closesOnEscape = false,
    this.closesOnBack = true,
    this.glassSource,
  }) : _stillFade = stillFade;

  /// The Android overlay: a 1/15 still blurred by 15 under 10 % black,
  /// closing on lift, with [ChromeScrimStill.androidGlassSource] for glass on
  /// the scrim.
  static const ChromeScrimPreset android = ChromeScrimPreset(
    name: 'android',
    still: ChromeScrimStill(),
    dimDark: Color(0x1A000000),
    dimLight: Color(0x1A000000),
    dimFade: ScrimMotion.android,
    closeOn: ChromeScrimCloseOn.up,
    glassSource: ChromeScrimStill.androidGlassSource,
  );

  /// iOS: a still standing in for the live system blur (its radius is
  /// unverified) under a dim of `0x000A26` at 20 % by day and black at 60 %
  /// by night, over 0.2 s, closing on contact and not on back.
  static const ChromeScrimPreset ios = ChromeScrimPreset(
    name: 'ios',
    still: ChromeScrimStill(),
    dimDark: Color(0x99000000),
    dimLight: Color(0x33000A26),
    dimFade: ScrimMotion.ios,
    closeOn: ChromeScrimCloseOn.down,
    closesOnBack: false,
  );

  /// iPad in a regular-width window: 40 % black and no still, over 0.2 s,
  /// closing on contact and not on back.
  static const ChromeScrimPreset ipad = ChromeScrimPreset(
    name: 'ipad',
    dimDark: Color(0x66000000),
    dimLight: Color(0x66000000),
    dimFade: ScrimMotion.ios,
    closeOn: ChromeScrimCloseOn.down,
    closesOnBack: false,
  );

  /// Desktop: 50 % black and no still, over 200 ms ease-out-circ, closing on
  /// release and on Escape.
  static const ChromeScrimPreset desktop = ChromeScrimPreset(
    name: 'desktop',
    dimDark: Color(0x7F000000),
    dimLight: Color(0x7F000000),
    dimFade: ScrimMotion.desktop,
    closeOn: ChromeScrimCloseOn.up,
    closesOnEscape: true,
  );

  /// The web's popups: 30 % black and no still, over 150 ms, closing on
  /// release.
  static const ChromeScrimPreset web = ChromeScrimPreset(
    name: 'web',
    dimDark: Color(0x4D000000),
    dimLight: Color(0x4D000000),
    dimFade: ScrimMotion.web,
    closeOn: ChromeScrimCloseOn.up,
  );

  /// The content preview: a 1/15 still blurred by 15 and toned by theme,
  /// under its own dim drawn at 180 / 255 of its alpha; the dim fades with
  /// the preview's show and the still on a clock of its own, both over
  /// 120 ms linear; closing on contact.
  static const ChromeScrimPreset contentPreview = ChromeScrimPreset(
    name: 'contentPreview',
    still: ChromeScrimStill(
      toneDark: ChromeScrimTone(saturation: 0.04, brightness: -0.04),
      toneLight: ChromeScrimTone(saturation: 0.25, brightness: -0.07),
    ),
    dimDark: Color(0x71000000),
    dimLight: Color(0x64E6E6E6),
    dimOpacity: 180 / 255,
    dimFade: ScrimMotion.contentPreview,
    closeOn: ChromeScrimCloseOn.down,
  );

  /// A stable name for logs: the owner reports it with the scrim's phases.
  final String name;

  /// How the still is made; null for a scrim of dim alone.
  final ChromeScrimStill? still;

  /// The dim over a dark theme.
  final Color dimDark;

  /// The dim over a light theme.
  final Color dimLight;

  /// The share of the dim's own alpha it is drawn at, from 0 to 1.
  final double dimOpacity;

  /// The dim's fade in and out.
  final MotionSpec dimFade;

  /// The still's fade in and out, on its own clock; [dimFade] unless set.
  MotionSpec get stillFade => _stillFade ?? dimFade;
  final MotionSpec? _stillFade;

  /// When a press outside the surface closes the scrim.
  final ChromeScrimCloseOn closeOn;

  /// Whether Escape closes the scrim.
  final bool closesOnEscape;

  /// Whether the system back closes the scrim. Off, the scrim takes no back
  /// at all: it reaches whatever handles it under the scrim.
  final bool closesOnBack;

  /// The second, toned still glass on the scrim samples, or null.
  final ChromeScrimStill? glassSource;

  /// The dim for a theme of [brightness].
  Color dimFor(Brightness brightness) => switch (brightness) {
    Brightness.dark => dimDark,
    Brightness.light => dimLight,
  };

  /// This preset with the given fields replaced.
  ChromeScrimPreset copyWith({
    String? name,
    Color? dimDark,
    Color? dimLight,
    double? dimOpacity,
    MotionSpec? dimFade,
    MotionSpec? stillFade,
    ChromeScrimCloseOn? closeOn,
    bool? closesOnEscape,
    bool? closesOnBack,
  }) => ChromeScrimPreset(
    name: name ?? this.name,
    still: still,
    dimDark: dimDark ?? this.dimDark,
    dimLight: dimLight ?? this.dimLight,
    dimOpacity: dimOpacity ?? this.dimOpacity,
    dimFade: dimFade ?? this.dimFade,
    stillFade: stillFade ?? _stillFade,
    closeOn: closeOn ?? this.closeOn,
    closesOnEscape: closesOnEscape ?? this.closesOnEscape,
    closesOnBack: closesOnBack ?? this.closesOnBack,
    glassSource: glassSource,
  );

  @override
  bool operator ==(Object other) =>
      other is ChromeScrimPreset &&
      other.name == name &&
      other.still == still &&
      other.dimDark == dimDark &&
      other.dimLight == dimLight &&
      other.dimOpacity == dimOpacity &&
      other.dimFade == dimFade &&
      other._stillFade == _stillFade &&
      other.closeOn == closeOn &&
      other.closesOnEscape == closesOnEscape &&
      other.closesOnBack == closesOnBack &&
      other.glassSource == glassSource;

  @override
  int get hashCode => Object.hash(
    name,
    still,
    dimDark,
    dimLight,
    dimOpacity,
    dimFade,
    _stillFade,
    closeOn,
    closesOnEscape,
    closesOnBack,
    glassSource,
  );
}
