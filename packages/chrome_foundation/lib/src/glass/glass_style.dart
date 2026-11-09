import 'dart:ui' show Color, Offset;

import 'package:chrome_foundation/src/glass/glass_material.dart';
import 'package:chrome_foundation/src/tokens/glass_material_tokens.dart';
import 'package:flutter/foundation.dart';

/// What a surface draws behind its child, as far as the look goes. Internal.
enum GlassFinish {
  /// A lightly blurred backdrop bent at the rim.
  refracting,

  /// A strongly blurred backdrop.
  frosted,

  /// No backdrop: the tint alone, opaque.
  flat,
}

/// Resolved paint parameters of one glass surface: the material's colours
/// from the theme, its geometry, and the effect of its [GlassFinish]. Internal.
///
/// The frosted look renders the content behind the glass at an eighth of
/// device resolution, blurs it by a 40 dp radius and triples its saturation,
/// then draws the tint over it at 0.76. The refracting look samples at a
/// quarter with a 6 dp radius (the rim's bend carries the rest), tints at
/// 0.85, and bends the view at the rim (intensity 0.75, index 1.5, a rim 11 dp
/// thick but no thicker than a fifth of the shorter side).
@immutable
class GlassStyle {
  /// Creates a style with every colour given; the rest defaults to the
  /// frosted look of a composer island.
  const GlassStyle({
    required this.fill,
    required this.strokeTop,
    required this.strokeBottom,
    required this.shadowColor,
    this.cornerRadius = 22,
    this.blurRadius = frostedBlurRadius,
    this.backdropSaturation = 3,
    this.sourceDownscale = frostedSourceDownscale,
    this.liquidThickness = 11,
    this.liquidIntensity = 0.75,
    this.liquidIndex = 1.5,
    this.strokeWidthTop = 0.5,
    this.strokeWidthBottom = 0.5,
    this.shadowBlur = 1,
    this.shadowOffset = const Offset(0, 1 / 3),
    this.enableLiquid = false,
  });

  /// The style of [material] in [colors] under [finish].
  ///
  /// A material that never refracts ([GlassMaterial.topPanel]) keeps the
  /// frosted blur under a refracting finish, at the refracting opacity: the
  /// opacity follows the host's choice of look, the blur the surface's.
  factory GlassStyle.resolve({
    required GlassMaterial material,
    required GlassMaterialColors colors,
    required double cornerRadius,
    required GlassFinish finish,
  }) {
    final refracts =
        finish == GlassFinish.refracting && material != GlassMaterial.topPanel;
    final opacity = switch (finish) {
      GlassFinish.refracting => refractingTintOpacity,
      GlassFinish.frosted => frostedTintOpacity,
      GlassFinish.flat => 1.0,
    };
    return GlassStyle(
      fill: colors.tint.withValues(alpha: colors.tint.a * opacity),
      strokeTop: colors.strokeTop,
      strokeBottom: colors.strokeBottom,
      shadowColor: colors.shadow,
      cornerRadius: cornerRadius,
      blurRadius: refracts ? refractingBlurRadius : frostedBlurRadius,
      sourceDownscale: refracts
          ? refractingSourceDownscale
          : frostedSourceDownscale,
      strokeWidthTop: material.strokeWidth,
      strokeWidthBottom: material.strokeWidth,
      shadowBlur: material.shadowBlur,
      shadowOffset: material.shadowOffset,
      enableLiquid: refracts,
    );
  }

  /// Opacity of the tint over a refracting backdrop.
  static const double refractingTintOpacity = 0.85;

  /// Opacity of the tint over a frosted backdrop: lower than the refracting
  /// one, since the strong blur already hides the content's detail.
  static const double frostedTintOpacity = 0.76;

  /// Blur radius (logical px) of the frosted look.
  static const double frostedBlurRadius = 40;

  /// Blur radius (logical px) of the refracting look.
  static const double refractingBlurRadius = 6;

  /// How much smaller than device resolution the frosted look samples.
  static const double frostedSourceDownscale = 8;

  /// How much smaller than device resolution the refracting look samples:
  /// the rim bends detail into view, so it needs more of it.
  static const double refractingSourceDownscale = 4;

