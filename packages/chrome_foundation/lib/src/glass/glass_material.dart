import 'dart:ui' show Offset;

/// A named glass preset.
///
/// A material fixes what does not vary with the theme: its corners, edge
/// widths and shadow geometry. Its colours come from `GlassMaterialTokens` in
/// the chrome theme scope, so one brightness mechanism drives it, and the
/// effect behind it (blur, saturation, refraction, tint opacity) follows the
/// host's `GlassQuality`. Pick a material by role and let the theme and the
/// quality decide the rest; there are no per-widget glass flags.
enum GlassMaterial {
  /// The composer input island: a stadium at the default radius on a 44 dp
  /// island.
  composerIsland(
    cornerRadius: 22,
    strokeWidth: 0.5,
    shadowBlur: 1,
    shadowOffset: Offset(0, 1 / 3),
  ),

  /// Round or pill buttons floating over a panel; pass `cornerRadius` of half
  /// the button size for a circle. Casts the deepest shadow.
  panelButton(
    cornerRadius: 18,
    strokeWidth: 0.5,
    shadowBlur: 11 / 3,
    shadowOffset: Offset(0, 2 / 3),
  ),

  /// A bar docked at the top edge of a panel: square corners, never
  /// refracting.
  topPanel(
    cornerRadius: 0,
    strokeWidth: 0.55,
    shadowBlur: 1,
    shadowOffset: Offset(0, 1 / 3),
    refracts: false,
  ),

  /// The message menu and its reaction strip over a dimmed screen: 12 dp
  /// corners, 2/3 dp edges, a soft 3.5 dp shadow all round, and a blur
  /// stronger than the frosted one (80 dp), never refracting. Its tint
  /// opacity, edges, shadow and backdrop saturation follow the theme's
  /// brightness (`GlassMaterialColors`).
  messageMenu(
    cornerRadius: 12,
    strokeWidth: 2 / 3,
    shadowBlur: 3.5,
    shadowOffset: Offset.zero,
    refracts: false,
    blurRadius: 80,
  );

  const GlassMaterial({
    required this.cornerRadius,
    required this.strokeWidth,
    required this.shadowBlur,
    required this.shadowOffset,
    this.refracts = true,
    this.blurRadius,
  });

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
}
