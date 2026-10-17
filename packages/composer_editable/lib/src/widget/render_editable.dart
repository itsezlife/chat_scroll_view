import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'selection_boxes.dart';
import 'selection_debug.dart';

/// [RenderEditable] with Telegram-style hybrid selection geometry.
///
/// Extends stock layout with [computeHybridSelectionBoxes] for highlight
/// rects, and adjusts [getEndpointsForSelection] when the exclusive end of a
/// selection falls at the start of the following visual line (soft wrap or
/// hard break).
///
/// Selected glyphs then lie on the previous line while [TextSelection.end]
/// addresses the next line’s start. Exclusive-end [TextAffinity] chooses chrome:
/// [TextAffinity.downstream] → content line `max` + empty-edge handle on the
/// following line; [TextAffinity.upstream] → content line `tight` + handle at
/// the last glyph. Prior completed lines still use `max`.
class ExtendedRenderEditable extends RenderEditable {
  /// Creates an extended render editable.
  ExtendedRenderEditable({
    required super.textDirection,
    required ViewportOffset offset,
    required super.textSelectionDelegate,
    required super.startHandleLayerLink,
    required super.endHandleLayerLink,
    super.text,
    super.textAlign,
    super.cursorColor,
    super.backgroundCursorColor,
    super.showCursor,
    super.hasFocus,
    super.maxLines,
    super.minLines,
    super.expands,
    super.strutStyle,
    super.selectionColor,
    super.textScaler,
    super.locale,
    super.selection,
    super.obscuringCharacter,
    super.obscureText,
    super.forceLine,
    super.readOnly,
    super.textHeightBehavior,
    super.textWidthBasis,
    super.cursorWidth,
    super.cursorHeight,
    super.cursorRadius,
    super.cursorOffset,
    super.paintCursorAboveText,
    super.selectionHeightStyle,
    super.selectionWidthStyle,
    super.enableInteractiveSelection,
    super.promptRectRange,
    super.promptRectColor,
    super.clipBehavior,
    super.devicePixelRatio,
    super.ignorePointer,
    super.painter,
    super.foregroundPainter,
  }) : super(offset: offset) {
    offset.addListener(_onScrollOffsetChanged);
  }

  List<ui.TextBox> _cachedBoxes = const <ui.TextBox>[];
  TextSelection? _cachedSelection;
  int? _cachedTextHash;

  /// Last laid-out size; kept across hybrid invalidation so chrome can rebuild
  /// while another [RenderObject] is the active layout (e.g. handle overlay).
  Size? _cachedSize;
  double? _cachedPixels;
  String? _lastEndpointsDebugSig;

  void _onScrollOffsetChanged() {
    _invalidateHybridCache();
    _warmHybridCache();
    markNeedsPaint();
  }

  void _invalidateHybridCache() {
    _cachedSelection = null;
    _cachedBoxes = const <ui.TextBox>[];
    _cachedTextHash = null;
    _cachedPixels = null;
  }

  /// Whether reading [size] is legal in the current pipeline phase.
  ///
  /// Any other [RenderObject] mid-[performLayout] (not a layout callback) makes
  /// [size] assert — including selection-handle overlay ancestors.
  bool get _canAccessOwnSize {
    if (debugDoingThisLayout || debugDoingThisResize) {
      return true;
    }
    final RenderObject? active = RenderObject.debugActiveLayout;
    if (active != null && !identical(active, this)) {
      // Deny all foreign layout. (Layout callbacks allow size globally in the
      // framework, but we still avoid reading size there for hybrid rebuilds.)
      return active.debugDoingThisLayoutWithCallback;
    }
    return true;
  }

  bool get _inForeignLayout {
    final RenderObject? active = RenderObject.debugActiveLayout;
    return active != null &&
        !identical(active, this) &&
        !debugDoingThisLayout &&
        !active.debugDoingThisLayoutWithCallback;
  }

  /// Whether [text] changed since the last layout, leaving glyph metrics stale.
  bool _textLayoutDirty = false;

  bool _hybridRebuildScheduled = false;

