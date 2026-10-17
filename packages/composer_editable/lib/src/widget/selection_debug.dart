import 'dart:developer' as dev;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'selection_boxes.dart';

/// Set to `true` to log selection-handle drag and exclusive-end chrome.
///
/// Useful while debugging soft-wrap / affinity / empty-edge regressions.
/// Leave `false` in normal use — logs are noisy (drag updates + hybrid rebuilds).
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

/// Exclusive-end chrome decision for [selection.end].
String debugExclusiveEndChromeSummary({
  required TextSelection selection,
  required ExclusiveLineEndKind? endKind,
}) {
  final bool emptyEdge =
      endKind != null && exclusiveEndUsesEmptyEdge(selection);
  final String style = switch ((endKind, emptyEdge)) {
    (null, _) => 'n/a',
    (_, true) => 'max+emptyEdge',
    (_, false) => 'tight+contentLine',
  };
  return 'exclEnd=${endKind?.name ?? 'none'} emptyEdge=$emptyEdge '
      'chrome=$style affinity=${selection.affinity.name}';
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

/// Short hybrid box dump (first/last rect).
String debugSelectionBoxesSummary(List<ui.TextBox> boxes) {
  if (boxes.isEmpty) {
    return 'boxes=0';
  }
  final ui.TextBox first = boxes.first;
  final ui.TextBox last = boxes.last;
  if (boxes.length == 1) {
    return 'boxes=1 '
        'box=(${first.left.toStringAsFixed(1)},${first.top.toStringAsFixed(1)})-'
        '(${first.right.toStringAsFixed(1)},${first.bottom.toStringAsFixed(1)})';
  }
  return 'boxes=${boxes.length} '
      'first=(${first.left.toStringAsFixed(1)},${first.top.toStringAsFixed(1)})-'
      '(${first.right.toStringAsFixed(1)},${first.bottom.toStringAsFixed(1)}) '
      'last=(${last.left.toStringAsFixed(1)},${last.top.toStringAsFixed(1)})-'
      '(${last.right.toStringAsFixed(1)},${last.bottom.toStringAsFixed(1)})';
}

/// Resolves exclusive-end kind at [offset] via [lineAtOffset] + [plainText].
ExclusiveLineEndKind? debugExclusiveEndKindAt({
  required int offset,
  required String plainText,
  required TextSelection Function(int offset) lineAtOffset,
}) {
  return exclusiveLineEndKind(
    offset: offset,
    plainText: plainText,
    lineAtOffset: lineAtOffset,
  );
}
