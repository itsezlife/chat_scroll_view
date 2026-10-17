import 'dart:developer' as dev;

import 'package:flutter/painting.dart';

/// Set to `true` to log selection-handle drag updates.
///
/// Leave `false` in normal use — the logs are noisy (one line per drag update).
bool debugLogExtendedTextSelectionHandles = false;

/// Logs one selection-debug line when [debugLogExtendedTextSelectionHandles].
void debugLogExtendedSelection(String message) {
  if (!debugLogExtendedTextSelectionHandles) {
    return;
  }
  dev.log(message, name: 'ext_sel');
}

/// Compact selection dump for logs.
String debugSelectionSummary(TextSelection selection) {
  final bool reversed = selection.extentOffset < selection.baseOffset;
  return 'base=${selection.baseOffset} extent=${selection.extentOffset} '
      'start=${selection.start} end=${selection.end} '
      'affinity=${selection.affinity.name} '
      'collapsed=${selection.isCollapsed} reversed=$reversed';
}

/// Finger-tracked moving-handle delta dump for scroll-edge diagnostics.
String debugFingerTrackedDeltaSummary({
  required Offset pointerGlobal,
  required Offset overlayLocal,
  required Offset leaderLocal,
  required Offset delta,
  required bool wouldClamp,
  double? scrollPixels,
}) {
  String xy(Offset o) =>
      '(${o.dx.toStringAsFixed(1)},${o.dy.toStringAsFixed(1)})';
  final String scroll = scrollPixels?.toStringAsFixed(1) ?? 'n/a';
  return 'fingerTracked: pointer=${xy(pointerGlobal)} '
      'overlay=${xy(overlayLocal)} leader=${xy(leaderLocal)} '
      'delta=${xy(delta)} wouldClamp=$wouldClamp scroll=$scroll';
}
