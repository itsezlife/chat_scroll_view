import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Kind of exclusive selection end that sits at a visual line start.
enum ExclusiveLineEndKind {
  /// Previous character is not `\n` (soft wrap).
  softWrap,

  /// Previous character is `\n` (hard line break).
  hardBreak,
}

/// Classifies an exclusive selection end at the start of a visual line.
///
/// Returns null when [offset] is not the start of a line after selected
/// content on a previous line.
ExclusiveLineEndKind? exclusiveLineEndKind({
  required int offset,
  required String plainText,
  required TextSelection Function(int offset) lineAtOffset,
}) {
  if (offset <= 0 || offset >= plainText.length) {
    return null;
  }
  final TextSelection lineAt = lineAtOffset(offset);
  final TextSelection lineBefore = lineAtOffset(offset - 1);
  if (lineAt.start != offset || lineAt.start == lineBefore.start) {
    return null;
  }
  return plainText.codeUnitAt(offset - 1) == 0x0A
      ? ExclusiveLineEndKind.hardBreak
      : ExclusiveLineEndKind.softWrap;
}

/// Whether an exclusive end should use empty-edge handle + full-width paint.
///
/// [TextSelection.affinity] is exclusive-end affinity at `selection.end`:
/// [TextAffinity.downstream] → next-line empty edge + `max`;
/// [TextAffinity.upstream] → last glyph on the content line + `tight`.
///
/// Callers already gate on [exclusiveLineEndKind]. When the exclusive end is
/// fixed base of a handle drag (start or end), preserve drag-start affinity —
/// do not flip empty-edge from the moving handle's hit-test.
bool exclusiveEndUsesEmptyEdge(TextSelection selection) {
  return selection.affinity == TextAffinity.downstream;
}

/// Whether handle-drag should preserve exclusive-end affinity from drag-start.
///
/// True only when [fixedBase] is an exclusive line end **and** it is
/// `selection.end` for this update (`extent <= fixedBase`). A fixed start that
/// merely sits at a visual line start must not freeze affinity while the
/// exclusive end is still the moving extent.
bool preserveExclusiveEndAffinityOnHandleDrag({
  required bool fixedBaseIsExclusiveLineEnd,
  required int fixedBase,
  required int extent,
}) {
  return fixedBaseIsExclusiveLineEnd && extent <= fixedBase;
}

/// Affinity for a handle-drag update.
///
/// When [fixedBaseIsExclusiveEnd] is true (see
/// [preserveExclusiveEndAffinityOnHandleDrag]), keep [dragStartAffinity].
/// Otherwise use [hitTestAffinity] from the moving handle.
TextAffinity affinityForHandleDrag({
  required bool fixedBaseIsExclusiveEnd,
  required TextAffinity dragStartAffinity,
  required TextAffinity hitTestAffinity,
}) {
  return fixedBaseIsExclusiveEnd ? dragStartAffinity : hitTestAffinity;
}

/// When the moving [extent] is unchanged, keep [previousAffinity].
///
/// Hit-test upstream/downstream can toggle at the same caret and jump
/// [getEndpointsForSelection] — fixed handles with zero follower delta then
/// appear to stick to the moving handle.
TextAffinity affinityForHandleDragStable({
  required int extent,
  required int previousExtent,
  required TextAffinity previousAffinity,
  required TextAffinity candidateAffinity,
}) {
  if (extent == previousExtent) {
    return previousAffinity;
  }
  return candidateAffinity;
}

/// Whether two selections identify the same hybrid paint cache entry.
///
/// Includes [TextSelection.affinity] — non-collapsed [TextSelection.==]
/// ignores it, so affinity-only exclusive-end flips would otherwise look equal.
bool selectionsMatchForHybridCache(TextSelection a, TextSelection b) {
  return a.baseOffset == b.baseOffset &&
      a.extentOffset == b.extentOffset &&
      a.affinity == b.affinity;
}