  void _scheduleHybridRebuild() {
    if (_hybridRebuildScheduled) {
      return;
    }
    _hybridRebuildScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _hybridRebuildScheduled = false;
      if (!attached) {
        return;
      }
      _warmHybridCache();
      markNeedsPaint();
    });
  }

  /// Layout width for hybrid chrome without asserting during foreign layout.
  Size? get _sizeForHybrid {
    if (_canAccessOwnSize && hasSize) {
      return size;
    }
    return _cachedSize;
  }

  bool get _isCacheValid {
    final TextSelection? sel = selection;
    return sel != null &&
        _cachedSelection != null &&
        selectionsMatchForHybridCache(_cachedSelection!, sel) &&
        _cachedTextHash == text?.hashCode &&
        _cachedSize == _sizeForHybrid &&
        _cachedPixels == offset.pixels;
  }

  /// Whether [query] is the editable’s current paint selection (cache key).
  bool _isPaintSelection(TextSelection query) {
    final TextSelection? paint = selection;
    return paint != null &&
        paint.isValid &&
        selectionsMatchForHybridCache(paint, query);
  }

  bool _matchesCachedSelection(TextSelection query) {
    final TextSelection? cached = _cachedSelection;
    return cached != null && selectionsMatchForHybridCache(cached, query);
  }

  void _warmHybridCache() {
    final TextSelection? sel = selection;
    if (sel == null || !sel.isValid || sel.isCollapsed) {
      _invalidateHybridCache();
      return;
    }
    if (owner?.debugDoingPaint ?? false) {
      return;
    }
    if (_inForeignLayout) {
      _scheduleHybridRebuild();
      return;
    }
    if (_sizeForHybrid == null) {
      return;
    }
    if (_textLayoutDirty) {
      // Glyph metrics are stale until the pending layout runs, and that pass
      // warms the cache itself.
      return;
    }
    if (_isCacheValid) {
      return;
    }
    _storePaintHybridCache(_computeHybridBoxes(sel), sel);
  }

  ExclusiveLineEndKind? _exclusiveEndKind(int offset) {
    return exclusiveLineEndKind(
      offset: offset,
      plainText: plainText,
      lineAtOffset: (int o) => getLineAtOffset(TextPosition(offset: o)),
    );
  }

  /// Room kept on the leading side of the text area for [gutterPainter].
  ///
  /// Only the gutter band opens up: the text keeps its own clip, so overflow
  /// cannot escape the field.
  double get gutterExtent => _gutterExtent;
  double _gutterExtent = 0.0;
  set gutterExtent(double value) {
    final double next = value < 0.0 ? 0.0 : value;
    if (_gutterExtent == next) {
      return;
    }
    _gutterExtent = next;
    markNeedsPaint();
  }

  /// Paints chrome in the leading gutter, above the text.
  ///
  /// Kept apart from [foregroundPainter] because that one paints inside the
  /// text clip, which would cut anything drawn beside the text.
  RenderEditablePainter? get gutterPainter => _gutterPainter;
  RenderEditablePainter? _gutterPainter;
  set gutterPainter(RenderEditablePainter? value) {
    if (identical(_gutterPainter, value)) {
      return;
    }
    _gutterPainter?.removeListener(markNeedsPaint);
    _gutterPainter = value;
    _gutterPainter?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// Inset the scrolled text keeps from the text area's own bounds.
  ///
  /// Belongs to the content, not to the box: the first and last line stay off
  /// the bounds while every other line scrolls through the inset and is cut at
  /// the bounds — the way [SingleChildScrollView.padding] insets content
  /// against its viewport. Geometric padding instead would shrink the box, so
  /// lines would stop short of the bounds and leave a permanent empty band.
  ///
  /// The box grows by the inset, and the scroll range covers it. Position
  /// translation belongs to the offset the editable is given ([
  /// PaddedViewportOffset]); this side only owns the extents.
  ///
  /// Applies to the vertical scroll axis, so it is only meaningful for
  /// multiline editables.
  EdgeInsets get contentScrollPadding => _contentScrollPadding;
  EdgeInsets _contentScrollPadding = EdgeInsets.zero;
  set contentScrollPadding(EdgeInsets value) {
    if (_contentScrollPadding == value) {
      return;
    }
    _contentScrollPadding = value;
    markNeedsLayout();
  }

  double get _contentScrollExtent => _contentScrollPadding.vertical;

  final LayerHandle<ClipRectLayer> _gutterClipLayer =
      LayerHandle<ClipRectLayer>();

  bool get _isLtr => textDirection == TextDirection.ltr;

  @override
  void performLayout() {
    super.performLayout();
    _textLayoutDirty = false;
    _invalidateHybridCache();
    _warmHybridCache();

    final double inset = _contentScrollExtent;
    if (inset == 0.0) {
      return;
    }
    // Super sized the box to the text alone and published extents against it;
    // both have to account for the inset the content now carries.
    final double contentExtent = maxScrollExtent + size.height;
    size = Size(size.width, constraints.constrainHeight(size.height + inset));
    offset
      ..applyViewportDimension(size.height)
      ..applyContentDimensions(
        0.0,
        math.max(0.0, contentExtent + inset - size.height),
      );
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(width) + _contentScrollExtent;

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(width) + _contentScrollExtent;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final Size size = super.computeDryLayout(constraints);
    if (_contentScrollExtent == 0.0) {
      return size;
    }
    return Size(
      size.width,
      constraints.constrainHeight(size.height + _contentScrollExtent),
    );
  }

  @override
  double computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) =>
      super.computeDryBaseline(constraints, baseline) +
      _contentScrollPadding.top;

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) =>
      super.computeDistanceToActualBaseline(baseline) +
      _contentScrollPadding.top;

  @override
  void paint(PaintingContext context, Offset offset) {
    final RenderEditablePainter? gutterPainter = _gutterPainter;
    if (_gutterExtent <= 0.0 || gutterPainter == null) {
      _gutterClipLayer.layer = null;
      super.paint(context, offset);
      _widenSelectionVisibilityToVisibleCaret();
      return;
    }

    _gutterClipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      gutterClipRect(size: size, gutterExtent: _gutterExtent, ltr: _isLtr),
      (PaintingContext innerContext, Offset innerOffset) {
        super.paint(innerContext, innerOffset);
        _widenSelectionVisibilityToVisibleCaret();
        // Editable painters draw in the editable's own coordinates.
        final Canvas canvas = innerContext.canvas;
        canvas
          ..save()
          ..translate(innerOffset.dx, innerOffset.dy);
        gutterPainter.paint(canvas, size, this);
        canvas.restore();
      },
      clipBehavior: clipBehavior,
      oldLayer: _gutterClipLayer.layer,
    );
  }

  /// Keeps handles whose endpoint line is still partly on screen.
  ///
  /// Stock visibility asks whether the caret's top edge is inside the text
  /// area, so a handle hanging off a line that is only cropped at the top
  /// counts as scrolled away. Any visible part of the anchored caret keeps it.
  /// Only widens the stock answer.
  void _widenSelectionVisibilityToVisibleCaret() {
    final TextSelection? current = selection;
    if (current == null || !current.isValid) {
      return;
    }
    final Rect region = (Offset.zero & size).inflate(0.5);
    void widen(ValueListenable<bool> visibility, int offset) {
      if (visibility is! ValueNotifier<bool> || visibility.value) {
        return;
      }
      visibility.value = region.overlaps(
        getLocalRectForCaret(
          TextPosition(offset: offset, affinity: current.affinity),
        ),
      );
    }

    widen(selectionStartInViewport, current.start);
    widen(selectionEndInViewport, current.end);
  }

  @override
  void dispose() {
    _gutterPainter?.removeListener(markNeedsPaint);
    _gutterClipLayer.layer = null;
    offset.removeListener(_onScrollOffsetChanged);
    super.dispose();
  }

  @override
  set selection(TextSelection? value) {
    final TextSelection? current = selection;
    // [TextSelection.==] ignores affinity when non-collapsed; force the field
    // through so upstream↔downstream at a wrap bound updates hybrid chrome.
    if (current != null &&
        value != null &&
        !current.isCollapsed &&
        !value.isCollapsed &&
        current.baseOffset == value.baseOffset &&
        current.extentOffset == value.extentOffset &&
        current.affinity != value.affinity) {
      super.selection = value.copyWith(isDirectional: !value.isDirectional);
    }
    super.selection = value;
    _invalidateHybridCache();
    _warmHybridCache();
  }

  @override
  set text(InlineSpan? value) {
    if (text != value) {
      _textLayoutDirty = true;
    }
    super.text = value;
    _invalidateHybridCache();
  }

  @override
  List<TextSelectionPoint> getEndpointsForSelection(TextSelection selection) {
    if (!selection.isValid || selection.isCollapsed) {
      return super.getEndpointsForSelection(selection);
    }

    // Custom hybrid endpoints may rebuild boxes / touch layout geometry.
    // During foreign layout (handle overlay), fall back to stock endpoints.
    if (_inForeignLayout) {
      _scheduleHybridRebuild();
      return super.getEndpointsForSelection(selection);
    }

    final List<ui.TextBox> boxes = getBoxesForSelection(selection);
    if (boxes.isEmpty) {
      return super.getEndpointsForSelection(selection);
    }

    final Size? layoutSize = _sizeForHybrid;
    final double maxWidth = math.max(
      layoutSize?.width ?? 0,
      math.max(boxes.first.right, boxes.last.right),
    );
    final Offset start = Offset(
      clampDouble(boxes.first.start, 0, maxWidth),
      boxes.first.bottom,
    );

    final Offset end;
    final ExclusiveLineEndKind? endKind = _exclusiveEndKind(selection.end);
    final bool useEmptyEdge =
        endKind != null && exclusiveEndUsesEmptyEdge(selection);
    if (useEmptyEdge) {
      // Avoid [getLocalRectForCaret] — it reads [size] and asserts when another
      // RenderObject is mid-layout.
      final List<TextSelectionPoint> edge = super.getEndpointsForSelection(
        TextSelection.collapsed(
          offset: selection.end,
          affinity: TextAffinity.downstream,
        ),
      );
      end = edge.first.point;
    } else {
      end = Offset(clampDouble(boxes.last.end, 0, maxWidth), boxes.last.bottom);
    }

    if (debugLogExtendedTextSelectionHandles && endKind != null) {
      final String sig =
          '${selection.baseOffset}:${selection.extentOffset}:'
          '${selection.affinity.name}:$useEmptyEdge:'
          '${start.dx.toStringAsFixed(1)},${start.dy.toStringAsFixed(1)}:'
          '${end.dx.toStringAsFixed(1)},${end.dy.toStringAsFixed(1)}';
      if (_lastEndpointsDebugSig != sig) {
        _lastEndpointsDebugSig = sig;
        debugLogExtendedSelection(
          'endpoints: ${debugSelectionSummary(selection)} '
          '${debugExclusiveEndChromeSummary(selection: selection, endKind: endKind)} '
          'start=(${start.dx.toStringAsFixed(1)},${start.dy.toStringAsFixed(1)}) '
          'end=(${end.dx.toStringAsFixed(1)},${end.dy.toStringAsFixed(1)}) '
          'path=${useEmptyEdge ? 'emptyEdgeCollapsed' : 'boxes.last'} '
          '${debugSelectionBoxesSummary(boxes)}',
        );
      }
    }

    return <TextSelectionPoint>[
      TextSelectionPoint(start, boxes.first.direction),
      TextSelectionPoint(end, boxes.last.direction),
    ];
  }

  List<ui.TextBox> boxesForSelectionWithStyle(
    TextSelection range,
    ui.BoxWidthStyle style,
  ) {
    assert(
      !(owner?.debugDoingPaint ?? false),
      'boxesForSelectionWithStyle cannot run during paint',
    );
    final ui.BoxWidthStyle previous = selectionWidthStyle;
    selectionWidthStyle = style;
    try {
      return super.getBoxesForSelection(range);
    } finally {
      selectionWidthStyle = previous;
    }
  }

  /// Hybrid boxes for [selection]; never writes the paint selection cache.
  List<ui.TextBox> _computeHybridBoxes(TextSelection selection) {
    final ExclusiveLineEndKind? endKind = _exclusiveEndKind(selection.end);
    List<ui.TextBox> boxes = computeHybridSelectionBoxes(
      selection: selection,
      lineAtOffset: (int offset) =>
          getLineAtOffset(TextPosition(offset: offset)),
      boxesFor: boxesForSelectionWithStyle,
      exclusiveEndKind: _exclusiveEndKind,
      synthesizeContentLessTrailing:
          ({
            required TextSelection contentEndLine,
            required ui.BoxWidthStyle style,
          }) => _synthesizeContentLessTrailing(
            selection: selection,
            contentEndLine: contentEndLine,
            style: style,
          ),
    );
    // Soft-wrap + empty-edge: engine [BoxWidthStyle.max] does not fill to the
    // layout width the way hard-break completed lines do — extend the last box.
    var softWrapMaxExtended = false;
    final Size? layoutSize = _sizeForHybrid;
    if (endKind == ExclusiveLineEndKind.softWrap &&
        exclusiveEndUsesEmptyEdge(selection) &&
        boxes.isNotEmpty &&
        layoutSize != null) {
      final ui.TextBox last = boxes.last;
      final double maxRight = math.max(layoutSize.width, last.right);
      if (maxRight > last.right + 0.5) {
        softWrapMaxExtended = true;
        boxes = <ui.TextBox>[
          ...boxes.sublist(0, boxes.length - 1),
          ui.TextBox.fromLTRBD(
            last.left,
            last.top,
            maxRight,
            last.bottom,
            last.direction,
          ),
        ];
      }
    }
    if (debugLogExtendedTextSelectionHandles) {
      final TextSelection? prev = _cachedSelection;
      final bool affinityOnlyStale =
          prev != null &&
          prev.baseOffset == selection.baseOffset &&
          prev.extentOffset == selection.extentOffset &&
          prev.affinity != selection.affinity;
      final bool paint = _isPaintSelection(selection);
      debugLogExtendedSelection(
        '${paint ? 'hybridRebuild' : 'hybridEphemeral'}: '
        '${debugSelectionSummary(selection)} '
        '${debugExclusiveEndChromeSummary(selection: selection, endKind: endKind)} '
        'softWrapMaxExt=$softWrapMaxExtended '
        'affinityOnlyVsCache=$affinityOnlyStale '
        '${debugSelectionBoxesSummary(boxes)}',
      );
    }
    return boxes;
  }

  void _storePaintHybridCache(List<ui.TextBox> boxes, TextSelection selection) {
    assert(_isPaintSelection(selection));
    _cachedBoxes = boxes;
    _cachedSelection = selection;
    _cachedTextHash = text?.hashCode;
    if (_canAccessOwnSize && hasSize) {
      _cachedSize = size;
    }
    _cachedPixels = offset.pixels;
  }

  /// Trailing box for content-less exclusive end on [contentEndLine].
  ///
  /// Scoped to [selection] (the range being computed), not the editable’s
  /// current paint selection — magnifier/subrange queries must synthesize for
  /// their own range.
  ///
  /// Uses glyph boxes instead of [getLocalRectForCaret] (caret reads [size] and
  /// asserts during selection-handle overlay layout).
  List<ui.TextBox> _synthesizeContentLessTrailing({
    required TextSelection selection,
    required TextSelection contentEndLine,
    required ui.BoxWidthStyle style,
  }) {
    if (!selection.isValid) {
      return const <ui.TextBox>[];
    }
    final ExclusiveLineEndKind? endKind = _exclusiveEndKind(selection.end);
    final int lastGlyphOffset = switch (endKind) {
      ExclusiveLineEndKind.hardBreak => math.max(0, selection.end - 2),
      ExclusiveLineEndKind.softWrap => math.max(0, selection.end - 1),
      null => math.max(0, selection.end - 1),
    };
    if (lastGlyphOffset < contentEndLine.start ||
        lastGlyphOffset >= plainText.length) {
      return const <ui.TextBox>[];
    }
    final List<ui.TextBox> glyphBoxes = boxesForSelectionWithStyle(
      TextSelection(
        baseOffset: lastGlyphOffset,
        extentOffset: lastGlyphOffset + 1,
      ),
      ui.BoxWidthStyle.tight,
    );
    if (glyphBoxes.isEmpty) {
      return const <ui.TextBox>[];
    }
    final ui.TextBox last = glyphBoxes.last;
    final double maxWidth = math.max(
      _sizeForHybrid?.width ?? last.right,
      last.right,
    );
    final double left = last.right;
    final double right = style == ui.BoxWidthStyle.max ? maxWidth : left;
    if (right + 0.5 < left) {
      return const <ui.TextBox>[];
    }
    return <ui.TextBox>[
      ui.TextBox.fromLTRBD(left, last.top, right, last.bottom, last.direction),
    ];
  }

  @override
  List<ui.TextBox> getBoxesForSelection(TextSelection selection) {
    if (!selection.isValid || selection.isCollapsed) {
      return const <ui.TextBox>[];
    }

    if (_isCacheValid && _matchesCachedSelection(selection)) {
      return _cachedBoxes;
    }

    if (owner?.debugDoingPaint ?? false) {
      return _cachedBoxes.isNotEmpty && _matchesCachedSelection(selection)
          ? _cachedBoxes
          : super.getBoxesForSelection(selection);
    }

    if (_inForeignLayout) {
      _scheduleHybridRebuild();
      if (_cachedBoxes.isNotEmpty && _matchesCachedSelection(selection)) {
        return _cachedBoxes;
      }
      // Ephemeral hybrid without cache write when layout width is known.
      if (_sizeForHybrid != null) {
        return _computeHybridBoxes(selection);
      }
      return super.getBoxesForSelection(selection);
    }

    final List<ui.TextBox> boxes = _computeHybridBoxes(selection);
    if (_isPaintSelection(selection)) {
      _storePaintHybridCache(boxes, selection);
    }
    return boxes;
  }
}

