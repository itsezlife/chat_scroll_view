import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('empty-state text and field hints use the muted text role', () {
      final palette = const ChromePalette.light().copyWith(
        onSurfaceMuted: const Color(0xFF445566),
      );
      final tokens = PlaceholderTokens.fromPalette(palette);
      expect(tokens.emptyState, const Color(0xFF445566));
      expect(tokens.fieldHint, const Color(0xFF445566));
    });

    test('the skeleton fill is the ink at alpha 0x0F', () {
      expect(
        PlaceholderTokens.fromPalette(const ChromePalette.light()).skeleton,
        const Color(0x0F000000),
      );
    });
  });

  group('copyWith', () {
    test('overrides one field and keeps the rest', () {
      final base = PlaceholderTokens.fromPalette(const ChromePalette.light());
      final next = base.copyWith(fieldHint: const Color(0xFF010203));
      expect(next.fieldHint, const Color(0xFF010203));
      expect(next.emptyState, base.emptyState);
      expect(next.copyWith(fieldHint: base.fieldHint), base);
    });
  });

  group('lerp', () {
    final a = PlaceholderTokens.fromPalette(const ChromePalette.light());
    final b = PlaceholderTokens.fromPalette(const ChromePalette.dark());

    test('returns the endpoints at 0 and 1', () {
      expect(PlaceholderTokens.lerp(a, b, 0), a);
      expect(PlaceholderTokens.lerp(a, b, 1), b);
    });

    test('blends every field halfway', () {
      final mid = PlaceholderTokens.lerp(a, b, 0.5);
      expect(mid.skeleton, Color.lerp(a.skeleton, b.skeleton, 0.5));
      expect(mid.emptyState, Color.lerp(a.emptyState, b.emptyState, 0.5));
    });
  });

  test('equality is by value', () {
    final a = PlaceholderTokens.fromPalette(const ChromePalette.light());
    expect(a, PlaceholderTokens.fromPalette(const ChromePalette.light()));
    expect(
      a.hashCode,
      PlaceholderTokens.fromPalette(const ChromePalette.light()).hashCode,
    );
    expect(a, isNot(PlaceholderTokens.fromPalette(const ChromePalette.dark())));
  });
}