/// Builds Telegram-style hybrid selection boxes
/// (`TextSelectionHelper.drawSelection`).
///
/// Multi-line selections use [ui.BoxWidthStyle.max] on completed lines and
/// [ui.BoxWidthStyle.tight] on the content end line.
///
/// Exclusive ends (soft wrap or hard break) branch on exclusive-end affinity:
/// - [TextAffinity.upstream]: content end line **tight**, handle stays on that
///   line (empty space to the right of the last glyph).
/// - [TextAffinity.downstream]: content end line **max**, empty-edge handle on
///   the following line.
///
/// Hard breaks omit the `\n` so the engine does not emit a leading box on the
/// following line. Prior completed lines stay `max`.
///
/// Content-less exclusive end: when the painted range on the content end line
/// is empty (or the engine returns no boxes there), [synthesizeContentLessTrailing]
/// supplies a trailing tight/max box so chrome is never blank.
///
/// Handle placement for exclusive ends is handled by
/// [ExtendedRenderEditable.getEndpointsForSelection].
List<ui.TextBox> computeHybridSelectionBoxes({
  required TextSelection selection,
  required TextSelection Function(int offset) lineAtOffset,
  required List<ui.TextBox> Function(
    TextSelection range,
    ui.BoxWidthStyle style,
  )
  boxesFor,
  ExclusiveLineEndKind? Function(int offset)? exclusiveEndKind,
  List<ui.TextBox> Function({
    required TextSelection contentEndLine,
    required ui.BoxWidthStyle style,
  })?
  synthesizeContentLessTrailing,
}) {
  if (!selection.isValid || selection.isCollapsed) {
    return const <ui.TextBox>[];
  }

  final int lo = selection.start;
  final int hi = selection.end;
  final TextSelection startLine = lineAtOffset(lo);

  final ExclusiveLineEndKind? endKind = exclusiveEndKind?.call(hi);

  if (endKind != null) {
    // Soft wrap: [lo, hi). Hard break: omit `\n` at hi-1.
    final int paintEnd = endKind == ExclusiveLineEndKind.hardBreak
        ? hi - 1
        : hi;
    // Content-less: paintEnd has no glyph left of exclusive end — anchor the
    // content end line at the last glyph before the break/wrap.
    final TextSelection contentEndLine = paintEnd > lo
        ? lineAtOffset(paintEnd - 1)
        : lineAtOffset(
            endKind == ExclusiveLineEndKind.hardBreak
                ? math.max(0, hi - 2)
                : math.max(0, hi - 1),
          );
    final ui.BoxWidthStyle contentStyle = exclusiveEndUsesEmptyEdge(selection)
        ? ui.BoxWidthStyle.max
        : ui.BoxWidthStyle.tight;
    final boxes = <ui.TextBox>[];
    void addRange(int start, int end, ui.BoxWidthStyle style) {
      if (end <= start) return;
      boxes.addAll(
        boxesFor(TextSelection(baseOffset: start, extentOffset: end), style),
      );
    }

    final int contentRangeStart = math.max(lo, contentEndLine.start);
    final bool contentLess = paintEnd <= contentRangeStart;

    if (startLine.start != contentEndLine.start) {
      // Completed lines before the content end line (skip when the selection
      // itself starts on/after that line — typical newline-only content-less).
      final int completedEnd = math.min(contentEndLine.start, paintEnd);
      if (completedEnd > lo) {
        addRange(lo, completedEnd, ui.BoxWidthStyle.max);
      }
    }

    final int beforeContentEnd = boxes.length;
    if (!contentLess) {
      addRange(contentRangeStart, paintEnd, contentStyle);
    }
    // Content-less, or engine returned no glyph boxes on the content end line.
    if (contentLess || boxes.length == beforeContentEnd) {
      final List<ui.TextBox>? synthesized = synthesizeContentLessTrailing?.call(
        contentEndLine: contentEndLine,
        style: contentStyle,
      );
      if (synthesized != null) {
        boxes.addAll(synthesized);
      }
    }
    return boxes;
  }

  final TextSelection endLine = lineAtOffset(hi > lo ? hi - 1 : lo);

  final boxes = <ui.TextBox>[];

  void addRange(int start, int end, ui.BoxWidthStyle style) {
    if (end <= start) return;
    boxes.addAll(
      boxesFor(TextSelection(baseOffset: start, extentOffset: end), style),
    );
  }

  if (startLine.start == endLine.start) {
    addRange(lo, hi, ui.BoxWidthStyle.tight);
    return boxes;
  }

  addRange(lo, math.min(hi, endLine.start), ui.BoxWidthStyle.max);
  addRange(math.max(lo, endLine.start), hi, ui.BoxWidthStyle.tight);

  return boxes;
}

/// Closes the gaps line metrics leave between the boxes of adjacent lines.
///
/// Half-leading rounds independently per line, so a line box can stop short of
/// the next line's top — a translucent highlight then reads as a stack of
/// ribbons. Lines closer than [maxGap] meet halfway; anything further apart is
/// a break the caller means to keep.
///
/// Boxes are grouped by their top edge, so a line's runs stay aligned.
List<Rect> stitchSelectionLines(List<Rect> rects, {required double maxGap}) {
  final Map<double, double> lineBottoms = <double, double>{};
  for (final Rect rect in rects) {
    final double? bottom = lineBottoms[rect.top];
    lineBottoms[rect.top] = bottom == null
        ? rect.bottom
        : math.max(bottom, rect.bottom);
  }
  if (lineBottoms.length < 2) {
    return rects;
  }

  final List<double> tops = lineBottoms.keys.toList()..sort();
  final Map<double, double> stitchedTops = <double, double>{};
  final Map<double, double> stitchedBottoms = <double, double>{};
  for (int i = 0; i < tops.length - 1; i++) {
    final double bottom = lineBottoms[tops[i]]!;
    final double gap = tops[i + 1] - bottom;
    if (gap <= 0 || gap > maxGap) {
      continue;
    }
    final double meet = bottom + gap / 2;
    stitchedBottoms[tops[i]] = meet;
    stitchedTops[tops[i + 1]] = meet;
  }
  if (stitchedTops.isEmpty) {
    return rects;
  }

  return <Rect>[
    for (final Rect rect in rects)
      Rect.fromLTRB(
        rect.left,
        stitchedTops[rect.top] ?? rect.top,
        rect.right,
        stitchedBottoms[rect.top] ?? rect.bottom,
      ),
  ];
}
