/// Glass materials are values: role presets a surface adjusts or replaces,
/// colours by role from the theme or the surface's own, and corners of a
/// surface's own.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = ValueKey('glass');

Widget _host(GlassSurface glass, {ChromePalette? palette}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(),
    child: ChromeThemeScope(
      palette: palette ?? const ChromePalette.light(),
      child: GlassQualityScope(
        quality: GlassQuality.flat,
        child: Center(child: SizedBox(width: 200, height: 60, child: glass)),
      ),
    ),
  ),
);

void main() {
  const presets = {
    GlassColorRole.island: GlassMaterial.island,
    GlassColorRole.button: GlassMaterial.button,
    GlassColorRole.bar: GlassMaterial.bar,
    GlassColorRole.menu: GlassMaterial.menu,
    GlassColorRole.panel: GlassMaterial.panel,
    GlassColorRole.bubble: GlassMaterial.bubble,
  };

  test('every role has its preset, naming its own colours', () {
    expect(presets.keys, GlassColorRole.values);
    for (final MapEntry(key: role, value: material) in presets.entries) {
      expect(material.colorRole, role);
    }
  });

  test('a material is a value: copyWith, equality, lerp', () {
    final rounded = GlassMaterial.panel.copyWith(cornerRadius: 16);
    expect(rounded.cornerRadius, 16);
    expect(rounded.colorRole, GlassColorRole.panel);
    expect(rounded, GlassMaterial.panel.copyWith(cornerRadius: 16));
    expect(
      rounded.hashCode,
      GlassMaterial.panel.copyWith(cornerRadius: 16).hashCode,
    );
    expect(rounded, isNot(GlassMaterial.panel));
    expect(GlassMaterial.panel.copyWith(), GlassMaterial.panel);

    final mid = GlassMaterial.lerp(
      GlassMaterial.island,
      GlassMaterial.menu,
      0.5,
    );
    expect(mid.cornerRadius, (22 + 12) / 2);
    expect(mid.colorRole, GlassColorRole.menu);
    expect(
      GlassMaterial.lerp(GlassMaterial.island, GlassMaterial.menu, 0),
      GlassMaterial.island.copyWith(),
    );
  });

  test('each role resolves its colours in light and dark', () {
    for (final palette in const [ChromePalette.light(), ChromePalette.dark()]) {
      final tokens = GlassMaterialTokens.fromPalette(palette);
      for (final material in presets.values) {
        expect(
          tokens.colorsOf(material),
          tokens.of(material.colorRole),
          reason: '${material.colorRole.name} ${palette.brightness.name}',
        );
      }
      expect(tokens.panel, tokens.island, reason: "the chat's panel look");
      expect(tokens.bubble, tokens.bar);
    }
    final light = GlassMaterialTokens.fromPalette(const ChromePalette.light());
    final dark = GlassMaterialTokens.fromPalette(const ChromePalette.dark());
    expect(light.panel.tint, isNot(dark.panel.tint));
  });

  testWidgets("a surface's own colours and material reach the paint", (
    tester,
  ) async {
    const tint = Color(0xFF00FF00);
    final colors = GlassMaterialTokens.fromPalette(
      const ChromePalette.light(),
    ).panel.copyWith(tint: tint);
    final custom = GlassMaterial.panel.copyWith(cornerRadius: 9);
    await tester.pumpWidget(
      _host(
        GlassSurface(
          key: _key,
          material: custom,
          colors: colors,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final fill = tester.widget<ColoredBox>(
      find.descendant(of: find.byKey(_key), matching: find.byType(ColoredBox)),
    );
    expect(fill.color, tint, reason: 'flat: the opaque tint');
    final clip = tester.widget<ClipRRect>(
      find.descendant(of: find.byKey(_key), matching: find.byType(ClipRRect)),
    );
    expect(clip.borderRadius, BorderRadius.circular(9));
  });

  testWidgets('a panel rounded at the top only clips and casts its shadow '
      'there, the effect keeping its own radius', (tester) async {
    const top = BorderRadius.vertical(top: Radius.circular(16));
    await tester.pumpWidget(
      _host(
        const GlassSurface(
          key: _key,
          material: GlassMaterial.panel,
          borderRadius: top,
          child: SizedBox.expand(),
        ),
      ),
    );
    final clip = tester.widget<ClipRRect>(
      find.descendant(of: find.byKey(_key), matching: find.byType(ClipRRect)),
    );
    expect(clip.borderRadius, top);
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(of: find.byKey(_key), matching: find.byType(DecoratedBox))
          .first,
    );
    expect((box.decoration as BoxDecoration).borderRadius, top);
  });
}
