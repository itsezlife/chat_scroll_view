import 'dart:ui' show Brightness, Color, Offset;

import 'package:flutter/foundation.dart';

/// Paint tokens for a liquid-glass surface.
///
/// Composer island: radius 22 on height 44 → stadium; fill α ≈ 0.85;
/// backdrop sampled at 1/4 resolution, blurred σ 4 in that space, saturation
/// ×3; liquid thickness 11.
@immutable
class LiquidGlassStyle {
  /// Creates a glass material style.
  const LiquidGlassStyle({
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

  /// Composer input-island material (glass path).
  factory LiquidGlassStyle.composerIsland({
    required Color panelBackground,
    required Brightness brightness,
    bool liquidEnabled = true,
    double cornerRadius = 22,
  }) {
    final isDark = brightness == Brightness.dark;
    final fillAlpha = isDark ? (liquidEnabled ? 0.85 : 0.76) : (216 / 255);
    return LiquidGlassStyle(
      fill: panelBackground.withValues(alpha: fillAlpha),
      strokeTop: isDark ? const Color(0x28FFFFFF) : const Color(0xFFFFFFFF),
      strokeBottom: isDark ? const Color(0x14FFFFFF) : const Color(0xFFFFFFFF),
      shadowColor: isDark ? const Color(0x00000000) : const Color(0x20000000),
      cornerRadius: cornerRadius,
      enableLiquid: liquidEnabled,
    );
  }

  /// Premultiplied tint drawn over the refracted backdrop.
  final Color fill;

  /// Top edge highlight / stroke.
  final Color strokeTop;

  /// Bottom edge stroke.
  final Color strokeBottom;

  /// Soft drop shadow (often zero in dark).
  final Color shadowColor;

  /// Painted corner radius (logical px).
  final double cornerRadius;

  /// Backdrop blur sigma in the downscaled sample (image px at
  /// 1 / [sourceDownscale] of device resolution).
  ///
  /// A captured backdrop is blurred after downscaling, so σ 4 there spans
  /// about 4 × [sourceDownscale] device px.
  final double blurSigma;

  /// Backdrop saturation applied in the liquid sample.
  final double backdropSaturation;

  /// How much smaller than device resolution the backdrop is sampled
  /// (default 4).
  ///
  /// A captured backdrop renders at 1/N, blurs, and upsamples in the shader.
  /// A scene [BackdropFilter] cannot change resolution, so it blurs at full
  /// resolution with [effectiveBlurSigma].
  final double sourceDownscale;

  /// Full-resolution Gaussian sigma (logical px) standing in for the
  /// downscale → blur chain on the [BackdropFilter] path.
  double get effectiveBlurSigma =>
      blurSigma * (sourceDownscale > 1 ? sourceDownscale : 1);

  /// Liquid rim thickness (default 11).
  final double liquidThickness;

  /// Refraction strength (default 0.75).
  final double liquidIntensity;

  /// Index of refraction (default 1.5).
  final double liquidIndex;

  /// Top stroke width.
  final double strokeWidthTop;

  /// Bottom stroke width.
  final double strokeWidthBottom;

  /// Shadow blur radius.
  final double shadowBlur;

  /// Shadow offset.
  final Offset shadowOffset;

  /// When false, blur + tint only (no refraction pass).
  final bool enableLiquid;

  /// Premultiplied RGBA for the liquid-glass shader tint.
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
      other is LiquidGlassStyle &&
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
}
