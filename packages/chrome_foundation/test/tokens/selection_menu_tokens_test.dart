import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('the light palette gives the reference client\'s default theme', () {
      final tokens = SelectionMenuTokens.fromPalette(
        const ChromePalette.light(),
      );
      expect(tokens.background, const Color(0xFFFFFFFF));
      expect(tokens.text, const Color(0xFF1A1D21));
      expect(tokens.pressHighlight, const Color(0x0F000000));
      expect(tokens.divider, const Color(0xFFD9D9D9));
    });

    test('the high-contrast light palette keeps the light card', () {
      final tokens = SelectionMenuTokens.fromPalette(
        const ChromePalette.highContrastLight(),
      );
      expect(tokens.background, const Color(0xFFFFFFFF));
      expect(tokens.text, const Color(0xFF1A1D21));
    });

    test('a dark palette derives the card from its raised surface', () {
      const palette = ChromePalette.dark();
      final tokens = SelectionMenuTokens.fromPalette(palette);
      expect(tokens.background, palette.surfaceRaised);
      expect(tokens.text, palette.onSurface);
      expect(tokens.pressHighlight, palette.onSurface.withAlpha(0x0F));
      expect(tokens.divider, palette.onSurface.withAlpha(0x26));
    });

    test('a dark palette follows a custom palette\'s roles', () {
      final palette = const ChromePalette.dark().copyWith(
        surfaceRaised: const Color(0xFF112233),
        onSurface: const Color(0xFFEEDDCC),
      );
      final tokens = SelectionMenuTokens.fromPalette(palette);
      expect(tokens.background, const Color(0xFF112233));
      expect(tokens.text, const Color(0xFFEEDDCC));
    });
  });

  test('the card metrics are an elevation of 1 and a corner radius of 12', () {
    expect(SelectionMenuTokens.elevation, 1);
    expect(SelectionMenuTokens.cornerRadius, 12);
  });

  group('copyWith', () {
    test('overrides one field and keeps the rest', () {
      final base = SelectionMenuTokens.fromPalette(const ChromePalette.light());
      final next = base.copyWith(divider: const Color(0xFF123456));
      expect(next.divider, const Color(0xFF123456));
      expect(next.background, base.background);
      expect(next.copyWith(divider: base.divider), base);
    });
  });

  group('lerp', () {
    final a = SelectionMenuTokens.fromPalette(const ChromePalette.light());
    final b = SelectionMenuTokens.fromPalette(const ChromePalette.dark());

    test('returns the endpoints at 0 and 1', () {
      expect(SelectionMenuTokens.lerp(a, b, 0), a);
      expect(SelectionMenuTokens.lerp(a, b, 1), b);
    });

    test('blends every field halfway', () {
      final mid = SelectionMenuTokens.lerp(a, b, 0.5);
      expect(mid.background, Color.lerp(a.background, b.background, 0.5));
      expect(mid.text, Color.lerp(a.text, b.text, 0.5));
      expect(
        mid.pressHighlight,
        Color.lerp(a.pressHighlight, b.pressHighlight, 0.5),
      );
      expect(mid.divider, Color.lerp(a.divider, b.divider, 0.5));
    });
  });

  test('equality is by value', () {
    final a = SelectionMenuTokens.fromPalette(const ChromePalette.light());
    final b = SelectionMenuTokens.fromPalette(const ChromePalette.light());
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(
      a,
      isNot(SelectionMenuTokens.fromPalette(const ChromePalette.dark())),
    );
  });
}
