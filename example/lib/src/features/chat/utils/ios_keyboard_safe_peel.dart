import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Home-indicator band remaining in a bottom chrome term on iOS.
///
/// Soft keyboard / panel extent excludes [safeBottom]; hosts add it in the
/// keyboard slot and in composer [ChatViewportInsets] reserve while idle.
/// As [keyboard] occupancy rises toward [keyboardTarget], peel safe
/// proportionally (`keyboard / target`) so open chrome does not double-count
/// the band — synced with slot layout, not a step at `keyboard > 0`.
///
/// Returns full [safeBottom] when [keyboard] is zero or the platform is not
/// iOS. Android keeps full [safeBottom] (nav inset often merges into IME).
double iosKeyboardSafeBandPeel({
  required double safeBottom,
  required double keyboard,
  required double keyboardTarget,
}) {
  if (safeBottom <= 0) return 0;
  if (defaultTargetPlatform != TargetPlatform.iOS) return safeBottom;
  if (keyboard <= 0) return safeBottom;

  final target = keyboardTarget > 0 ? keyboardTarget : keyboard;
  if (target <= 0) return safeBottom;

  final peel = (keyboard / target).clamp(0.0, 1.0);
  return safeBottom * (1 - peel);
}

/// Resolves keyboard open target for [iosKeyboardSafeBandPeel].
double iosKeyboardOpenTarget({
  required double keyboard,
  required double panelTarget,
  required double storedKeyboardHeight,
}) => math.max(keyboard, math.max(panelTarget, storedKeyboardHeight));
