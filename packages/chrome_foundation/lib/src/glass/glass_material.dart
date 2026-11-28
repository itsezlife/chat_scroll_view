import 'dart:ui' show Offset, lerpDouble;

import 'package:flutter/foundation.dart';

/// The role whose colours a glass material takes from the theme
/// (`GlassMaterialTokens`): the same names as the presets of
/// [GlassMaterial].
enum GlassColorRole {
  /// The composer's input island.
  island,

  /// Round or pill buttons floating over content.
  button,

  /// Bars docked at an edge.
  bar,

  /// Menus and popups over a dimmed screen.
  menu,

  /// Bottom panels: the one in the keyboard's place, docked, or a popup.
  panel,

  /// Small floating labels (a fast scroll's date).
  bubble,

  /// A tab bar floating over content.
  tabs,
}

/// What a glass surface is made of, apart from its colours: its corners,
/// edges, shadow and effect.
///
/// A value, not a fixed list: a surface takes the preset of its role and
/// adjusts it (`GlassMaterial.panel.copyWith(cornerRadius: 16)`), or builds
/// its own. Its colours come from `GlassMaterialTokens` in the chrome theme
/// scope by [colorRole] (or a surface passes its own), so one brightness
/// mechanism drives them. The finish (blur, refraction, tint opacity by
/// quality, lite mode, a route in motion) stays the host's `GlassQuality`:
/// a material cannot turn refraction on where the finish has it off.
@immutable
final class GlassMaterial {
  /// A material with every part given.
  const GlassMaterial({
    required this.colorRole,
    required this.cornerRadius,
    required this.strokeWidth,
    required this.shadowBlur,
    required this.shadowOffset,
    this.refracts = true,
    this.blurRadius,
  });

  /// The composer input island: a stadium at the default radius on a 44 dp
  /// island.
  static const island = GlassMaterial(
    colorRole: GlassColorRole.island,
    cornerRadius: 22,
    strokeWidth: 0.5,
    shadowBlur: 1,
    shadowOffset: Offset(0, 1 / 3),
  );

  /// Round or pill buttons floating over content; a surface passes half the
  /// button's size as its corner radius for a circle. Casts the deepest
  /// shadow.
  static const button = GlassMaterial(
    colorRole: GlassColorRole.button,
    cornerRadius: 18,
    strokeWidth: 0.5,
    shadowBlur: 11 / 3,
    shadowOffset: Offset(0, 2 / 3),
  );

  /// A bar docked at an edge: square corners, never refracting.
  static const bar = GlassMaterial(
    colorRole: GlassColorRole.bar,
    cornerRadius: 0,
    strokeWidth: 0.55,
    shadowBlur: 1,
    shadowOffset: Offset(0, 1 / 3),
    refracts: false,
  );

  /// A menu or popup over a dimmed screen: 12 dp corners, 2/3 dp edges, a
  /// soft 3.5 dp shadow all round, and a blur stronger than the frosted one
  /// (80 dp), never refracting.
  static const menu = GlassMaterial(
    colorRole: GlassColorRole.menu,
    cornerRadius: 12,
    strokeWidth: 2 / 3,
    shadowBlur: 3.5,
    shadowOffset: Offset.zero,
    refracts: false,
    blurRadius: 80,
  );

  /// A menu on a chrome scrim that offers a glass source: the [menu]'s
  /// geometry with a 4 dp shadow all round. Its colours are
  /// `GlassMaterialColors.scrimMenu`, which a surface passes; the theme's
  /// menu colours raise a backdrop's saturation, which the glass source's
  /// tone has already done.
  static const scrimMenu = GlassMaterial(
    colorRole: GlassColorRole.menu,
    cornerRadius: 12,
    strokeWidth: 2 / 3,
    shadowBlur: 4,
    shadowOffset: Offset.zero,
    refracts: false,
    blurRadius: 80,
  );

