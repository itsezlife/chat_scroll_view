import 'dart:ui' show Color, Offset;

import 'package:chrome_foundation/src/glass/glass_material.dart';
import 'package:chrome_foundation/src/tokens/glass_material_tokens.dart';
import 'package:flutter/foundation.dart';

/// Resolved paint parameters of one glass surface: the material's colours from
/// the theme plus the shape constants of its effect. Internal.
///
/// Composer island: radius 22 on height 44 gives a stadium; fill alpha about
/// 0.85; backdrop sampled at 1/4 resolution, blurred with sigma 4 in that
/// space, saturation x3; liquid thickness 11.
@immutable
class GlassStyle {
  /// Creates a style with every colour given.
  const GlassStyle({
    required this.fill,
    required this.strokeTop,
    required this.strokeBottom,
    required this.shadowColor,
    this.cornerRadius = 22,
    this.blurSigma = 4,
    this.backdropSaturation = 3,
    this.sourceDownscale = 4,
    this.liquidThickness = 11,
    this.liquidIntensity = 0.75,
    this.liquidIndex = 1.5,
    this.strokeWidthTop = 1,
    this.strokeWidthBottom = 2 / 3,
    this.shadowBlur = 1,
    this.shadowOffset = const Offset(0, 1 / 3),
    this.enableLiquid = true,
  });

  /// The style of [material] in [colors]. [liquid] is false when the
  /// effective quality has no refraction.
  factory GlassStyle.resolve({
    required GlassMaterial material,
    required GlassMaterialColors colors,
    required double cornerRadius,
    required bool liquid,
  }) => GlassStyle(
    fill: colors.fill,
    strokeTop: colors.strokeTop,
    strokeBottom: colors.strokeBottom,
    shadowColor: colors.shadow,
    cornerRadius: cornerRadius,
    enableLiquid: liquid && material != GlassMaterial.topPanel,
  );

  /// Tint drawn over the refracted backdrop.
  final Color fill;

  /// Top edge highlight.
  final Color strokeTop;

  /// Bottom edge stroke.
  final Color strokeBottom;

  /// Soft drop shadow ink (transparent where the material casts none).
  final Color shadowColor;

  /// Painted corner radius (logical px).
  final double cornerRadius;

  /// Backdrop blur sigma in the downscaled sample (image px at
  /// 1 / [sourceDownscale] of device resolution).
  ///
  /// A captured backdrop is blurred after downscaling, so sigma 4 there spans
  /// about 4 x [sourceDownscale] device px.
  final double blurSigma;

  /// Backdrop saturation applied in the liquid sample.
  final double backdropSaturation;

  /// How much smaller than device resolution the backdrop is sampled.
  ///
  /// A captured backdrop renders at 1/N, blurs, and upsamples in the shader.
  /// A scene backdrop filter cannot change resolution, so it blurs at full
  /// resolution with [effectiveBlurSigma].
  final double sourceDownscale;

  /// Full-resolution Gaussian sigma (logical px) standing in for the
  /// downscale then blur chain on the scene-filter path.
  double get effectiveBlurSigma =>
      blurSigma * (sourceDownscale > 1 ? sourceDownscale : 1);

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
          blurSigma == other.blurSigma &&
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
    blurSigma,
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
  String toString() => 'GlassStyle(fill: $fill, cornerRadius: $cornerRadius)';
}
