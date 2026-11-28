import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:panel_presentation/panel_presentation.dart';

/// Carries out the composer's keyboard intent through the panel
/// presentation: the composer only states it, and knows no panel.
///
/// - `hold`: the keyboard goes down (focus stays on the field) and the
///   keyboard slot keeps its height occupied, so the composer does not drop
///   under the surface over it.
/// - `keep` and `hide`: the hold ends. A keyboard the composer reopened
///   takes the held height over; one that stays down lets the slot shrink
///   over [shrink].
final class ComposerKeyboardIntentHost {
  /// Follows [composer]'s intent, holding [keyboard]'s occupancy and
  /// lowering the soft keyboard through [hideKeyboard]; [shrink] defaults
  /// to the standard `listTransition` role.
  ComposerKeyboardIntentHost({
    required this.composer,
    required this.keyboard,
    required this.hideKeyboard,
    MotionSpec? shrink,
  }) : shrink = shrink ?? const ChromeMotion.standard().listTransition {
    composer.keyboardIntent.addListener(_onIntent);
    _onIntent();
  }

  /// The composer whose intent is carried out.
  final ComposerController composer;

  /// The slot whose occupancy a hold keeps.
  final KeyboardReplacementStrategy keyboard;

  /// Lowers the soft keyboard, leaving focus where it is, saying why.
  final Future<void> Function(String why) hideKeyboard;

  /// The motion a released hold shrinks over when the keyboard stays down.
  final MotionSpec shrink;

  KeyboardOccupancyHold? _hold;
  var _disposed = false;

  void _onIntent() {
    if (_disposed) return;
    switch (composer.keyboardIntent.value) {
      case ComposerKeyboardIntent.hold:
        // Held before the keyboard goes, so the height it leaves is kept.
        _hold ??= keyboard.holdOccupancy(shrink);
        unawaited(hideKeyboard('a surface over the composer holds it'));
      case ComposerKeyboardIntent.keep || ComposerKeyboardIntent.hide:
        _release();
    }
  }

  void _release() {
    _hold?.release();
    _hold = null;
  }

  /// Stops following the composer and ends a hold under way. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    composer.keyboardIntent.removeListener(_onIntent);
    _release();
  }
}
