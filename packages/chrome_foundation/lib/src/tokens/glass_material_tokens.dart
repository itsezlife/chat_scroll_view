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
    this.tintOpacity,
    this.backdropSaturation = 3,
  });

  /// The colours of a menu on a chrome scrim that offers a glass source
  /// (`GlassMaterial.scrimMenu`): the menu's tint, [ChromePalette.surfaceRaised]
  /// at 0.85 in a dark theme and 0.825 in a light one; in a light theme a
  /// white top edge at 0x44, a bottom one at 0x22 and a black shadow at
  /// 0x26, in a dark one neither.
  ///
  /// The backdrop's saturation is left at 1: the glass source is a still
  /// already toned (saturation scaled by 2 dark, 3 light), and raising it
  /// again would double the tone. Off such a scrim, a menu takes the
  /// theme's menu colours, which raise the saturation of the scene behind.
  factory GlassMaterialColors.scrimMenu(ChromePalette palette) {
    final isDark = palette.brightness == Brightness.dark;
    const white = Color(0xFFFFFFFF);
    return GlassMaterialColors(
      tint: palette.surfaceRaised,
      strokeTop: white.withAlpha(isDark ? 0 : 0x44),
      strokeBottom: white.withAlpha(isDark ? 0 : 0x22),
      shadow: Color(isDark ? 0x00000000 : 0x26000000),
      tintOpacity: isDark ? 0.85 : 0.825,
      backdropSaturation: 1,
    );
  }

  /// The material's surface colour, drawn over the frosted backdrop.
  ///
  /// The glass sets its opacity, not the theme: 0.85 over a refracting
  /// backdrop, 0.76 over a frosted one, and opaque where no backdrop is read
  /// (a flat glass shows none of the content it would have frosted). The
  /// colour's own alpha multiplies that opacity.
  final Color tint;

  /// The opacity of [tint] over a backdrop whatever the finish, or null to
  /// let the finish set it. A flat glass is opaque either way.
  final double? tintOpacity;

  /// The backdrop's saturation: 1 leaves its colours, 3 triples their
  /// distance from grey.
  final double backdropSaturation;

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
    double? tintOpacity,
    double? backdropSaturation,
  }) => GlassMaterialColors(
    tint: tint ?? this.tint,
    strokeTop: strokeTop ?? this.strokeTop,
    strokeBottom: strokeBottom ?? this.strokeBottom,
    shadow: shadow ?? this.shadow,
    tintOpacity: tintOpacity ?? this.tintOpacity,
    backdropSaturation: backdropSaturation ?? this.backdropSaturation,
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
    tintOpacity: switch ((a.tintOpacity, b.tintOpacity)) {
      (final from?, final to?) => from + (to - from) * t,
      (final from, final to) => t < 0.5 ? from : to,
    },
    backdropSaturation:
        a.backdropSaturation +
        (b.backdropSaturation - a.backdropSaturation) * t,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassMaterialColors &&
          tint == other.tint &&
          strokeTop == other.strokeTop &&
          strokeBottom == other.strokeBottom &&
          shadow == other.shadow &&
          tintOpacity == other.tintOpacity &&
          backdropSaturation == other.backdropSaturation;

  @override
  int get hashCode => Object.hash(
    tint,
    strokeTop,
    strokeBottom,
    shadow,
    tintOpacity,
    backdropSaturation,
  );

  @override
  String toString() => 'GlassMaterialColors(tint: $tint)';
}

/// Palette-derived colours of the glass roles.
///
/// `GlassSurface` reads these through the chrome theme scope: [colorsOf] gives
/// a [GlassMaterial] the colours of its [GlassMaterial.colorRole] (a surface
/// may pass its own instead). Derived from a [ChromePalette] by
/// [GlassMaterialTokens.fromPalette]; a host overrides one role with
/// [copyWith] or supplies the whole group to a `ChromeThemeScope`.
@immutable
final class GlassMaterialTokens {
  /// A glass token group with every role given.
  const GlassMaterialTokens({
    required this.island,
    required this.button,
    required this.bar,
    required this.menu,
    required this.panel,
    required this.bubble,
    required this.tabs,
  });

