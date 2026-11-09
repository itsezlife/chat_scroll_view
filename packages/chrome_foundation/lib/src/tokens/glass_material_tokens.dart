import 'dart:ui' show Brightness, Color;

import 'package:chrome_foundation/src/glass/glass_material.dart';
import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// The colours of one named glass material: tint, edge strokes and shadow.
///
/// Geometry and shader parameters (corner radius, blur, refraction) belong to
/// the glass stack, not to the theme; this is only what varies with the
/// palette.
@immutable
final class GlassMaterialColors {
  /// A material with every colour given.
  const GlassMaterialColors({
    required this.tint,
    required this.strokeTop,
    required this.strokeBottom,
    required this.shadow,
  });

  /// The material's surface colour, drawn over the frosted backdrop.
  ///
  /// The glass sets its opacity, not the theme: 0.85 over a refracting
  /// backdrop, 0.76 over a frosted one, and opaque where no backdrop is read
  /// (a flat glass shows none of the content it would have frosted). The
  /// colour's own alpha multiplies that opacity.
  final Color tint;

  /// Top edge highlight.
  final Color strokeTop;

  /// Bottom edge stroke.
  final Color strokeBottom;

  /// Soft drop shadow ink; fully transparent where the material casts none.
  final Color shadow;

  /// A copy with the named colours replaced.
  GlassMaterialColors copyWith({
    Color? tint,
    Color? strokeTop,
    Color? strokeBottom,
    Color? shadow,
  }) => GlassMaterialColors(
    tint: tint ?? this.tint,
    strokeTop: strokeTop ?? this.strokeTop,
    strokeBottom: strokeBottom ?? this.strokeBottom,
    shadow: shadow ?? this.shadow,
  );

  /// Interpolates every colour between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static GlassMaterialColors lerp(
    GlassMaterialColors a,
    GlassMaterialColors b,
    double t,
  ) => GlassMaterialColors(
    tint: Color.lerp(a.tint, b.tint, t)!,
    strokeTop: Color.lerp(a.strokeTop, b.strokeTop, t)!,
    strokeBottom: Color.lerp(a.strokeBottom, b.strokeBottom, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassMaterialColors &&
          tint == other.tint &&
          strokeTop == other.strokeTop &&
          strokeBottom == other.strokeBottom &&
          shadow == other.shadow;

  @override
  int get hashCode => Object.hash(tint, strokeTop, strokeBottom, shadow);

  @override
  String toString() => 'GlassMaterialColors(tint: $tint)';
}

/// Palette-derived colours of the named glass materials.
///
/// `GlassSurface` reads these through the chrome theme scope: [colorsOf] maps a
/// [GlassMaterial] to its colours. Derived from a [ChromePalette] by
/// [GlassMaterialTokens.fromPalette]; a host overrides one material with
/// [copyWith] or supplies the whole group to a `ChromeThemeScope`.
@immutable
final class GlassMaterialTokens {
  /// A glass token group with every material given.
  const GlassMaterialTokens({
    required this.composerIsland,
    required this.panelButton,
    required this.topPanel,
  });

  /// The default mapping of [palette] roles onto the named materials.
  ///
  /// The composer island and panel buttons tint [ChromePalette.surface], the
  /// top panel [ChromePalette.surfaceDim]. Light edges are opaque white; dark
  /// edges are faint white, the top one stronger than the bottom. Light
  /// materials cast the palette shadow (the island and the top panel at
  /// 0x20, a floating button at 0x40); dark materials cast none.
  factory GlassMaterialTokens.fromPalette(ChromePalette palette) {
    final isDark = palette.brightness == Brightness.dark;
    const white = Color(0xFFFFFFFF);
    Color shadow(int alpha) => palette.shadow.withAlpha(isDark ? 0 : alpha);
    GlassMaterialColors material(
      Color tint, {
      required int darkTop,
      required int shadowAlpha,
    }) => GlassMaterialColors(
      tint: tint,
      strokeTop: isDark ? white.withAlpha(darkTop) : white,
      strokeBottom: isDark ? white.withAlpha(0x14) : white,
      shadow: shadow(shadowAlpha),
    );
    return GlassMaterialTokens(
      composerIsland: material(
        palette.surface,
        darkTop: 0x28,
        shadowAlpha: 0x20,
      ),
      panelButton: material(palette.surface, darkTop: 0x28, shadowAlpha: 0x40),
      topPanel: material(palette.surfaceDim, darkTop: 0x20, shadowAlpha: 0x20),
    );
  }

  /// The composer input island.
  final GlassMaterialColors composerIsland;

  /// Round or pill buttons floating over the panel.
  final GlassMaterialColors panelButton;

  /// The bar docked at the top of the panel.
  final GlassMaterialColors topPanel;

  /// The colours of [material].
  GlassMaterialColors colorsOf(GlassMaterial material) => switch (material) {
    GlassMaterial.composerIsland => composerIsland,
    GlassMaterial.panelButton => panelButton,
    GlassMaterial.topPanel => topPanel,
  };

  /// A copy with the named materials replaced.
  GlassMaterialTokens copyWith({
    GlassMaterialColors? composerIsland,
    GlassMaterialColors? panelButton,
    GlassMaterialColors? topPanel,
  }) => GlassMaterialTokens(
    composerIsland: composerIsland ?? this.composerIsland,
    panelButton: panelButton ?? this.panelButton,
    topPanel: topPanel ?? this.topPanel,
  );

  /// Interpolates every material between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static GlassMaterialTokens lerp(
    GlassMaterialTokens a,
    GlassMaterialTokens b,
    double t,
  ) => GlassMaterialTokens(
    composerIsland: GlassMaterialColors.lerp(
      a.composerIsland,
      b.composerIsland,
      t,
    ),
    panelButton: GlassMaterialColors.lerp(a.panelButton, b.panelButton, t),
    topPanel: GlassMaterialColors.lerp(a.topPanel, b.topPanel, t),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassMaterialTokens &&
          composerIsland == other.composerIsland &&
          panelButton == other.panelButton &&
          topPanel == other.topPanel;

  @override
  int get hashCode => Object.hash(composerIsland, panelButton, topPanel);

  @override
  String toString() => 'GlassMaterialTokens(composerIsland: $composerIsland)';
}
