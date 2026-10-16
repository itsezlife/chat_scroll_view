/// A named glass preset.
///
/// A material fixes what does not vary with the theme: the shape of the
/// effect (blur, saturation, refraction, stroke widths). Its colours come
/// from `GlassMaterialTokens` in the chrome theme scope, so one brightness
/// mechanism drives it. Pick a material by role and let the theme and the
/// host's `GlassQuality` decide the rest; there are no per-widget glass flags.
enum GlassMaterial {
  /// The composer input island: refracting, rounded to a stadium at the
  /// default radius.
  composerIsland(cornerRadius: 22),

  /// Round or pill buttons floating over a panel; pass `cornerRadius` of half
  /// the button size for a circle.
  panelButton(cornerRadius: 22),

  /// A bar docked at the top edge of a panel: frosted, square corners.
  topPanel(cornerRadius: 0);

  const GlassMaterial({required this.cornerRadius});

  /// The corner radius (logical px) used when a surface names none.
  final double cornerRadius;
}
