/// Runtime switches for scroll-smoothness experiments. Not a stable API:
/// these exist to A/B a change on a device before it is designed in.
abstract final class ChatScrollExperiments {
  /// Whether the viewport rounds every row's paint origin to a whole
  /// physical pixel, as a platform list that scrolls in integer pixels does.
  /// The row's content then keeps one sub-pixel phase while it moves.
  static bool snapRowsToPhysicalPixels = false;
}
