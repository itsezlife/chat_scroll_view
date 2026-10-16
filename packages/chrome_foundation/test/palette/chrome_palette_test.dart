import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('presets', () {
    test('light and dark report their brightness', () {
      expect(const ChromePalette.light().brightness, Brightness.light);
      expect(const ChromePalette.dark().brightness, Brightness.dark);
      expect(
        const ChromePalette.highContrastLight().brightness,
        Brightness.light,
      );
      expect(
        const ChromePalette.highContrastDark().brightness,
        Brightness.dark,
      );
    });

    test('forBrightness picks the matching preset', () {
      expect(
        ChromePalette.forBrightness(Brightness.dark),
        const ChromePalette.dark(),
      );
      expect(
        ChromePalette.forBrightness(Brightness.light),
        const ChromePalette.light(),
      );
      expect(
        ChromePalette.forBrightness(Brightness.dark, highContrast: true),
        const ChromePalette.highContrastDark(),
      );
    });

    test('light and dark differ in every surface role', () {
      const light = ChromePalette.light();
      const dark = ChromePalette.dark();
      expect(light.surface, isNot(dark.surface));
      expect(light.onSurface, isNot(dark.onSurface));
      expect(light.accent, isNot(dark.accent));
    });

    test('the content fade is not the panel surface', () {
      // The fade stands in for wallpaper behind the panel; if it matched the
      // panel the sheet's top edge would vanish.
      for (final palette in [
        const ChromePalette.light(),
        const ChromePalette.dark(),
        const ChromePalette.highContrastLight(),
        const ChromePalette.highContrastDark(),
      ]) {
        expect(palette.contentFade, isNot(palette.surfaceDim));
      }
    });
  });

  group('custom', () {
    test('the primary constructor takes every role', () {
      final palette = _custom();
      expect(palette.accent, const Color(0xFF00FF00));
      expect(palette.brightness, Brightness.dark);
    });
  });

  group('copyWith', () {
    test('replaces only the named roles', () {
      const base = ChromePalette.light();
      final next = base.copyWith(accent: const Color(0xFFFF0000));
      expect(next.accent, const Color(0xFFFF0000));
      expect(next.copyWith(accent: base.accent), base);
    });

    test('with no arguments is equal but not necessarily identical', () {
      const base = ChromePalette.dark();
      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
    });
  });

  group('equality', () {
    test('compares by value', () {
      expect(const ChromePalette.light(), const ChromePalette.light());
      expect(const ChromePalette.light(), isNot(const ChromePalette.dark()));
      expect(
        const ChromePalette.light().hashCode,
        const ChromePalette.light().hashCode,
      );
    });
  });

  group('lerp', () {
    test('returns the endpoints at 0 and 1', () {
      const a = ChromePalette.light();
      const b = ChromePalette.dark();
      expect(ChromePalette.lerp(a, b, 0), a);
      expect(ChromePalette.lerp(a, b, 1), b);
    });

    test('blends colours halfway', () {
      final a = _custom(accent: const Color(0xFF000000));
      final b = _custom(accent: const Color(0xFFFFFFFF));
      final mid = ChromePalette.lerp(a, b, 0.5);
      expect(mid.accent, Color.lerp(a.accent, b.accent, 0.5));
    });

    test('switches brightness at the midpoint', () {
      const a = ChromePalette.light();
      const b = ChromePalette.dark();
      expect(ChromePalette.lerp(a, b, 0.49).brightness, Brightness.light);
      expect(ChromePalette.lerp(a, b, 0.5).brightness, Brightness.dark);
    });
  });

  group('fromColorScheme', () {
    test('maps scheme roles and brightness', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF3366CC),
        brightness: Brightness.dark,
      );
      final palette = ChromePalette.fromColorScheme(scheme);
      expect(palette.brightness, Brightness.dark);
      expect(palette.accent, scheme.primary);
      expect(palette.onAccent, scheme.onPrimary);
      expect(palette.onSurface, scheme.onSurface);
      expect(palette.surface, scheme.surface);
      expect(palette.destructive, scheme.error);
    });
  });
}

ChromePalette _custom({Color accent = const Color(0xFF00FF00)}) =>
    ChromePalette(
      brightness: Brightness.dark,
      surface: const Color(0xFF010101),
      surfaceDim: const Color(0xFF020202),
      surfaceRaised: const Color(0xFF030303),
      surfaceSelected: const Color(0xFF040404),
      surfaceTint: const Color(0x10FFFFFF),
      onSurface: const Color(0xFFFFFFFF),
      onSurfaceMuted: const Color(0xFFCCCCCC),
      iconIdle: const Color(0xFF999999),
      iconActive: const Color(0xFFFFFFFF),
      accent: accent,
      onAccent: const Color(0xFF000000),
      separator: const Color(0x20FFFFFF),
      destructive: const Color(0xFFFF0000),
      contentFade: const Color(0xFF000000),
      shadow: const Color(0xFF000000),
    );
