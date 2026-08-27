import 'dart:ui' show Brightness, Color, Offset;

import 'package:flutter/foundation.dart';

/// Paint tokens for a Telegram-style liquid-glass surface.
///
/// Composer island: radius 22 on height 44 → stadium; fill α ≈ 0.85;
/// glass source 4× frost + blur σ≈4 **in downscaled space** (≈σ16 full-res)
/// + sat ×3; liquid thickness 11.
@immutable
class TelegramGlassStyle {
  /// Creates a glass material style.
  const TelegramGlassStyle({
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
  factory TelegramGlassStyle.composerIsland({
    required Color panelBackground,
    required Brightness brightness,
    bool liquidEnabled = true,
    double cornerRadius = 22,
  }) {
    final isDark = brightness == Brightness.dark;
    final fillAlpha = isDark ? (liquidEnabled ? 0.85 : 0.76) : (216 / 255);
    return TelegramGlassStyle(
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

  /// Backdrop blur sigma in **post-downscale** space (Telegram glass source).
  ///
  /// Android: `convertRadiusToSigma(dpf2(6))` ≈ 4 applied **after**
  /// `DownscaledRenderNode` scale 4×. At full resolution that is
  /// [effectiveBlurSigma] ≈ [blurSigma] × [sourceDownscale], not σ=4 alone.
  /// Applying σ=4 at full res leaves glyph stems readable — the screenshot gap.
  final double blurSigma;

  /// Backdrop saturation before / in the liquid sample (`setSaturation(3)`).
  final double backdropSaturation;

  /// Glass-source downscale factor (`DownscaledRenderNode` scale, default 4).
  ///
  /// Real Android path: render glass source at 1/N, blur, upsample. Scene
  /// [BackdropFilter] cannot change resolution, so we box-average N×N then
  /// blur with [effectiveBlurSigma].
  final double sourceDownscale;

  /// Full-resolution Gaussian sigma matching Telegram's downscale→blur chain.
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
      other is TelegramGlassStyle &&
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
