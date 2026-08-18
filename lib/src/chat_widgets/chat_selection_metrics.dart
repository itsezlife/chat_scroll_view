import 'package:flutter/foundation.dart';

/// Telegram Android selection tokens (ChatMessageCell, CheckBoxBase,
/// RecyclerListView.startMultiselect).
///
/// Keep gesture, chrome, and auto-scroll numbers in one place so they
/// cannot drift independently of the reference client.
@immutable
abstract final class ChatSelectionMetrics {
  /// [ViewConfiguration.getLongPressTimeout] default (ms).
  static const Duration longPressTimeout = Duration(milliseconds: 500);

  /// [ViewConfiguration.getScaledTouchSlop] default, in logical pixels.
  /// Past this distance after long-press, the span starts tracking.
  static const double spanSlop = 8;

  /// `RecyclerListView` edge band: `dp(56)` from each padded edge.
  static const double autoScrollEdgeBand = 56;

  /// `RecyclerListView` scroller: `dp(12)` per vsync.
  static const double autoScrollPixelsPerFrame = 12;

  /// `ChatMessageCell` checkbox translation: `dp(35)`.
  static const double slotWidth = 35;

  /// `CheckBoxBase(this, 21)` on the message cell.
  static const double checkSize = 21;

  /// `ChatMessageCell` checkbox show/hide: `dt / 200.0f`.
  static const Duration modeDuration = Duration(milliseconds: 200);

  /// `CheckBoxBase.animationDuration` default.
  static const Duration selectDuration = Duration(milliseconds: 200);
}
