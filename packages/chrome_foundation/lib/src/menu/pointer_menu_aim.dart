import 'dart:ui' show Offset;

/// Aim protection of a submenu: while the pointer travels from the row that
/// opened it toward it, the rows it crosses on the way do not take the
/// highlight.
///
/// The widget keeps the apex (the pointer, moved along as it stays inside) and
/// a timer of `PointerMenuTiming.aimHold` that ends the hold when the pointer
/// pauses; this is the geometry.
abstract final class PointerMenuAim {
  /// Whether [point] is inside the triangle of [apex] and the submenu's near
  /// edge from [edgeTop] to [edgeBottom], borders included.
  static bool contains({
    required Offset apex,
    required Offset edgeTop,
    required Offset edgeBottom,
    required Offset point,
  }) {
    double side(Offset a, Offset b, Offset p) =>
        (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
    final d1 = side(apex, edgeTop, point);
    final d2 = side(edgeTop, edgeBottom, point);
    final d3 = side(edgeBottom, apex, point);
    final negative = d1 < 0 || d2 < 0 || d3 < 0;
    final positive = d1 > 0 || d2 > 0 || d3 > 0;
    return !(negative && positive);
  }
}
