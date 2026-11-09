import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('is the high-contrast card on the high-contrast presets', () {
      for (final palette in [
        const ChromePalette.highContrastLight(),
        const ChromePalette.highContrastDark(),
      ]) {
        expect(
          BulletinTokens.fromPalette(palette),
          BulletinTokens.highContrast,
        );
      }
    });

    test('is the reference dark card on the other palettes', () {
      for (final palette in [
        const ChromePalette.light(),
        const ChromePalette.dark(),
      ]) {
        expect(
          BulletinTokens.fromPalette(palette),
          BulletinTokens.referenceAndroid,
        );
      }
    });

    test('the reference values are the Android undo colours', () {
      const tokens = BulletinTokens.referenceAndroid;
      expect(tokens.background, const Color(0xEA272F38));
      expect(tokens.foreground, const Color(0xFFFFFFFF));
      expect(tokens.accent, const Color(0xFF85CAFF));
      expect(tokens.countdown, const Color(0xFFFFFFFF));
    });
  });

  test('copyWith replaces only the named fields', () {
    const base = BulletinTokens.referenceAndroid;
    final next = base.copyWith(accent: const Color(0xFF00FF00));
    expect(next.accent, const Color(0xFF00FF00));
    expect(next.background, base.background);
    expect(next.foreground, base.foreground);
    expect(next.countdown, base.countdown);
  });

  test('lerp blends every field and returns the endpoints', () {
    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);
    const a = BulletinTokens(
      background: black,
      foreground: black,
      accent: black,
      countdown: black,
    );
    const b = BulletinTokens(
      background: white,
      foreground: white,
      accent: white,
      countdown: white,
    );
    final mid = BulletinTokens.lerp(a, b, 0.5);
    final grey = Color.lerp(black, white, 0.5);
    expect(mid.background, grey);
    expect(mid.foreground, grey);
    expect(mid.accent, grey);
    expect(mid.countdown, grey);
    expect(BulletinTokens.lerp(a, b, 0), a);
    expect(BulletinTokens.lerp(a, b, 1), b);
  });

  test('equality is by value', () {
    expect(
      BulletinTokens.fromPalette(const ChromePalette.light()).hashCode,
      BulletinTokens.referenceAndroid.hashCode,
    );
    expect(
      BulletinTokens.referenceAndroid,
      isNot(
        BulletinTokens.referenceAndroid.copyWith(
          background: const Color(0xFF123456),
        ),
      ),
    );
  });
}
