import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromPalette', () {
    test('light composer island: the surface tint, white strokes, a 0x20 '
        'shadow', () {
      final island = GlassMaterialTokens.fromPalette(
        const ChromePalette.light(),
      ).composerIsland;
      expect(island.tint, const Color(0xFFFFFFFF));
      expect(island.strokeTop, const Color(0xFFFFFFFF));
      expect(island.strokeBottom, const Color(0xFFFFFFFF));
      expect(island.shadow, const Color(0x20000000));
    });

    test('dark composer island: faint strokes and no shadow', () {
      final island = GlassMaterialTokens.fromPalette(
        const ChromePalette.dark(),
      ).composerIsland;
      expect(island.tint, const Color(0xFF20242A));
      expect(island.strokeTop, const Color(0x28FFFFFF));
      expect(island.strokeBottom, const Color(0x14FFFFFF));
      expect(island.shadow.a, 0);
    });

    test('a panel button tints the surface and casts a 0x40 shadow in light '
        'only', () {
      final light = GlassMaterialTokens.fromPalette(
        const ChromePalette.light(),
      ).panelButton;
      final dark = GlassMaterialTokens.fromPalette(
        const ChromePalette.dark(),
      ).panelButton;
      expect(light.tint, const Color(0xFFFFFFFF));
      expect(light.shadow, const Color(0x40000000));
      expect(dark.tint, const Color(0xFF20242A));
      expect(dark.shadow.a, 0);
    });

    test('a top panel tints the dim surface with a fainter dark top edge', () {
      final light = GlassMaterialTokens.fromPalette(
        const ChromePalette.light(),
      ).topPanel;
      final dark = GlassMaterialTokens.fromPalette(
        const ChromePalette.dark(),
      ).topPanel;
      expect(light.tint, const Color(0xFFF0F2F5));
      expect(light.shadow, const Color(0x20000000));
      expect(dark.strokeTop, const Color(0x20FFFFFF));
      expect(dark.strokeBottom, const Color(0x14FFFFFF));
      expect(dark.shadow.a, 0);
    });
  });

  group('copyWith', () {
    test('replaces one material and keeps the others', () {
      final base = GlassMaterialTokens.fromPalette(const ChromePalette.light());
      const custom = GlassMaterialColors(
        tint: Color(0x80123456),
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
        tint: Color(0x80123456),
        strokeTop: Color(0xFFFFFFFF),
        strokeBottom: Color(0xFFFFFFFF),
        shadow: Color(0x00000000),
      );
      expect(
        material.copyWith(shadow: const Color(0x20000000)).shadow,
        const Color(0x20000000),
      );
      expect(
        material.copyWith(shadow: const Color(0x20000000)).tint,
        material.tint,
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
        mid.composerIsland.tint,
        Color.lerp(a.composerIsland.tint, b.composerIsland.tint, 0.5),
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
