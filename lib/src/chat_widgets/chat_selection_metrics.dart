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
  /// Message **span** multi-select only.
  static const double autoScrollEdgeBand = 56;

  /// Auto-scroll distance per vsync frame (logical px).
  /// Message **span** multi-select only.
  static const double autoScrollPixelsPerFrame = 12;

  /// Mobile text-selection soft arm band (logical px).
  ///
  /// Same depth as [spanSlop] / touch slop. The markdown package also ramps
  /// into the content over this band; reference clients arm only past the pad
  /// — exterior-only arming would need a markdown-package knob.
  static const double textAutoScrollEdgeZoneMobile = 8;

  /// Desktop text-selection soft arm band (logical px).
  static const double textAutoScrollEdgeZoneDesktop = 8;

  /// Mobile text-selection auto-scroll distance per vsync frame (logical px).
  ///
  /// Half of a typical 16sp body line (`lineHeight >> 1` ≈ 9). Converted to
  /// px/s as `pixelsPerFrame × displayRefreshHz`.
  static const double textAutoScrollPixelsPerFrame = 9;

  /// Desktop text-selection timer period (ms) for the near-edge product.
  static const int textAutoScrollSpeedIntervalMs = 15;

  /// Desktop pixels scrolled per [textAutoScrollSpeedIntervalMs] when the
  /// pointer sits ~20px past the edge (`delta×3/20+1` → 4).
  static const double textAutoScrollDesktopPixelsPerTick = 4;

  /// Desktop absolute max velocity (logical px/s).
  ///
  /// Fixed timer product — do **not** multiply by display Hz.
  static const double textAutoScrollDesktopMaxVelocity =
      textAutoScrollDesktopPixelsPerTick *
      (1000 / textAutoScrollSpeedIntervalMs);

  /// Horizontal checkbox slot width (logical px).
  static const double slotWidth = 35;

  /// Checkbox diameter on the message cell (logical px).
  static const double checkSize = 21;

  /// Trailing edge margin for the selection checkbox under desktop policy.
  static const double checkTrailingMargin = 12;

  /// Selection-mode chrome show/hide duration.
  static const Duration modeDuration = Duration(milliseconds: 200);

  /// Per-checkbox select/deselect animation duration.
  static const Duration selectDuration = Duration(milliseconds: 200);
}