/// Paint bounds for an editable that reserves [gutterExtent] beside its text.
///
/// The trailing side stays at the text bounds; only the leading gutter is
/// exempt from clipping.
Rect gutterClipRect({
  required Size size,
  required double gutterExtent,
  required bool ltr,
}) => Rect.fromLTWH(
  ltr ? -gutterExtent : 0.0,
  0.0,
  size.width + gutterExtent,
  size.height,
);

/// Paints Telegram-style hybrid selection highlights.
///
/// Built-in [RenderEditable] highlight must be disabled (`selectionColor: null`)
/// so this painter is the sole source of selection chrome.
class HybridSelectionHighlightPainter extends RenderEditablePainter {
  /// Creates a hybrid selection painter.
  HybridSelectionHighlightPainter({Color? highlightColor})
    : _highlightColor = highlightColor;

  final Paint _paint = Paint();

  Color? get highlightColor => _highlightColor;
  Color? _highlightColor;
  set highlightColor(Color? value) {
    if (_highlightColor == value) {
      return;
    }
    _highlightColor = value;
    notifyListeners();
  }

  @override
  void paint(Canvas canvas, Size size, RenderEditable renderEditable) {
    final Color? color = highlightColor;
    final TextSelection? selection = renderEditable.selection;
    if (color == null ||
        selection == null ||
        !selection.isValid ||
        selection.isCollapsed) {
      return;
    }

    _paint.color = color;
    final List<ui.TextBox> boxes = renderEditable.getBoxesForSelection(
      selection,
    );
    // Boxes are viewport-relative, so clipping uses the editable's box — [size]
    // measures the text and can fall short of it (short or inset content).
    final Rect clip = Offset.zero & renderEditable.size;
    final List<Rect> lines = stitchSelectionLines(<Rect>[
      for (final ui.TextBox box in boxes) box.toRect(),
    ], maxGap: renderEditable.preferredLineHeight / 2);
    // One shape rather than a rect per box: a translucent highlight seams along
    // the edges boxes share, and overlapping boxes would blend twice.
    final Path path = Path();
    var drawn = false;
    for (final Rect line in lines) {
      final Rect rect = line.intersect(clip);
      if (rect.isEmpty) {
        continue;
      }
      path.addRect(rect);
      drawn = true;
    }
    if (drawn) {
      canvas.drawPath(path, _paint);
    }
  }

  @override
  bool shouldRepaint(RenderEditablePainter? oldDelegate) {
    if (identical(oldDelegate, this)) {
      return false;
    }
    return oldDelegate is! HybridSelectionHighlightPainter ||
        oldDelegate.highlightColor != highlightColor;
  }
}
