/// How much of the glass effect the host allows a surface to draw.
///
/// A ceiling, not a guarantee: the backend may offer less (see
/// `GlassCapabilities`), and a surface drops to a flat fill while its route
/// moves where filtering the scene would cost frames. Ordered from richest to
/// cheapest.
enum GlassQuality {
  /// Frosted backdrop with edge refraction (the liquid look).
  fullLiquid,

  /// Frosted backdrop without refraction.
  frosted,

  /// The material's tint as a solid fill, with its strokes and shadow. No
  /// backdrop is read.
  flat,

  /// Nothing is drawn behind the child: no fill, strokes or shadow.
  off,
}
