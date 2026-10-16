import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('derives every group from the palette', () {
      const palette = ChromePalette.dark();
      final data = ChromeThemeData.fromPalette(palette);
      expect(data.palette, palette);
      expect(data.composer, ComposerTokens.fromPalette(palette));
      expect(data.panel, PanelTokens.fromPalette(palette));
      expect(data.action, ActionTokens.fromPalette(palette));
      expect(data.placeholder, PlaceholderTokens.fromPalette(palette));
      expect(data.glass, GlassMaterialTokens.fromPalette(palette));
    });

    test('an override replaces only its group', () {
      const palette = ChromePalette.light();
      final panel = PanelTokens.fromPalette(
        palette,
      ).copyWith(background: const Color(0xFF123456));
      final data = ChromeThemeData.fromPalette(palette, panel: panel);
      expect(data.panel.background, const Color(0xFF123456));
      expect(data.composer, ComposerTokens.fromPalette(palette));
    });
  });

  group('copyWith', () {
    test('replaces a group and keeps the rest', () {
      final base = ChromeThemeData.fromPalette(const ChromePalette.light());
      final composer = base.composer.copyWith(text: const Color(0xFF010203));
      final next = base.copyWith(composer: composer);
      expect(next.composer, composer);
      expect(next.panel, base.panel);
      expect(next.copyWith(composer: base.composer), base);
    });

    test('replacing the palette does not re-derive the groups', () {
      // Re-deriving would silently discard host overrides.
      final base = ChromeThemeData.fromPalette(const ChromePalette.light());
      final next = base.copyWith(palette: const ChromePalette.dark());
      expect(next.palette, const ChromePalette.dark());
      expect(next.panel, base.panel);
    });
  });

  group('lerp', () {
    final a = ChromeThemeData.fromPalette(const ChromePalette.light());
    final b = ChromeThemeData.fromPalette(const ChromePalette.dark());

    test('returns the endpoints at 0 and 1', () {
      expect(ChromeThemeData.lerp(a, b, 0), a);
      expect(ChromeThemeData.lerp(a, b, 1), b);
    });

    test('blends the palette and each group halfway', () {
      final mid = ChromeThemeData.lerp(a, b, 0.5);
      expect(mid.palette, ChromePalette.lerp(a.palette, b.palette, 0.5));
      expect(mid.composer, ComposerTokens.lerp(a.composer, b.composer, 0.5));
      expect(mid.glass, GlassMaterialTokens.lerp(a.glass, b.glass, 0.5));
    });
  });

  test('equality is by value', () {
    final a = ChromeThemeData.fromPalette(const ChromePalette.light());
    final b = ChromeThemeData.fromPalette(const ChromePalette.light());
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(ChromeThemeData.fromPalette(const ChromePalette.dark())));
  });
}
