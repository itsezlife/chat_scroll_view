import 'package:flutter/animation.dart';

/// Keyboard / keyboard-panel open-close motion tokens.
abstract final class KeyboardPanelMotion {
  /// Panel / IME pan duration — 250ms.
  static const Duration duration = Duration(milliseconds: 250);

  /// Delayed start before cold open animation.
  static const Duration startDelay = Duration(milliseconds: 50);

  /// Search-field open/close duration (`openSearch` / 220ms).
  static const Duration searchDuration = Duration(milliseconds: 220);

  /// Panel height expand/collapse for emoji search (`setStickersExpanded` / 300ms).
  static const Duration searchExpandDuration = Duration(milliseconds: 300);

  /// Extra height above the keyboard-sized panel while searching (`dp(175)`).
  static const double searchExpandExtra = 175;

  /// Strip hide distance while search is open (`−dp(40)`).
  static const double searchStripHide = 40;

  /// Restartable emoji keyword search debounce (`EmojiSearchAdapter.search`).
  static const Duration searchDebounce = Duration(milliseconds: 300);

  /// Delay before leading search icon shows progress (`SearchStateDrawable`).
  static const Duration searchProgressDelay = Duration(milliseconds: 65);

  /// Search icon morph duration (`SearchStateDrawable` / 350ms EASE_OUT_QUINT).
  static const Duration searchIconMorphDuration = Duration(milliseconds: 350);

  /// Strip / search shadow fade (`BoolAnimator` 200ms EASE_OUT).
  static const Duration shadowDuration = Duration(milliseconds: 200);

  /// Reselect type-tab strip restore (`150ms` EASE_OUT_QUINT).
  static const Duration reselectStripDuration = Duration(milliseconds: 150);

  /// List-style cubic used for panel progress.
  static const Cubic curve = Cubic(
    0.19919472913616398,
    0.010644531250000006,
    0.27920937042459737,
    0.91025390625,
  );
}
