import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('a black scrim and the sheet on the raised surface', () {
      for (final palette in [
        const ChromePalette.light(),
        const ChromePalette.dark(),
      ]) {
        final tokens = AttachTokens.fromPalette(palette);
        expect(tokens.scrim, const Color(0xFF000000));
        expect(tokens.background, palette.surfaceRaised);
        expect(tokens.header, palette.surfaceRaised);
      }
    });

    test('the grabber is the text colour at 7 % light and 20 % dark', () {
      const light = ChromePalette.light();
      const dark = ChromePalette.dark();
      expect(
        AttachTokens.fromPalette(light).grabber,
        light.onSurface.withValues(alpha: 0.07),
      );
      expect(
        AttachTokens.fromPalette(dark).grabber,
        dark.onSurface.withValues(alpha: 0.2),
      );
    });
  });

  test('copyWith replaces only the named fields', () {
    final base = AttachTokens.fromPalette(const ChromePalette.light());
    final next = base.copyWith(background: const Color(0xFF010203));
    expect(next.background, const Color(0xFF010203));
    expect(next.scrim, base.scrim);
    expect(next.grabber, base.grabber);
    expect(next.copyWith(background: base.background), base);
  });

  test('lerp ends at each side', () {
    final a = AttachTokens.fromPalette(const ChromePalette.light());
    final b = AttachTokens.fromPalette(const ChromePalette.dark());
    expect(AttachTokens.lerp(a, b, 0), a);
    expect(AttachTokens.lerp(a, b, 1), b);
  });

  test('the theme carries the group', () {
    const palette = ChromePalette.dark();
    final data = ChromeThemeData.fromPalette(palette);
    expect(data.attach, AttachTokens.fromPalette(palette));
    final custom = data.attach.copyWith(grabber: const Color(0xFF070809));
    expect(data.copyWith(attach: custom).attach, custom);
    expect(data.copyWith(attach: custom), isNot(data));
  });
}
