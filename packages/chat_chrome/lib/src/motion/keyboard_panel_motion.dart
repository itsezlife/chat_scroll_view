import 'package:flutter/animation.dart';

/// Keyboard / keyboard-panel open-close motion tokens.
abstract final class KeyboardPanelMotion {
  /// Panel / IME pan duration — 250ms.
  static const Duration duration = Duration(milliseconds: 250);

  /// Delayed start before cold open animation.
  static const Duration startDelay = Duration(milliseconds: 50);

  /// Search-field open/close duration (220ms).
  static const Duration searchDuration = Duration(milliseconds: 220);

  /// Panel height expand/collapse for emoji search (300ms).
  static const Duration searchExpandDuration = Duration(milliseconds: 300);

  /// Extra height above the keyboard-sized panel while searching (175 dp).
  static const double searchExpandExtra = 175;

  /// Strip hide distance while search is open (slides up 40 dp).
  static const double searchStripHide = 40;

  /// Restartable emoji keyword search debounce.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  /// Delay before the leading search icon shows progress.
  static const Duration searchProgressDelay = Duration(milliseconds: 65);

  /// Search icon morph duration (350ms, [Curves.easeOutQuint]).
  static const Duration searchIconMorphDuration = Duration(milliseconds: 350);

  /// Strip / search shadow fade (200ms, [Curves.easeOut]).
  static const Duration shadowDuration = Duration(milliseconds: 200);

  /// Reselect type-tab strip restore (150ms, [Curves.easeOutQuint]).
  static const Duration reselectStripDuration = Duration(milliseconds: 150);

  /// List-style cubic used for panel progress.
  static const Cubic curve = Cubic(
    0.19919472913616398,
    0.010644531250000006,
    0.27920937042459737,
    0.91025390625,
  );
}
