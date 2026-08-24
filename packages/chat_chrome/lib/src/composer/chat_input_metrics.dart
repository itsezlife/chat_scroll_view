/// Layout metrics for the composer input island.
///
/// Paint sizes — not outer hit boxes.
///
/// **Radius vs height:** `bubbleRadius` is 22 because the idle island height is
/// 44 (`DEFAULT_HEIGHT`). Half of height → stadium / capsule ends. Raising the
/// radius alone does not match Telegram; a taller Flutter island with the same
/// 22 reads as “less round.” Keep single-line height at [islandHeight].
abstract final class ChatInputMetrics {
  /// Idle glass island height (`DEFAULT_HEIGHT` / `defaultIslandHeight`).
  static const double islandHeight = 44;

  /// Glass corner radius (`INPUT_BUBBLE_RADIUS`).
  ///
  /// With [islandHeight] 44 this is a full pill (`radius == height / 2`).
  static const double bubbleRadius = 22;

  /// Under-keyboard / emoji panel top radius (`INPUT_KEYBOARD_RADIUS`).
  static const double keyboardRadius = 29;

  /// Gap between island bottom and keyboard/panel top (`INPUT_BUBBLE_BOTTOM`).
  static const double bubbleBottomGap = 9;

  /// Horizontal glass inset / island margin (`setPadding(dp(7))`).
  static const double bubblePadding = 7;
}
