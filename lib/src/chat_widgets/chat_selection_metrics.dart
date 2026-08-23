import 'package:flutter/foundation.dart';

/// Selection gesture and chrome metrics for message multi-select.
///
/// Keep gesture, chrome, and auto-scroll numbers in one place so they
/// cannot drift independently across hosts.
@immutable
abstract final class ChatSelectionMetrics {
  /// Long-press duration before selection mode arms.
  static const Duration longPressTimeout = Duration(milliseconds: 500);

  /// Touch slop after long-press, in logical pixels.
  /// Past this distance, the span starts tracking.
  static const double spanSlop = 8;

  /// Auto-scroll edge band from each padded viewport edge (logical px).
  static const double autoScrollEdgeBand = 56;

  /// Auto-scroll distance per vsync frame (logical px).
  static const double autoScrollPixelsPerFrame = 12;

  /// Horizontal checkbox slot width (logical px).
  static const double slotWidth = 35;

  /// Checkbox diameter on the message cell (logical px).
  static const double checkSize = 21;

  /// Selection-mode chrome show/hide duration.
  static const Duration modeDuration = Duration(milliseconds: 200);

  /// Per-checkbox select/deselect animation duration.
  static const Duration selectDuration = Duration(milliseconds: 200);
}