  /// The default mapping of [palette] roles onto the glass roles.
  ///
  /// The island, buttons and panels tint [ChromePalette.surface], bars and
  /// bubbles [ChromePalette.surfaceDim]. Light edges are opaque white; dark
  /// edges are faint white, the top one stronger than the bottom. Light
  /// materials cast the palette shadow (the island, panels and bars at 0x20,
  /// a floating button at 0x40); dark materials cast none.
  ///
  /// A menu tints [ChromePalette.surfaceRaised] at 0.85 in a dark theme and
  /// 0.825 in a light one, over a backdrop saturated x2 and x3. A light menu
  /// has a white top edge at 0x44, a bottom one at 0x22 and a 0x38 black
  /// shadow; a dark one has neither.
  ///
  /// A tab bar tints [ChromePalette.surface]. Its light edges are the
  /// shadow ink at 0x11 (top) and 0x20 (bottom) under a 0x20 shadow; its
  /// dark ones white at 0x06 and 0x11 under a 0x04 white glow.
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
    final island = material(palette.surface, darkTop: 0x28, shadowAlpha: 0x20);
    final bar = material(palette.surfaceDim, darkTop: 0x20, shadowAlpha: 0x20);
    return GlassMaterialTokens(
      island: island,
      button: material(palette.surface, darkTop: 0x28, shadowAlpha: 0x40),
      bar: bar,
      menu: GlassMaterialColors(
        tint: palette.surfaceRaised,
        strokeTop: white.withAlpha(isDark ? 0 : 0x44),
        strokeBottom: white.withAlpha(isDark ? 0 : 0x22),
        shadow: Color(isDark ? 0x00000000 : 0x38000000),
        tintOpacity: isDark ? 0.85 : 0.825,
        backdropSaturation: isDark ? 2 : 3,
      ),
      panel: island,
      bubble: bar,
      tabs: GlassMaterialColors(
        tint: palette.surface,
        strokeTop: isDark
            ? white.withAlpha(0x06)
            : palette.shadow.withAlpha(0x11),
        strokeBottom: isDark
            ? white.withAlpha(0x11)
            : palette.shadow.withAlpha(0x20),
        shadow: isDark ? white.withAlpha(0x04) : palette.shadow.withAlpha(0x20),
      ),
    );
  }

  /// The composer's input island.
  final GlassMaterialColors island;

  /// Round or pill buttons floating over content.
  final GlassMaterialColors button;

  /// Bars docked at an edge.
  final GlassMaterialColors bar;

  /// Menus and popups over a dimmed screen.
  final GlassMaterialColors menu;

  /// Bottom panels.
  final GlassMaterialColors panel;

  /// Small floating labels.
  final GlassMaterialColors bubble;

  /// Tab bars floating over content.
  final GlassMaterialColors tabs;

  /// The colours of [role].
  GlassMaterialColors of(GlassColorRole role) => switch (role) {
    GlassColorRole.island => island,
    GlassColorRole.button => button,
    GlassColorRole.bar => bar,
    GlassColorRole.menu => menu,
    GlassColorRole.panel => panel,
    GlassColorRole.bubble => bubble,
    GlassColorRole.tabs => tabs,
  };

  /// The colours of [material]: those of its colour role.
  GlassMaterialColors colorsOf(GlassMaterial material) =>
      of(material.colorRole);

  /// A copy with the named roles replaced.
  GlassMaterialTokens copyWith({
    GlassMaterialColors? island,
    GlassMaterialColors? button,
    GlassMaterialColors? bar,
    GlassMaterialColors? menu,
    GlassMaterialColors? panel,
    GlassMaterialColors? bubble,
    GlassMaterialColors? tabs,
  }) => GlassMaterialTokens(
    island: island ?? this.island,
    button: button ?? this.button,
    bar: bar ?? this.bar,
    menu: menu ?? this.menu,
    panel: panel ?? this.panel,
    bubble: bubble ?? this.bubble,
    tabs: tabs ?? this.tabs,
  );

  /// Interpolates every role between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static GlassMaterialTokens lerp(
    GlassMaterialTokens a,
    GlassMaterialTokens b,
    double t,
  ) => GlassMaterialTokens(
    island: GlassMaterialColors.lerp(a.island, b.island, t),
    button: GlassMaterialColors.lerp(a.button, b.button, t),
    bar: GlassMaterialColors.lerp(a.bar, b.bar, t),
    menu: GlassMaterialColors.lerp(a.menu, b.menu, t),
    panel: GlassMaterialColors.lerp(a.panel, b.panel, t),
    bubble: GlassMaterialColors.lerp(a.bubble, b.bubble, t),
    tabs: GlassMaterialColors.lerp(a.tabs, b.tabs, t),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassMaterialTokens &&
          GlassColorRole.values.every((role) => of(role) == other.of(role));

  @override
  int get hashCode => Object.hashAll(GlassColorRole.values.map(of));

  @override
  String toString() => 'GlassMaterialTokens(island: $island)';
}
