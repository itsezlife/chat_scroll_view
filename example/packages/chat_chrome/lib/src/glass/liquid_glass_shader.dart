import 'dart:ui' as ui;

import 'package:chat_chrome/src/glass/telegram_glass_style.dart';
import 'package:flutter/foundation.dart';

/// Liquid refraction for [ImageFilter.shader] (scene / crop path).
const String kLiquidGlassShaderAsset =
    'packages/chat_chrome/shaders/liquid_glass.frag';

/// Liquid refraction that samples a full backdrop [ui.Image] (capture path).
const String kLiquidGlassBackdropShaderAsset =
    'packages/chat_chrome/shaders/liquid_glass_backdrop.frag';

/// 4× downscale stand-in (`DownscaledRenderNode` glass scale).
const String kGlassFrostPrepassAsset =
    'packages/chat_chrome/shaders/glass_frost_prepass.frag';

/// Loaded fragment programs for the glass pipeline.
@immutable
class GlassShaderPrograms {
  /// Creates a program set.
  const GlassShaderPrograms({
    required this.liquid,
    required this.liquidBackdrop,
    required this.frost,
  });

  /// Refraction + tint for [ImageFilter] (texture = filtered child).
  final ui.FragmentProgram liquid;

  /// Refraction + tint sampling a full capture [ui.Image].
  final ui.FragmentProgram liquidBackdrop;

  /// Neighborhood average before blur (scene path only).
  final ui.FragmentProgram frost;
}

/// Loads and caches Telegram liquid-glass filter programs.
abstract final class LiquidGlassShader {
  static GlassShaderPrograms? _programs;
  static Future<GlassShaderPrograms>? _loading;

  /// Whether [ui.ImageFilter.shader] is usable on this backend (Impeller).
  static bool get isSupported => ui.ImageFilter.isShaderFilterSupported;

  /// Loads programs once; safe to call from multiple widgets.
  static Future<GlassShaderPrograms> load() {
    final existing = _programs;
    if (existing != null) return SynchronousFuture(existing);
    return _loading ??= () async {
      final pair = await (
        ui.FragmentProgram.fromAsset(kLiquidGlassShaderAsset),
        ui.FragmentProgram.fromAsset(kLiquidGlassBackdropShaderAsset),
        ui.FragmentProgram.fromAsset(kGlassFrostPrepassAsset),
      ).wait;
      final programs = GlassShaderPrograms(
        liquid: pair.$1,
        liquidBackdrop: pair.$2,
        frost: pair.$3,
      );
      _programs = programs;
      return programs;
    }();
  }

  /// Builds glass filter: frost? → blur → liquid (scene [BackdropFilter] path).
  static ui.ImageFilter? createFilter({
    required GlassShaderPrograms programs,
    required ui.Size size,
    required TelegramGlassStyle style,
    bool applyFrost = true,
  }) {
    if (!isSupported || size.isEmpty) return null;

    final thickness = style.liquidThickness
        .clamp(1.0, size.shortestSide / 5)
        .toDouble();
    final radius = style.cornerRadius;
    final center = ui.Offset(size.width / 2, size.height / 2);
    final half = ui.Offset(size.width / 2, size.height / 2);
    final fill = style.fillPremultiplied;

    final liquid = programs.liquid.fragmentShader();
    // ImageFilter.shader: float 0..1 = u_size. Custom uniforms start at 2.
    var i = 2;
    liquid.setFloat(i++, center.dx);
    liquid.setFloat(i++, center.dy);
    liquid.setFloat(i++, half.dx);
    liquid.setFloat(i++, half.dy);
    liquid.setFloat(i++, radius);
    liquid.setFloat(i++, radius);
    liquid.setFloat(i++, radius);
    liquid.setFloat(i++, radius);
    liquid.setFloat(i++, thickness);
    liquid.setFloat(i++, style.liquidIndex);
    liquid.setFloat(i++, style.liquidIntensity);
    liquid.setFloat(i++, fill.r);
    liquid.setFloat(i++, fill.g);
    liquid.setFloat(i++, fill.b);
    liquid.setFloat(i++, fill.a);
    liquid.setFloat(i++, style.backdropSaturation);

    final effectiveSigma = style.effectiveBlurSigma;
    final blur = ui.ImageFilter.blur(
      sigmaX: effectiveSigma,
      sigmaY: effectiveSigma,
      tileMode: ui.TileMode.clamp,
    );

    ui.ImageFilter inner = blur;
    final downscale = style.sourceDownscale;
    if (applyFrost && downscale > 1) {
      final frost = programs.frost.fragmentShader();
      // u_scale after auto u_size (floats 0..1).
      frost.setFloat(2, downscale);
      inner = ui.ImageFilter.compose(
        outer: blur,
        inner: ui.ImageFilter.shader(frost),
      );
    }

    return ui.ImageFilter.compose(
      outer: ui.ImageFilter.shader(liquid),
      inner: inner,
    );
  }

  /// Configures a direct [ui.FragmentShader] that samples [image] (full capture).
  ///
  /// [texOrigin] = island top-left in capture pixels;
  /// [texScale] = logical px → capture px ([GlassBackdropController.pixelRatio]).
  static ui.FragmentShader? createBackdropShader({
    required GlassShaderPrograms programs,
    required ui.Size size,
    required TelegramGlassStyle style,
    required ui.Image image,
    required ui.Offset texOrigin,
    required double texScale,
  }) {
    if (size.isEmpty || texScale <= 0) return null;

    final thickness = style.liquidThickness
        .clamp(1.0, size.shortestSide / 5)
        .toDouble();
    final radius = style.cornerRadius;
    final center = ui.Offset(size.width / 2, size.height / 2);
    final half = ui.Offset(size.width / 2, size.height / 2);
    final fill = style.fillPremultiplied;

    final shader = programs.liquidBackdrop.fragmentShader();
    var i = 0;
    shader.setFloat(i++, size.width);
    shader.setFloat(i++, size.height);
    shader.setFloat(i++, center.dx);
    shader.setFloat(i++, center.dy);
    shader.setFloat(i++, half.dx);
    shader.setFloat(i++, half.dy);
    shader.setFloat(i++, radius);
    shader.setFloat(i++, radius);
    shader.setFloat(i++, radius);
    shader.setFloat(i++, radius);
    shader.setFloat(i++, thickness);
    shader.setFloat(i++, style.liquidIndex);
    shader.setFloat(i++, style.liquidIntensity);
    shader.setFloat(i++, fill.r);
    shader.setFloat(i++, fill.g);
    shader.setFloat(i++, fill.b);
    shader.setFloat(i++, fill.a);
    shader.setFloat(i++, style.backdropSaturation);
    shader.setFloat(i++, image.width.toDouble());
    shader.setFloat(i++, image.height.toDouble());
    shader.setFloat(i++, texOrigin.dx);
    shader.setFloat(i++, texOrigin.dy);
    shader.setFloat(i++, texScale);
    // Two stacked 9-tap passes aren't available; use a wide logical radius so
    // frost reads like Telegram glass (downscale + blur), not sharp tint.
    shader.setFloat(i++, style.blurSigma * 2.5);
    shader.setImageSampler(0, image);
    return shader;
  }
}