  /// Tint drawn over the backdrop, its opacity already the finish's.
  final Color fill;

  /// Top edge highlight.
  final Color strokeTop;

  /// Bottom edge stroke.
  final Color strokeBottom;

  /// Soft drop shadow ink (transparent where the material casts none).
  final Color shadowColor;

  /// Painted corner radius (logical px).
  final double cornerRadius;

  /// Backdrop blur as a radius (logical px), the convention in which a blur
  /// radius r is a Gaussian of sigma 0.57735 r + 0.5 device px ([blurSigma]).
  final double blurRadius;

  /// Backdrop saturation: 1 leaves the colours, 3 triples their distance
  /// from grey.
  final double backdropSaturation;

  /// How much smaller than device resolution the backdrop is sampled.
  ///
  /// A captured backdrop renders at 1/N, blurs at that size, and is scaled
  /// back up when drawn. A scene backdrop filter cannot change resolution,
  /// so it blurs at full resolution with the same [blurSigma].
  final double sourceDownscale;

  /// Gaussian sigma (logical px) of [blurRadius] on a screen of
  /// [devicePixelRatio].
  ///
  /// The 0.57735 r + 0.5 conversion is in device px; the half pixel makes the
  /// logical sigma a little larger on a coarser screen.
  double blurSigma({required double devicePixelRatio}) =>
      blurRadius > 0 ? _sigmaScale * blurRadius + 0.5 / devicePixelRatio : 0;

  /// [blurSigma] in the px of a capture at 1 / [sourceDownscale] of device
  /// resolution: 40 dp is a sigma of 8 such px on a 2.75 screen.
  double captureBlurSigma({required double devicePixelRatio}) =>
      blurSigma(devicePixelRatio: devicePixelRatio) *
      devicePixelRatio /
      sourceDownscale;

  // 1 / sqrt(3): the radius-to-sigma factor of the blur radius convention.
  static const double _sigmaScale = 0.57735;

  /// Liquid rim thickness.
  final double liquidThickness;

  /// Refraction strength.
  final double liquidIntensity;

  /// Index of refraction.
  final double liquidIndex;

  /// Top stroke width.
  final double strokeWidthTop;

  /// Bottom stroke width.
  final double strokeWidthBottom;

  /// Shadow blur radius.
  final double shadowBlur;

  /// Shadow offset.
  final Offset shadowOffset;

  /// When false, blur and tint only (no refraction pass).
  final bool enableLiquid;

  /// Premultiplied RGBA for the liquid shader tint.
  Color get fillPremultiplied {
    final a = fill.a;
    return Color.from(
      alpha: a,
      red: fill.r * a,
      green: fill.g * a,
      blue: fill.b * a,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassStyle &&
          fill == other.fill &&
          strokeTop == other.strokeTop &&
          strokeBottom == other.strokeBottom &&
          shadowColor == other.shadowColor &&
          cornerRadius == other.cornerRadius &&
          blurRadius == other.blurRadius &&
          backdropSaturation == other.backdropSaturation &&
          sourceDownscale == other.sourceDownscale &&
          liquidThickness == other.liquidThickness &&
          liquidIntensity == other.liquidIntensity &&
          liquidIndex == other.liquidIndex &&
          strokeWidthTop == other.strokeWidthTop &&
          strokeWidthBottom == other.strokeWidthBottom &&
          shadowBlur == other.shadowBlur &&
          shadowOffset == other.shadowOffset &&
          enableLiquid == other.enableLiquid;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    fill,
    strokeTop,
    strokeBottom,
    shadowColor,
    cornerRadius,
    blurRadius,
    backdropSaturation,
    sourceDownscale,
    liquidThickness,
    liquidIntensity,
    liquidIndex,
    strokeWidthTop,
    strokeWidthBottom,
    shadowBlur,
    shadowOffset,
    enableLiquid,
  ]);

  @override
  String toString() =>
      'GlassStyle(fill: $fill, cornerRadius: $cornerRadius, '
      'blurRadius: $blurRadius, liquid: $enableLiquid)';
}
