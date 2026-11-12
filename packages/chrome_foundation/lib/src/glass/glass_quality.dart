/// How much of the glass effect the host allows a surface to draw.
///
/// A ceiling, not a guarantee: the backend may offer less (see
/// `GlassCapabilities`), and a surface drops to a flat fill while its route
/// moves where filtering the scene would cost frames. Ordered from richest to
/// cheapest.
enum GlassQuality {
  /// A lightly blurred backdrop bent at the rim (the liquid look), under a
  /// tint at 0.85. Needs fragment shaders; frosted where they do not load.
  fullLiquid,

  /// A strongly blurred, saturated backdrop under a tint at 0.76. The
  /// default.
  frosted,

  /// The material's tint as an opaque fill, with its strokes and shadow. No
  /// backdrop is read.
  flat,

  /// Nothing is drawn behind the child: no fill, strokes or shadow.
  off,
}
