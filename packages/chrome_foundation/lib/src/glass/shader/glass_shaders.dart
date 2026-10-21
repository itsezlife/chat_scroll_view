import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chrome_foundation/src/glass/glass_style.dart';
import 'package:flutter/foundation.dart';

/// Liquid refraction for [ImageFilter.shader] (scene / crop path).
const String _liquidAsset =
    'packages/chrome_foundation/shaders/liquid_glass.frag';

/// Liquid refraction that samples a full backdrop [ui.Image] (capture path).
const String _liquidBackdropAsset =
    'packages/chrome_foundation/shaders/liquid_glass_backdrop.frag';

/// Full-resolution stand-in for sampling the backdrop at 1/4 resolution.
const String _frostPrepassAsset =
    'packages/chrome_foundation/shaders/glass_frost_prepass.frag';

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

/// Loads and caches the liquid-glass shader programs.
abstract final class GlassShaders {
  static GlassShaderPrograms? _programs;
  static Future<GlassShaderPrograms>? _loading;

  /// Whether [ui.ImageFilter.shader] is usable on this backend (Impeller).
  static bool get isSupported => ui.ImageFilter.isShaderFilterSupported;

  /// Where [load] gets the programs from the first time. A test replaces it
  /// (the shader assets are not in a unit test's bundle) and puts
  /// [loadFromAssets] back.
  @visibleForTesting
  static Future<GlassShaderPrograms> Function() loader = loadFromAssets;

  /// Loads programs once; safe to call from multiple widgets.
  static Future<GlassShaderPrograms> load() {
    final existing = _programs;
    if (existing != null) return SynchronousFuture(existing);
    return _loading ??= loader();
  }

  /// Reads the compiled programs from the package's assets.
  @visibleForTesting
  static Future<GlassShaderPrograms> loadFromAssets() async {
    final pair = await (
      ui.FragmentProgram.fromAsset(_liquidAsset),
      ui.FragmentProgram.fromAsset(_liquidBackdropAsset),
      ui.FragmentProgram.fromAsset(_frostPrepassAsset),
    ).wait;
    final programs = GlassShaderPrograms(
      liquid: pair.$1,
      liquidBackdrop: pair.$2,
      frost: pair.$3,
    );
    _programs = programs;
    return programs;
  }

  /// Forgets what was loaded, or failed to, and restores the asset loader.
  @visibleForTesting
  static void debugReset() {
    _programs = null;
    _loading = null;
    loader = loadFromAssets;
  }

  /// Builds glass filter: frost? → blur → liquid (scene [BackdropFilter] path).
  static ui.ImageFilter? createFilter({
    required GlassShaderPrograms programs,
    required ui.Size size,
    required GlassStyle style,
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

    var inner = blur;
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

  // The style's rim, no thicker than a fifth of the shorter side and no
  // thinner than a pixel; a surface under five pixels (one growing from
  // nothing) gets the pixel, the bound never falling below it.
  static double _thickness(GlassStyle style, ui.Size size) => style
      .liquidThickness
      .clamp(1.0, math.max(1.0, size.shortestSide / 5))
      .toDouble();

  /// How far (logical px) outside a [size] surface the liquid shader samples.
  ///
  /// The rim bends the view ray inward by up to
  /// `9 · thickness · intensity · index · sin(critical)`; on a surface
  /// thinner than that the sample lands past the opposite edge.
  static double backdropReach({
    required GlassStyle style,
    required ui.Size size,
  }) {
    if (!style.enableLiquid || size.isEmpty) return 0;
    final index = style.liquidIndex;
    final bend = index > 1 ? math.sqrt(1 - 1 / (index * index)) : 0.0;
    return 9 * _thickness(style, size) * style.liquidIntensity * index * bend;
  }

  /// Configures a direct [ui.FragmentShader] that samples [image].
  ///
  /// [texOrigin] = surface top-left in image pixels; [texScale] = logical
  /// px → image px. [blurRadius] (logical px) adds a 9-tap box blur for an
  /// [image] that is not blurred yet. Refraction applies only with
  /// [GlassStyle.enableLiquid].
  static ui.FragmentShader? createBackdropShader({
    required GlassShaderPrograms programs,
    required ui.Size size,
    required GlassStyle style,
    required ui.Image image,
    required ui.Offset texOrigin,
    required double texScale,
    double blurRadius = 0,
  }) {
    if (size.isEmpty || texScale <= 0) return null;

    final thickness = _thickness(style, size);
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
    shader.setFloat(i++, style.enableLiquid ? style.liquidIntensity : 0);
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
    shader.setFloat(i++, blurRadius);
    shader.setImageSampler(0, image);
    return shader;
  }
}
