/// Layout metrics for the composer input island.
///
/// Paint sizes — not outer hit boxes.
///
/// **Radius vs height:** `bubbleRadius` is 22 because the idle island height is
/// 44. Half of height → stadium / capsule ends. A taller island with the same
/// 22 reads as less round. Keep single-line height at [islandHeight].
abstract final class ChatInputMetrics {
  /// Idle glass island height.
  static const double islandHeight = 44;

  /// Glass corner radius.
  ///
  /// With [islandHeight] 44 this is a full pill (`radius == height / 2`).
  static const double bubbleRadius = 22;

  /// Under-keyboard / keyboard-panel top radius.
  static const double keyboardRadius = 29;

  /// Gap between island bottom and keyboard/panel top.
  static const double bubbleBottomGap = 9;

  /// Horizontal glass inset / island margin.
  static const double bubblePadding = 7;
}
