import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test(
      'the card is the palette\'s raised surface, the text its on-surface',
      () {
        for (final palette in [
          const ChromePalette.light(),
          const ChromePalette.dark(),
          const ChromePalette.highContrastLight(),
          const ChromePalette.highContrastDark(),
        ]) {
          final tokens = SelectionMenuTokens.fromPalette(palette);
          expect(tokens.background, palette.surfaceRaised);
          expect(tokens.text, palette.onSurface);
        }
      },
    );

    test('a custom palette\'s roles are followed', () {
      final palette = const ChromePalette.dark().copyWith(
        surfaceRaised: const Color(0xFF112233),
        onSurface: const Color(0xFFEEDDCC),
      );
      final tokens = SelectionMenuTokens.fromPalette(palette);
      expect(tokens.background, const Color(0xFF112233));
      expect(tokens.text, const Color(0xFFEEDDCC));
    });

    test('the divider is the separator at half its own opacity', () {
      // An opaque separator (a palette built from a colour scheme) gives 0.5.
      final opaque = const ChromePalette.light().copyWith(
        separator: const Color(0xFFCAC4D0),
      );
      expect(
        SelectionMenuTokens.fromPalette(opaque).divider,
        const Color(0xFFCAC4D0).withValues(alpha: 0.5),
      );
      // A translucent one (0x12 = 18 of 255) halves again.
      final translucent = SelectionMenuTokens.fromPalette(
        const ChromePalette.light(),
      );
      expect(translucent.divider.a, closeTo(0x12 / 255 / 2, 1 / 255));
    });

    test('the shadow is black at 0.45', () {
      final tokens = SelectionMenuTokens.fromPalette(
        const ChromePalette.light(),
      );
      expect(tokens.shadow, const Color(0xFF000000).withValues(alpha: 0.45));
    });

    test(
      'the page dim is black, 0x18 on a light palette, 0x40 on a dark one',
      () {
        expect(
          SelectionMenuTokens.fromPalette(const ChromePalette.light()).pageDim,
          const Color(0x18000000),
        );
        expect(
          SelectionMenuTokens.fromPalette(const ChromePalette.dark()).pageDim,
          const Color(0x40000000),
        );
      },
    );
  });

  test('the card metrics are an elevation of 3 and a corner radius of 12', () {
    expect(SelectionMenuTokens.elevation, 3);
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

    test('reaches the shadow and the page dim', () {
      final base = SelectionMenuTokens.fromPalette(const ChromePalette.light());
      final next = base.copyWith(
        shadow: const Color(0xFF010203),
        pageDim: const Color(0x20000000),
      );
      expect(next.shadow, const Color(0xFF010203));
      expect(next.pageDim, const Color(0x20000000));
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
      expect(mid.divider, Color.lerp(a.divider, b.divider, 0.5));
      expect(mid.shadow, Color.lerp(a.shadow, b.shadow, 0.5));
      expect(mid.pageDim, Color.lerp(a.pageDim, b.pageDim, 0.5));
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
    expect(a, isNot(a.copyWith(pageDim: const Color(0x30000000))));
    expect(a, isNot(a.copyWith(shadow: const Color(0xFF000000))));
  });
}