  /// A bottom panel (in the keyboard's place, docked, a popup panel): the
  /// island's edges and shadow, its effect running to the panel's edges;
  /// the surface rounds its top corners (`GlassSurface.borderRadius`).
  static const panel = GlassMaterial(
    colorRole: GlassColorRole.panel,
    cornerRadius: 0,
    strokeWidth: 0.5,
    shadowBlur: 1,
    shadowOffset: Offset(0, 1 / 3),
  );

  /// A small floating label (a fast scroll's date): a bar's edges, never
  /// refracting; the surface gives its corners.
  static const bubble = GlassMaterial(
    colorRole: GlassColorRole.bubble,
    cornerRadius: 0,
    strokeWidth: 0.55,
    shadowBlur: 1,
    shadowOffset: Offset(0, 1 / 3),
    refracts: false,
  );

  /// A tab bar floating over content: a stadium on a 56 dp bar, hairline
  /// 0.4 dp edges and a soft shadow 0.85 dp down.
  static const tabs = GlassMaterial(
    colorRole: GlassColorRole.tabs,
    cornerRadius: 28,
    strokeWidth: 0.4,
    shadowBlur: 8 / 3,
    shadowOffset: Offset(0, 0.85),
  );

  /// The theme colours this material takes.
  final GlassColorRole colorRole;

  /// The corner radius (logical px) used when a surface names none.
  final double cornerRadius;

  /// Width (logical px) of the top highlight and of the bottom edge.
  final double strokeWidth;

  /// Blur radius (logical px) of the drop shadow, in the `BoxShadow` sense.
  final double shadowBlur;

  /// Offset (logical px) of the drop shadow.
  final Offset shadowOffset;

  /// Whether the material bends the view at its rim under a refracting
  /// finish; one that does not keeps the frosted blur there.
  final bool refracts;

  /// The backdrop blur radius (logical px) of the material, or null for its
  /// finish's.
  final double? blurRadius;

  /// A copy with the given parts replaced.
  GlassMaterial copyWith({
    GlassColorRole? colorRole,
    double? cornerRadius,
    double? strokeWidth,
    double? shadowBlur,
    Offset? shadowOffset,
    bool? refracts,
    double? blurRadius,
  }) => GlassMaterial(
    colorRole: colorRole ?? this.colorRole,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    shadowBlur: shadowBlur ?? this.shadowBlur,
    shadowOffset: shadowOffset ?? this.shadowOffset,
    refracts: refracts ?? this.refracts,
    blurRadius: blurRadius ?? this.blurRadius,
  );

  /// Interpolates the geometry between [a] and [b]; the colour role and the
  /// refraction switch at the middle.
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static GlassMaterial lerp(GlassMaterial a, GlassMaterial b, double t) =>
      GlassMaterial(
        colorRole: t < 0.5 ? a.colorRole : b.colorRole,
        cornerRadius: lerpDouble(a.cornerRadius, b.cornerRadius, t)!,
        strokeWidth: lerpDouble(a.strokeWidth, b.strokeWidth, t)!,
        shadowBlur: lerpDouble(a.shadowBlur, b.shadowBlur, t)!,
        shadowOffset: Offset.lerp(a.shadowOffset, b.shadowOffset, t)!,
        refracts: t < 0.5 ? a.refracts : b.refracts,
        blurRadius: switch ((a.blurRadius, b.blurRadius)) {
          (final from?, final to?) => lerpDouble(from, to, t),
          (final from, final to) => t < 0.5 ? from : to,
        },
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassMaterial &&
          colorRole == other.colorRole &&
          cornerRadius == other.cornerRadius &&
          strokeWidth == other.strokeWidth &&
          shadowBlur == other.shadowBlur &&
          shadowOffset == other.shadowOffset &&
          refracts == other.refracts &&
          blurRadius == other.blurRadius;

  @override
  int get hashCode => Object.hash(
    colorRole,
    cornerRadius,
    strokeWidth,
    shadowBlur,
    shadowOffset,
    refracts,
    blurRadius,
  );

  @override
  String toString() =>
      'GlassMaterial(${colorRole.name}, radius $cornerRadius, '
      'refracts $refracts)';
}
