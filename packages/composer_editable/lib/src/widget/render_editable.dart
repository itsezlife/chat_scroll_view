import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// [RenderEditable] for the composer's editable: a gutter beside the text, a
/// content inset that scrolls with the text, and handle / toolbar visibility
/// that follows the selection's visible part rather than its endpoints.
///
/// Selection paint and endpoint geometry are stock: the highlight is the
/// engine's [BoxWidthStyle], and the `painter` slot stays free for callers.
class ExtendedRenderEditable extends RenderEditable {
  /// Creates an extended render editable.
  ExtendedRenderEditable({
    required super.textDirection,
    required super.offset,
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
  });

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
      _publishSelectionVisibility();
      return;
    }

    _gutterClipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      gutterClipRect(size: size, gutterExtent: _gutterExtent, ltr: _isLtr),
      (PaintingContext innerContext, Offset innerOffset) {
        super.paint(innerContext, innerOffset);
        _publishSelectionVisibility();
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

  /// Whether the start caret is visible in the text area.
  ///
  /// Wider than [selectionStartInViewport]: stock asks whether the caret's top
  /// edge is inside the text area, so a handle hanging off a line that is only
  /// cropped at the top counts as scrolled away. Any visible part of the
  /// anchored caret keeps the handle, so this is true whenever the stock value
  /// is.
  ///
  /// A separate notifier rather than a write to the stock one: that one is
  /// typed [ValueListenable] and owned by [RenderEditable], so overwriting it
  /// would need a downcast to its private [ValueNotifier] and would notify
  /// twice per paint (stock's answer, then the widened one).
  ValueListenable<bool> get startHandleInViewport => _startHandleInViewport;
  final ValueNotifier<bool> _startHandleInViewport = ValueNotifier<bool>(true);

  /// Whether the end caret is visible in the text area; the end counterpart of
  /// [startHandleInViewport].
  ValueListenable<bool> get endHandleInViewport => _endHandleInViewport;
  final ValueNotifier<bool> _endHandleInViewport = ValueNotifier<bool>(true);

  /// Whether any part of the selection is visible in the text area.
  ///
  /// True when either caret is visible ([startHandleInViewport],
  /// [endHandleInViewport]) or a selection box overlaps the text area. The
  /// endpoint test alone fails after select-all on tall text: both ends can be
  /// off-screen while the middle is still visible. Drives the selection
  /// toolbar's visibility.
  ValueListenable<bool> get selectionIntersectsViewport =>
      _selectionIntersectsViewport;
  final ValueNotifier<bool> _selectionIntersectsViewport = ValueNotifier<bool>(
    true,
  );

  /// Publishes the three visibility notifiers from the selection as painted.
  ///
  /// Runs at the end of [paint], where reading [size] is legal in every build
  /// mode: the overlay that consumes the answer lays out in a pass of its own,
  /// where reading this box's size is not.
  void _publishSelectionVisibility() {
    final TextSelection? current = selection;
    if (current == null) {
      return;
    }
    final bool startVisible =
        selectionStartInViewport.value ||
        _caretOverlapsViewport(current, current.start);
    final bool endVisible =
        selectionEndInViewport.value ||
        _caretOverlapsViewport(current, current.end);
    _startHandleInViewport.value = startVisible;
    _endHandleInViewport.value = endVisible;
    _selectionIntersectsViewport.value =
        startVisible || endVisible || _selectionBoxOverlapsViewport(current);
  }

  bool _caretOverlapsViewport(TextSelection current, int offset) {
    if (!current.isValid) {
      return false;
    }
    final Rect region = (Offset.zero & size).inflate(0.5);
    return region.overlaps(
      getLocalRectForCaret(
        TextPosition(offset: offset, affinity: current.affinity),
      ),
    );
  }

  bool _selectionBoxOverlapsViewport(TextSelection current) {
    if (!current.isValid || current.isCollapsed) {
      return false;
    }
    final List<TextBox> boxes = getBoxesForSelection(current);
    if (boxes.isEmpty) {
      return false;
    }
    final Rect selectionRect = boxes
        .map((TextBox box) => box.toRect())
        .reduce((Rect a, Rect b) => a.expandToInclude(b));
    return selectionRect.overlaps(Offset.zero & size);
  }

  @override
  void dispose() {
    _gutterPainter?.removeListener(markNeedsPaint);
    _gutterClipLayer.layer = null;
    _startHandleInViewport.dispose();
    _endHandleInViewport.dispose();
    _selectionIntersectsViewport.dispose();
    super.dispose();
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
