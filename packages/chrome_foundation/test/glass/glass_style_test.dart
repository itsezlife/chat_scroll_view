/// The look of each glass material per finish: tint opacity, blur, sampling
/// resolution, saturation, edges, shadow and corners.
///
/// **Seam:** `GlassStyle.resolve`, the one place a surface's theme colours
/// and its material become paint parameters. Expected values are the
/// frosted and liquid glass presets.
library;

import 'dart:ui';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/src/glass/glass_style.dart';
import 'package:flutter_test/flutter_test.dart';

GlassStyle _resolve(
  GlassMaterial material,
  GlassFinish finish, {
  ChromePalette palette = const ChromePalette.dark(),
}) => GlassStyle.resolve(
  material: material,
  colors: GlassMaterialTokens.fromPalette(palette).colorsOf(material),
  cornerRadius: material.cornerRadius,
  finish: finish,
);

void main() {
  group('frosted', () {
    final style = _resolve(GlassMaterial.composerIsland, GlassFinish.frosted);

    test('tints at 0.76 over a 40 dp blur sampled at an eighth, saturation '
        'x3', () {
      expect(style.fill, const Color(0xFF20242A).withValues(alpha: 0.76));
      expect(style.blurRadius, 40);
      expect(style.sourceDownscale, 8);
      expect(style.backdropSaturation, 3);
      expect(style.enableLiquid, isFalse);
    });

    test('the 40 dp radius is a Gaussian sigma of 0.57735 r + 0.5 device px, '
        'an eighth of it in the capture', () {
      // 40 dp at 2.75: sigma 64.01 device px, 23.28 logical, 8.00 captured.
      expect(style.blurSigma(devicePixelRatio: 2.75), closeTo(23.276, 1e-3));
      expect(
        style.captureBlurSigma(devicePixelRatio: 2.75),
        closeTo(8.001, 1e-3),
      );
    });
  });

  group('refracting', () {
    test('the island tints at 0.85 over a 6 dp blur sampled at a quarter', () {
      final style = _resolve(
        GlassMaterial.composerIsland,
        GlassFinish.refracting,
      );

      expect(style.fill, const Color(0xFF20242A).withValues(alpha: 0.85));
      expect(style.blurRadius, 6);
      expect(style.sourceDownscale, 4);
      expect(style.backdropSaturation, 3);
      expect(style.enableLiquid, isTrue);
      expect(
        (style.liquidIntensity, style.liquidIndex, style.liquidThickness),
        (0.75, 1.5, 11),
      );
    });

    test('a top panel never refracts: the strong blur at the refracting '
        'opacity', () {
      final style = _resolve(GlassMaterial.topPanel, GlassFinish.refracting);

      expect(style.enableLiquid, isFalse);
      expect(style.fill.a, closeTo(0.85, 1e-6));
      expect((style.blurRadius, style.sourceDownscale), (40, 8));
    });
  });

  test('a flat glass is opaque: it reads no backdrop to tint', () {
    final style = _resolve(GlassMaterial.composerIsland, GlassFinish.flat);

    expect(style.fill, const Color(0xFF20242A));
  });

  group('edges, shadow and corners per material', () {
    test('the composer island: 22 dp corners, 0.5 dp edges, a 1 dp shadow '
        '1/3 dp down', () {
      final style = _resolve(
        GlassMaterial.composerIsland,
        GlassFinish.frosted,
        palette: const ChromePalette.light(),
      );

      expect(style.cornerRadius, 22);
      expect((style.strokeWidthTop, style.strokeWidthBottom), (0.5, 0.5));
      expect(style.shadowColor, const Color(0x20000000));
      expect(style.shadowBlur, 1);
      expect(style.shadowOffset, const Offset(0, 1 / 3));
    });

    test('a panel button: 18 dp corners, 0.5 dp edges, an 11/3 dp shadow '
        '2/3 dp down', () {
      final style = _resolve(
        GlassMaterial.panelButton,
        GlassFinish.frosted,
        palette: const ChromePalette.light(),
      );

      expect(style.cornerRadius, 18);
      expect((style.strokeWidthTop, style.strokeWidthBottom), (0.5, 0.5));
      expect(style.shadowColor, const Color(0x40000000));
      expect(style.shadowBlur, 11 / 3);
      expect(style.shadowOffset, const Offset(0, 2 / 3));
    });

    test('a top panel: square, 0.55 dp edges', () {
      final style = _resolve(GlassMaterial.topPanel, GlassFinish.frosted);

      expect(style.cornerRadius, 0);
      expect((style.strokeWidthTop, style.strokeWidthBottom), (0.55, 0.55));
    });
  });
}
