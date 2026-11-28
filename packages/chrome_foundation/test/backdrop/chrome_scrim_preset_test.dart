/// The scrim presets: each platform's still, tone, dim, fade, dismissal.
///
/// **Seam:** the `ChromeScrimPreset` values, pure Dart. Expected values are
/// the spec's, written as literals.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('android: a 1/15 still blurred by 15 under 10 % black, closing on '
      'lift, with a toned glass source', () {
    const preset = ChromeScrimPreset.android;
    expect(preset.name, 'android');
    expect(preset.still?.downscale, 15);
    expect(preset.still?.blurRadius, 15);
    expect(preset.still?.toneDark, isNull);
    expect(preset.dimDark, const Color(0x1A000000));
    expect(preset.dimLight, const Color(0x1A000000));
    expect(preset.dimOpacity, 1);
    expect(preset.dimFade.duration, const Duration(milliseconds: 300));
    expect(preset.dimFade.curve, AccelerateDecelerateCurve.instance);
    expect(preset.closeOn, ChromeScrimCloseOn.up);
    expect(preset.closesOnEscape, isFalse);
    expect(preset.glassSource, ChromeScrimStill.androidGlassSource);
  });

  test('the android glass source: 1/15, blur max(15, window / 180), '
      'saturation up and brightness down by theme', () {
    const still = ChromeScrimStill.androidGlassSource;
    expect(still.downscale, 15);
    expect(still.radiusFor(const Size(1080, 2400)), 15);
    expect(still.radiusFor(const Size(1440, 3600)), 20);
    expect(still.toneDark?.brightness, -0.2);
    expect(still.toneLight?.brightness, -0.07);
    // Saturation 2 (dark) and 3 (light) as a multiplier; `toneMatrix`'s
    // scale leaves the colour at 0.
    expect(still.toneDark?.saturation, 1);
    expect(still.toneLight?.saturation, 2);
  });

  group('a saturation scale on the tone matrix', () {
    // Each red row of the matrix, worked by hand from the luminance weights
    // 0.3086, 0.6094 and 0.0820 at x = scale.
    test('at 2 (dark), brightness -0.2', () {
      const tone = ChromeScrimTone.saturationScale(2, brightness: -0.2);
      expect(tone.saturation, 1);
      expect(tone.brightness, -0.2);
      final m = tone.matrix;
      expect(m[0], closeTo(1.6914, 1e-9));
      expect(m[1], closeTo(-0.6094, 1e-9));
      expect(m[2], closeTo(-0.0820, 1e-9));
      expect(m[4], closeTo(-51, 1e-9));
      // The rows sum to 1: a grey stays grey, only the brightness moves it.
      expect(m[0] + m[1] + m[2], closeTo(1, 1e-9));
    });

    test('at 3 (light), brightness -0.07', () {
      const tone = ChromeScrimTone.saturationScale(3, brightness: -0.07);
      expect(tone.saturation, 2);
      final m = tone.matrix;
      expect(m[0], closeTo(2.3828, 1e-9));
      expect(m[1], closeTo(-1.2188, 1e-9));
      expect(m[2], closeTo(-0.1640, 1e-9));
      expect(m[4], closeTo(-17.85, 1e-9));
    });

    test('at 1 it leaves the colour', () {
      expect(
        const ChromeScrimTone.saturationScale(1).matrix,
        BackdropSnapshot.identityTone,
      );
    });
  });

  test('ios: a still under a 20 % day / 60 % dark dim over 0.2 s, closing '
      'on contact', () {
    const preset = ChromeScrimPreset.ios;
    expect(preset.still, isNotNull);
    expect(preset.dimLight, const Color(0x33000A26));
    expect(preset.dimDark, const Color(0x99000000));
    expect(preset.dimFade.duration, const Duration(milliseconds: 200));
    expect(preset.closeOn, ChromeScrimCloseOn.down);
  });

  test('ipad: 40 % black, no still, closing on contact', () {
    const preset = ChromeScrimPreset.ipad;
    expect(preset.still, isNull);
    expect(preset.dimLight, const Color(0x66000000));
    expect(preset.dimDark, const Color(0x66000000));
    expect(preset.dimFade.duration, const Duration(milliseconds: 200));
    expect(preset.closeOn, ChromeScrimCloseOn.down);
  });

  test('desktop: 50 % black, no still, 200 ms ease-out-circ, closing on '
      'release and on Escape', () {
    const preset = ChromeScrimPreset.desktop;
    expect(preset.still, isNull);
    expect(preset.dimDark, const Color(0x7F000000));
    expect(preset.dimFade.duration, const Duration(milliseconds: 200));
    expect(preset.dimFade.curve, const EaseOutCirc());
    expect(preset.closeOn, ChromeScrimCloseOn.up);
    expect(preset.closesOnEscape, isTrue);
  });

  test('web popups: 30 % black, no still, 150 ms, closing on release', () {
    const preset = ChromeScrimPreset.web;
    expect(preset.still, isNull);
    expect(preset.dimLight, const Color(0x4D000000));
    expect(preset.dimFade.duration, const Duration(milliseconds: 150));
    expect(preset.dimFade.curve, const Cubic(0.4, 0, 0.2, 1));
    expect(preset.closeOn, ChromeScrimCloseOn.up);
  });

  test('content preview: its own dim at 180 / 255 and tone, the still on a '
      'clock of its own, closing on contact', () {
    const preset = ChromeScrimPreset.contentPreview;
    expect(preset.still?.downscale, 15);
    expect(preset.still?.blurRadius, 15);
    expect(preset.still?.toneDark?.saturation, 0.04);
    expect(preset.still?.toneDark?.brightness, -0.04);
    expect(preset.still?.toneLight?.saturation, 0.25);
    expect(preset.still?.toneLight?.brightness, -0.07);
    expect(preset.dimDark, const Color(0x71000000));
    expect(preset.dimLight, const Color(0x64E6E6E6));
    expect(preset.dimOpacity, 180 / 255);
    expect(preset.dimFade.duration, const Duration(milliseconds: 120));
    expect(preset.dimFade.curve, Curves.linear);
    expect(preset.stillFade.duration, const Duration(milliseconds: 120));
    expect(preset.closeOn, ChromeScrimCloseOn.down);
  });

  test('a preset is a value: a copy with one field changed', () {
    final faster = ChromeScrimPreset.contentPreview.copyWith(
      dimFade: const MotionSpec(Duration(milliseconds: 150), Curves.linear),
    );
    expect(faster.dimFade.duration, const Duration(milliseconds: 150));
    expect(faster.still, ChromeScrimPreset.contentPreview.still);
    expect(faster, isNot(ChromeScrimPreset.contentPreview));
    expect(
      ChromeScrimPreset.contentPreview.copyWith(),
      ChromeScrimPreset.contentPreview,
    );
  });

  test('the dim by brightness', () {
    expect(
      ChromeScrimPreset.ios.dimFor(Brightness.dark),
      const Color(0x99000000),
    );
    expect(
      ChromeScrimPreset.ios.dimFor(Brightness.light),
      const Color(0x33000A26),
    );
  });
}
