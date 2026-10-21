import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('maps the light palette to the Telegram-derived panel colours', () {
      final tokens = PanelTokens.fromPalette(const ChromePalette.light());
      expect(tokens.background, const Color(0xFFF0F2F5));
      expect(tokens.hairline, const Color(0x12000000));
      expect(tokens.tabSelector, const Color(0xFFE2E5E7));
    });

    test('the search pill is the ink at alpha 0x0F', () {
      final tokens = PanelTokens.fromPalette(const ChromePalette.dark());
      expect(tokens.searchFill, const Color(0x0FFFFFFF));
    });

    test('the pinned strip is the ink at alpha 0x0A over the panel body', () {
      expect(
        PanelTokens.fromPalette(const ChromePalette.dark()).stripFill,
        const Color(0x0AFFFFFF),
      );
      expect(
        PanelTokens.fromPalette(const ChromePalette.light()).stripFill,
        const Color(0x0A000000),
      );
    });

    test('a tooltip is muted text on the raised fill, edged by the '
        'separator', () {
      const palette = ChromePalette.light();
      final tokens = PanelTokens.fromPalette(palette);
      expect(tokens.tooltipFill, palette.surfaceRaised);
      expect(tokens.tooltipText, palette.onSurfaceMuted);
      expect(tokens.tooltipBorder, palette.separator);
    });

    test(
      'selected category icon follows iconActive, idle follows iconIdle',
      () {
        final palette = const ChromePalette.light().copyWith(
          iconIdle: const Color(0xFF111111),
          iconActive: const Color(0xFF222222),
        );
        final tokens = PanelTokens.fromPalette(palette);
        expect(tokens.categoryIcon, const Color(0xFF111111));
        expect(tokens.categoryIconSelected, const Color(0xFF222222));
      },
    );
  });

  group('copyWith', () {
    test('overrides one field and keeps the rest', () {
      final base = PanelTokens.fromPalette(const ChromePalette.light());
      final next = base.copyWith(sectionTitle: const Color(0xFF010203));
      expect(next.sectionTitle, const Color(0xFF010203));
      expect(next.background, base.background);
      expect(next.copyWith(sectionTitle: base.sectionTitle), base);
    });
  });

  group('lerp', () {
    final a = PanelTokens.fromPalette(const ChromePalette.light());
    final b = PanelTokens.fromPalette(const ChromePalette.dark());

    test('returns the endpoints at 0 and 1', () {
      expect(PanelTokens.lerp(a, b, 0), a);
      expect(PanelTokens.lerp(a, b, 1), b);
    });

    test('blends every field halfway', () {
      final mid = PanelTokens.lerp(a, b, 0.5);
      expect(mid.background, Color.lerp(a.background, b.background, 0.5));
      expect(mid.searchFill, Color.lerp(a.searchFill, b.searchFill, 0.5));
      expect(mid.stripFill, Color.lerp(a.stripFill, b.stripFill, 0.5));
    });
  });

  test('equality is by value', () {
    final a = PanelTokens.fromPalette(const ChromePalette.light());
    expect(a, PanelTokens.fromPalette(const ChromePalette.light()));
    expect(
      a.hashCode,
      PanelTokens.fromPalette(const ChromePalette.light()).hashCode,
    );
    expect(a, isNot(PanelTokens.fromPalette(const ChromePalette.dark())));
  });
}
