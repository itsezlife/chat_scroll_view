import 'dart:ui' show Brightness, Color;

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
    required this.fill,
    required this.strokeTop,
    required this.strokeBottom,
    required this.shadow,
  });

  /// Tint drawn over the sampled backdrop.
  final Color fill;

  /// Top edge highlight.
  final Color strokeTop;

  /// Bottom edge stroke.
  final Color strokeBottom;

  /// Soft drop shadow ink; fully transparent where the material casts none.
  final Color shadow;

  /// A copy with the named colours replaced.
  GlassMaterialColors copyWith({
    Color? fill,
    Color? strokeTop,
    Color? strokeBottom,
    Color? shadow,
  }) => GlassMaterialColors(
    fill: fill ?? this.fill,
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
    fill: Color.lerp(a.fill, b.fill, t)!,
    strokeTop: Color.lerp(a.strokeTop, b.strokeTop, t)!,
    strokeBottom: Color.lerp(a.strokeBottom, b.strokeBottom, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassMaterialColors &&
          fill == other.fill &&
          strokeTop == other.strokeTop &&
          strokeBottom == other.strokeBottom &&
          shadow == other.shadow;

  @override
  int get hashCode => Object.hash(fill, strokeTop, strokeBottom, shadow);

  @override
  String toString() => 'GlassMaterialColors(fill: $fill)';
}

/// Palette-derived colours of the named glass materials.
///
/// Type only: the surface widget, quality policy and strategy chain that paint
/// these materials arrive with the glass stack. Derived from a
/// [ChromePalette] by [GlassMaterialTokens.fromPalette]; a host overrides one
/// material with [copyWith] or supplies the whole group to a
/// `ChromeThemeScope`.
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
  /// Each material tints its surface role at 85% opacity. Light strokes are
  /// opaque white; dark strokes are faint white. The light shadow is the
  /// palette shadow at 12.5% and dark materials cast none.
  factory GlassMaterialTokens.fromPalette(ChromePalette palette) {
    final isDark = palette.brightness == Brightness.dark;
    final strokeTop = isDark
        ? const Color(0x28FFFFFF)
        : const Color(0xFFFFFFFF);
    final strokeBottom = isDark
        ? const Color(0x14FFFFFF)
        : const Color(0xFFFFFFFF);
    final shadow = palette.shadow.withValues(alpha: isDark ? 0 : 0.125);
    GlassMaterialColors material(Color surface) => GlassMaterialColors(
      fill: surface.withValues(alpha: 0.85),
      strokeTop: strokeTop,
      strokeBottom: strokeBottom,
      shadow: shadow,
    );
    return GlassMaterialTokens(
      composerIsland: material(palette.surface),
      panelButton: material(palette.surfaceRaised),
      topPanel: material(palette.surfaceDim),
    );
  }

  /// The composer input island.
  final GlassMaterialColors composerIsland;

  /// Round or pill buttons floating over the panel.
  final GlassMaterialColors panelButton;

  /// The bar docked at the top of the panel.
  final GlassMaterialColors topPanel;

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
