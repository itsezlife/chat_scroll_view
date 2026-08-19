import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_dev_log.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Edge inset when clamping menu X.
const double kChatMessageMenuEdgeInset = 16;

/// Extra left bias from the tap.
const double kChatMessageMenuTouchBias = 28;

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
  double reactionsExtent = 0,
}) {
  final tap = tapGlobal ?? messageRect.center;
  final kb = keyboardHeight < 0 ? 0.0 : keyboardHeight;
  final bottomInset = kb > safePadding.bottom ? kb : safePadding.bottom;
  final bottom = screenSize.height - bottomInset;

  final minX = kChatMessageMenuEdgeInset + safePadding.left;
  final maxX = math.max(
    minX,
    screenSize.width -
        kChatMessageMenuEdgeInset -
        safePadding.right -
        menuSize.width,
  );
  final rawX = tap.dx - menuSize.width - kChatMessageMenuTouchBias;
  const pinEnd = false;
  final menuX = minX;
  const xBranch = 'leadingInset';

  final minY = safePadding.top + 24;
  final clampHeight = menuSize.height + kChatMessageMenuClampHeightPad;
  final maxY = math.max(minY, bottom - clampHeight - 8);
  final yNudged = tap.dy + kChatMessageMenuTallThreshold - clampHeight;

  var menuY = tap.dy;
  var yBranch = 'atTap';
  if (clampHeight > kChatMessageMenuTallThreshold) {
    menuY = yNudged;
    yBranch = 'tallNudge';
  }

  final usableHeight = screenSize.height - safePadding.top - bottomInset;
  if (clampHeight >= usableHeight) {
    menuY = safePadding.top;
    yBranch = 'fitsScreenTop';
  } else {
    final clamped = menuY.clamp(minY, maxY);
    if (clamped != menuY) yBranch = '$yBranch+clamp';
    menuY = clamped.toDouble();
  }

  final fitsAbove = menuY + menuSize.height / 2 <= tap.dy;
  final origin = Offset(menuX, menuY);
  final menuRect = origin & menuSize;

  logChatMessageMenu('place', {
    'screen': ChatMessageMenuLogFormat.size(screenSize),
    'kb': DevLogFormat.f(kb),
    'bottomInset': DevLogFormat.f(bottomInset),
    'safe': ChatMessageMenuLogFormat.insets(safePadding),
    'message': ChatMessageMenuLogFormat.rect(messageRect),
    'tap': ChatMessageMenuLogFormat.offset(tap),
    'menuSize': ChatMessageMenuLogFormat.size(menuSize),
    'reactionsExtent': DevLogFormat.f(reactionsExtent),
    'rawX': DevLogFormat.f(rawX),
    'minX': DevLogFormat.f(minX),
    'maxX': DevLogFormat.f(maxX),
    'alignEnd': false,
    'pinEnd': pinEnd,
    'xBranch': xBranch,
    'menuX': DevLogFormat.f(menuX),
    'minY': DevLogFormat.f(minY),
    'maxY': DevLogFormat.f(maxY),
    'clampH': DevLogFormat.f(clampHeight),
    'usableH': DevLogFormat.f(usableHeight),
    'yNudged': DevLogFormat.f(yNudged),
    'yBranch': yBranch,
    'menuY': DevLogFormat.f(menuY),
    'origin': ChatMessageMenuLogFormat.offset(origin),
    'menuRect': ChatMessageMenuLogFormat.rect(menuRect),
    'fitsAbove': fitsAbove,
    'overlapMsg': menuRect.overlaps(messageRect),
    'tapToMenuRight': DevLogFormat.f(tap.dx - menuRect.right),
    'rightGap': DevLogFormat.f(
      screenSize.width - safePadding.right - menuRect.right,
    ),
  });

  return ChatMessageMenuPlacement(menuOrigin: origin, fitsAbove: fitsAbove);
}
