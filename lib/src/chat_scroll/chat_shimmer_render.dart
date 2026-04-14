import 'dart:ui';

/// Shared shimmer render for unfetched message slots.
///
/// A single instance is reused for all empty slots — no per-slot state,
/// no layers, no [Picture]. The viewport paints shimmers directly
/// on the canvas, reusing the same shader across all visible slots.
abstract class ChatShimmerRender {
  /// Compute the height of one shimmer row for [availableWidth].
  /// Called once per layout pass when width changes.
  double performLayout(double availableWidth);

  /// Paint one shimmer row onto [canvas] within [size].
  void paint(Canvas canvas, Size size);
}
