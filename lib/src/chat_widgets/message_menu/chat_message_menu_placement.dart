import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_presentation.dart';
import 'package:chat_scroll_view/src/chat_widgets/message_menu/chat_message_menu_reactions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Computed placement for the message-menu stack.
@immutable
final class ChatMessageMenuPlacement {
  /// Creates a placement.
  const ChatMessageMenuPlacement({
    required this.menuOrigin,
    required this.fitsAbove,
  });

  /// Positions the menu from the tap, clamped above the IME and safe insets.
  ///
  /// Slot rects are full rows and can be taller/wider than the screen, so
  /// **Y follows the tap**, not `messageRect.top`.
  ///
  /// - **X ([ChatMessageMenuPresentation.sheet]):** the menu hangs to the
  ///   left of the press. The box its action card sits in (the card, a
  ///   [cardShadowInset] around it, and the reaction strip's margins
  ///   [reactionsCardStart] / [reactionsCardEnd] beside it when
  ///   [hasReactions]) ends [sheetPressGap] left of the press, kept
  ///   [sheetScreenInset] inside the screen and its safe insets. The card is
  ///   taken to sit in [menuSize] as the default column lays it out
  ///   ([ChatMessageMenuReactions.startOverhang] /
  ///   [ChatMessageMenuReactions.endOverhang] beside it). Outgoing vs
  ///   incoming does not change X.
  /// - **X ([ChatMessageMenuPresentation.popup]):** follows the tap, clamped
  ///   into the overlay so a desktop/web pointer menu stays near the cursor.
  /// - **Y:** start at tap Y; if the stack is taller than 240dp, shift up by
  ///   `240 - (height + 48)`; then clamp into the overlay.
  factory ChatMessageMenuPlacement.compute({
    required Size screenSize,
    required double keyboardHeight,
    required Rect messageRect,
    required Size menuSize,
    Offset? tapGlobal,
    EdgeInsets safePadding = EdgeInsets.zero,
    ChatMessageMenuPresentation presentation =
        ChatMessageMenuPresentation.sheet,
    bool hasReactions = false,
  }) {
    final tap = tapGlobal ?? messageRect.center;
    final kb = keyboardHeight < 0 ? 0.0 : keyboardHeight;
    final bottomInset = kb > safePadding.bottom ? kb : safePadding.bottom;
    final bottom = screenSize.height - bottomInset;

    final minX = edgeInset + safePadding.left;
    final maxX = math.max(
      minX,
      screenSize.width - menuSize.width - edgeInset - safePadding.right,
    );
    final menuX = switch (presentation) {
      ChatMessageMenuPresentation.sheet => _sheetX(
        tap: tap.dx,
        menuWidth: menuSize.width,
        screenWidth: screenSize.width,
        safePadding: safePadding,
        hasReactions: hasReactions,
      ),
      ChatMessageMenuPresentation.popup => tap.dx.clamp(minX, maxX).toDouble(),
    };

    final minY = safePadding.top + 24;
    final clampHeight = menuSize.height + clampHeightPad;
    final maxY = math.max(minY, bottom - clampHeight - 8);
    final yNudged = tap.dy + tallThreshold - clampHeight;

    var menuY = tap.dy;
    if (clampHeight > tallThreshold) {
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

  static double _sheetX({
    required double tap,
    required double menuWidth,
    required double screenWidth,
    required EdgeInsets safePadding,
    required bool hasReactions,
  }) {
    const columnStart = ChatMessageMenuReactions.startOverhang;
    const columnEnd = ChatMessageMenuReactions.endOverhang;
    final cardWidth = math.max(0, menuWidth - columnStart - columnEnd);
    final cardStart = cardShadowInset + (hasReactions ? reactionsCardStart : 0);
    final cardEnd = cardShadowInset + (hasReactions ? reactionsCardEnd : 0);
    final boxWidth = cardWidth + cardStart + cardEnd;
    final minLeft = sheetScreenInset + safePadding.left;
    final maxLeft = math.max(
      minLeft,
      screenWidth - sheetScreenInset - safePadding.right - boxWidth,
    );
    final boxLeft = (tap - sheetPressGap - boxWidth)
        .clamp(minLeft, maxLeft)
        .toDouble();
    return boxLeft + cardStart - columnStart;
  }

  /// Edge inset when clamping a popup's X.
  static const double edgeInset = 16;

  /// How far left of the press a sheet's card box ends.
  static const double sheetPressGap = 20;

  /// How far inside the screen a sheet's card box stays.
  static const double sheetScreenInset = 6;

  /// The room around a sheet's action card inside its box.
  static const double cardShadowInset = 8;

  /// The reaction strip's margin before a sheet's action card.
  static const double reactionsCardStart = 16;

  /// The reaction strip's margin after a sheet's action card.
  static const double reactionsCardEnd = 36;

  /// Tall-menu nudge threshold.
  static const double tallThreshold = 240;

  /// Extra height added to the clamp budget (`measuredHeight + 48`).
  static const double clampHeightPad = 48;

  /// Top-left of the reactions + action column in overlay coordinates.
  final Offset menuOrigin;

  /// Whether the stack sits mostly above the message (leave animation sign).
  final bool fitsAbove;
}
