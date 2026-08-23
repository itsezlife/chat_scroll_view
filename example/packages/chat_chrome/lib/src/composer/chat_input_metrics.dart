/// Layout metrics for the composer input island.
///
/// Paint sizes — not outer hit boxes.
abstract final class ChatInputMetrics {
  /// Glass input island corner radius (`INPUT_BUBBLE_RADIUS`).
  static const double bubbleRadius = 28;

  /// Under-keyboard / emoji panel top radius (`INPUT_KEYBOARD_RADIUS`).
  static const double keyboardRadius = 29;

  /// Gap between island bottom and keyboard/panel top (`INPUT_BUBBLE_BOTTOM`).
  static const double bubbleBottomGap = 9;

  /// Horizontal glass inset / island margin (`setPadding(dp(7))`).
  static const double bubblePadding = 7;
}
