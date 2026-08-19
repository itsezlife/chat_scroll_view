import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Edge inset when clamping menu X.
const double kChatMessageMenuEdgeInset = 16;

/// Tall-menu nudge threshold.
const double kChatMessageMenuTallThreshold = 240;

/// Extra height added to the clamp budget (`measuredHeight + 48`).
const double kChatMessageMenuClampHeightPad = 48;

/// Computed placement for the message-menu stack.
@immutable
final class ChatMessageMenuPlacement {
  /// Creates a placement.
  const ChatMessageMenuPlacement({
    required this.menuOrigin,
    required this.fitsAbove,
  });

  /// Top-left of the reactions + action column in overlay coordinates.
  final Offset menuOrigin;

  /// Whether the stack sits mostly above the message (leave animation sign).
  final bool fitsAbove;
}

/// Positions the menu from the tap, clamped above the IME and safe insets.
///
/// Slot rects are full rows and can be taller/wider than the screen, so
/// **Y follows the tap** (`ChatActivity.createMenu` `popupY = listY +
/// cellTop + tapY`), not `messageRect.top`.
///
/// - **X:** always the leading inset ([kChatMessageMenuEdgeInset]). Telegram's window is that
///   outer box; the action card is then inset 16/36 under a wider
///   reactions strip (`ChatScrimPopupContainerLayout`). Outgoing vs
///   incoming does not change X.
/// - **Y:** start at tap Y; if the stack is taller than 240dp, shift up by
///   `240 - (height + 48)`; then clamp into the overlay.
ChatMessageMenuPlacement computeChatMessageMenuPlacement({
  required Size screenSize,
  required double keyboardHeight,
  required Rect messageRect,
  required Size menuSize,
  Offset? tapGlobal,
  EdgeInsets safePadding = EdgeInsets.zero,
}) {
  final tap = tapGlobal ?? messageRect.center;
  final kb = keyboardHeight < 0 ? 0.0 : keyboardHeight;
  final bottomInset = kb > safePadding.bottom ? kb : safePadding.bottom;
  final bottom = screenSize.height - bottomInset;

  final menuX = kChatMessageMenuEdgeInset + safePadding.left;

  final minY = safePadding.top + 24;
  final clampHeight = menuSize.height + kChatMessageMenuClampHeightPad;
  final maxY = math.max(minY, bottom - clampHeight - 8);
  final yNudged = tap.dy + kChatMessageMenuTallThreshold - clampHeight;

  var menuY = tap.dy;
  if (clampHeight > kChatMessageMenuTallThreshold) {
    menuY = yNudged;
  }

  final usableHeight = screenSize.height - safePadding.top - bottomInset;
  if (clampHeight >= usableHeight) {
    menuY = safePadding.top;
  } else {
    menuY = menuY.clamp(minY, maxY).toDouble();
  }

  final fitsAbove = menuY + menuSize.height / 2 <= tap.dy;
  return ChatMessageMenuPlacement(
    menuOrigin: Offset(menuX, menuY),
    fitsAbove: fitsAbove,
  );
}
