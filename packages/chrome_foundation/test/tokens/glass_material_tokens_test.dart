import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('light composer island: translucent surface, white strokes', () {
      final island = GlassMaterialTokens.fromPalette(
        const ChromePalette.light(),
      ).composerIsland;
      expect(island.fill, const Color(0xFFFFFFFF).withValues(alpha: 0.85));
      expect(island.strokeTop, const Color(0xFFFFFFFF));
      expect(island.strokeBottom, const Color(0xFFFFFFFF));
      expect(island.shadow, const Color(0xFF000000).withValues(alpha: 0.125));
    });

    test('dark composer island: faint strokes and no shadow', () {
      final island = GlassMaterialTokens.fromPalette(
        const ChromePalette.dark(),
      ).composerIsland;
      expect(island.fill, const Color(0xFF20242A).withValues(alpha: 0.85));
      expect(island.strokeTop, const Color(0x28FFFFFF));
      expect(island.strokeBottom, const Color(0x14FFFFFF));
      expect(island.shadow.a, 0);
    });

    test('each named material tints its own surface role', () {
      final tokens = GlassMaterialTokens.fromPalette(
        const ChromePalette.light(),
      );
      expect(
        tokens.panelButton.fill.withValues(alpha: 1),
        const Color(0xFFE8EAED),
      );
      expect(
        tokens.topPanel.fill.withValues(alpha: 1),
        const Color(0xFFF0F2F5),
      );
    });
  });

  group('copyWith', () {
    test('replaces one material and keeps the others', () {
      final base = GlassMaterialTokens.fromPalette(const ChromePalette.light());
      const custom = GlassMaterialColors(
        fill: Color(0x80123456),
        strokeTop: Color(0xFFFFFFFF),
        strokeBottom: Color(0xFFFFFFFF),
        shadow: Color(0x00000000),
      );
      final next = base.copyWith(topPanel: custom);
      expect(next.topPanel, custom);
      expect(next.composerIsland, base.composerIsland);
      expect(next.copyWith(topPanel: base.topPanel), base);
    });

    test('a material copyWith replaces one colour', () {
      const material = GlassMaterialColors(
        fill: Color(0x80123456),
        strokeTop: Color(0xFFFFFFFF),
        strokeBottom: Color(0xFFFFFFFF),
        shadow: Color(0x00000000),
      );
      expect(
        material.copyWith(shadow: const Color(0x20000000)).shadow,
        const Color(0x20000000),
      );
      expect(
        material.copyWith(shadow: const Color(0x20000000)).fill,
        material.fill,
      );
    });
  });

  group('lerp', () {
    final a = GlassMaterialTokens.fromPalette(const ChromePalette.light());
    final b = GlassMaterialTokens.fromPalette(const ChromePalette.dark());

    test('returns the endpoints at 0 and 1', () {
      expect(GlassMaterialTokens.lerp(a, b, 0), a);
      expect(GlassMaterialTokens.lerp(a, b, 1), b);
    });

    test('blends the materials halfway', () {
      final mid = GlassMaterialTokens.lerp(a, b, 0.5);
      expect(
        mid.composerIsland.fill,
        Color.lerp(a.composerIsland.fill, b.composerIsland.fill, 0.5),
      );
      expect(
        mid.topPanel.strokeTop,
        Color.lerp(a.topPanel.strokeTop, b.topPanel.strokeTop, 0.5),
      );
    });
  });

  test('equality is by value', () {
    final a = GlassMaterialTokens.fromPalette(const ChromePalette.light());
    expect(a, GlassMaterialTokens.fromPalette(const ChromePalette.light()));
    expect(
      a.hashCode,
      GlassMaterialTokens.fromPalette(const ChromePalette.light()).hashCode,
    );
    expect(
      a,
      isNot(GlassMaterialTokens.fromPalette(const ChromePalette.dark())),
    );
  });
}
