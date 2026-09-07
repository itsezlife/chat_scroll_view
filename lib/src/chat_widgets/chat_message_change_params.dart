import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// When true, change-transition paints append samples to
/// [RenderChatMessageChangeTransition.debugPaintHistory].
///
/// Opt in from diagnostic tests. Keep false in production.
bool debugChatMessageChangeRecordPaints = false;

/// List-item change duration.
const Duration kChatMessageChangeDuration = Duration(milliseconds: 250);

/// List-item change curve.
const Curve kChatMessageChangeCurve = Cubic(
  0.19919472913616398,
  0.010644531250000006,
  0.27920937042459737,
  0.91025390625,
);

/// Clip inset inside the painted bubble while crossfading text.
const double kChatMessageChangeClipInset = 4;

/// Edge deltas for background-bounds change animation.
///
/// At animation start, [left]/[right]/[top]/[bottom] equal
/// `oldEdge − newEdge` so `finalRect + deltas` reconstructs the previous
/// painted bubble. During flight they are scaled by `(1 − progress)`.
@immutable
class ChatMessageChangeDeltas {
  /// Creates raw edge deltas (old − new) in the render object's coordinates.
  const ChatMessageChangeDeltas({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  /// Builds start deltas from the last painted rect and the new layout rect.
  ///
  /// All four edges are recorded; outgoing bubbles typically change [left],
  /// incoming typically [right], when only width changes.
  factory ChatMessageChangeDeltas.between({
    required Rect oldRect,
    required Rect newRect,
  }) => ChatMessageChangeDeltas(
    left: oldRect.left - newRect.left,
    right: oldRect.right - newRect.right,
    top: oldRect.top - newRect.top,
    bottom: oldRect.bottom - newRect.bottom,
  );

  /// Zero deltas — settled / no background animation.
  static const ChatMessageChangeDeltas zero = ChatMessageChangeDeltas(
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
  );

  /// Left edge: `old.left − new.left`.
  final double left;

  /// Right edge: `old.right − new.right`.
  final double right;

  /// Top edge: `old.top − new.top`.
  final double top;

  /// Bottom edge: `old.bottom − new.bottom`.
  final double bottom;

  /// Scales by `v` where the animator uses `v = 1 − progress`.
  ChatMessageChangeDeltas scaled(double oneMinusProgress) =>
      ChatMessageChangeDeltas(
        left: left * oneMinusProgress,
        right: right * oneMinusProgress,
        top: top * oneMinusProgress,
        bottom: bottom * oneMinusProgress,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatMessageChangeDeltas &&
      left == other.left &&
      right == other.right &&
      top == other.top &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, right, top, bottom);

  @override
  String toString() =>
      'Δ(l=${left.toStringAsFixed(1)}, r=${right.toStringAsFixed(1)}, '
      't=${top.toStringAsFixed(1)}, b=${bottom.toStringAsFixed(1)})';
}

/// Snapshot of change-animation state for one tick.
@immutable
class ChatMessageChangeParams {
  /// Creates a change-animation snapshot.
  const ChatMessageChangeParams({
    required this.progress,
    required this.deltas,
    required this.animateMessageText,
    required this.animateBackgroundBounds,
    required this.animateEditedEnter,
    required this.editedWidthDiff,
    this.holdPaintedBackground,
    this.animateFromMetaOffset,
    this.animateFromMetaWidth,
    this.shouldAnimateMetaX = false,
  });

  /// Settled / no animation.
  static const ChatMessageChangeParams settled = ChatMessageChangeParams(
    progress: 1,
    deltas: ChatMessageChangeDeltas.zero,
    animateMessageText: false,
    animateBackgroundBounds: false,
    animateEditedEnter: false,
    editedWidthDiff: 0,
  );

  /// Change progress ∈ `[0, 1]`.
  final double progress;

  /// Unscaled start deltas (`old − new`); [paintedBackground] applies
  /// `(1 − progress)`.
  final ChatMessageChangeDeltas deltas;

  /// Dual text crossfade when body text changed.
  final bool animateMessageText;

  /// Paint background via deltas (layout stays at the final rect).
  final bool animateBackgroundBounds;

  /// “edited” prefix enter / meta width morph.
  final bool animateEditedEnter;

  /// Incoming meta width minus pre-change meta width.
  final double editedWidthDiff;

  /// When non-null, [paintedBackground] returns this rect instead of applying
  /// deltas — used for the one frame between content swap and delta install so
  /// the final layout size is never painted early.
  final Rect? holdPaintedBackground;

  /// Meta top-left before the change.
  ///
  /// When non-null and [shouldAnimateMetaX], X lerps from here to the settled
  /// meta offset.
  final Offset? animateFromMetaOffset;

  /// Meta width before the change.
  ///
  /// On the hold frame, edited width is already reserved while
  /// [editedWidthDiff] is still 0. Paint uses
  /// `from.dx − (currentMetaWidth − animateFromMetaWidth)` so the wider meta
  /// still fits inside the held bubble.
  final double? animateFromMetaWidth;

  /// When true, meta X lerps from [animateFromMetaOffset] (edited enter or
  /// meaningful horizontal move).
  final bool shouldAnimateMetaX;

  /// `1 − progress` — scale factor for start deltas.
  double get oneMinusProgress => 1 - progress;

  /// Edge deltas effective at the current progress (or full while holding).
  ChatMessageChangeDeltas effectiveDeltas(Rect finalRect) {
    final hold = holdPaintedBackground;
    if (hold != null) {
      return ChatMessageChangeDeltas.between(oldRect: hold, newRect: finalRect);
    }
    if (!animateBackgroundBounds || progress >= 1) {
      return ChatMessageChangeDeltas.zero;
    }
    return deltas.scaled(oneMinusProgress);
  }

  /// Painted bubble rect: final layout rect plus scaled deltas.
  Rect paintedBackground(Rect finalRect) {
    final hold = holdPaintedBackground;
    if (hold != null) return hold;
    if (!animateBackgroundBounds || progress >= 1) return finalRect;
    final d = deltas.scaled(oneMinusProgress);
    return Rect.fromLTRB(
      finalRect.left + d.left,
      finalRect.top + d.top,
      finalRect.right + d.right,
      finalRect.bottom + d.bottom,
    );
  }

  /// Clip rect for text crossfade — painted background inset by
  /// [kChatMessageChangeClipInset].
  Rect textClipRect(Rect finalRect) {
    final bg = paintedBackground(finalRect);
    return Rect.fromLTRB(
      bg.left + kChatMessageChangeClipInset,
      bg.top + kChatMessageChangeClipInset,
      bg.right - kChatMessageChangeClipInset,
      bg.bottom - kChatMessageChangeClipInset,
    );
  }

  /// Outgoing text opacity (`1 − p`) while [animateMessageText].
  double get outgoingTextOpacity =>
      animateMessageText ? oneMinusProgress.clamp(0.0, 1.0) : 0;

  /// Incoming text opacity (`p`) while [animateMessageText]; else fully opaque.
  double get incomingTextOpacity =>
      animateMessageText ? progress.clamp(0.0, 1.0) : 1;

  /// Opacity for the “edited” label.
  double get editedLabelOpacity =>
      animateEditedEnter ? progress.clamp(0.0, 1.0) : 1;

  /// Painted meta top-left for the current progress.
  ///
  /// - Hold frame: [animateFromMetaOffset], shifted left by the live edited
  ///   width growth when [currentMetaWidth] / [animateFromMetaWidth] are known
  ///   (or by [editedWidthDiff] once installed).
  /// - [shouldAnimateMetaX]: `lerp(from, to, p)` then
  ///   `− editedWidthDiff×(1−p)`.
  /// - Else: `to.dx + δ.right` (tracks painted right edge).
  /// - Y always: `to.dy + δ.bottom − δ.top`.
  Offset metaPaintOffset({
    required Offset settledMeta,
    required Rect finalRect,
    double? currentMetaWidth,
  }) {
    final from = animateFromMetaOffset;
    if (holdPaintedBackground != null && from != null) {
      // Hold paints at the pre-change meta origin before deltas install.
      // Edited width may already be reserved while editedWidthDiff is still 0 —
      // shift by the live width delta so meta does not clip the held bubble.
      var editedShift = 0.0;
      if (animateEditedEnter) {
        final fromW = animateFromMetaWidth;
        if (currentMetaWidth != null && fromW != null) {
          editedShift = currentMetaWidth - fromW;
        } else {
          editedShift = editedWidthDiff * oneMinusProgress;
        }
      }
      return Offset(from.dx - editedShift, from.dy);
    }

    final d = effectiveDeltas(finalRect);
    final y = settledMeta.dy + d.bottom - d.top;

    if (shouldAnimateMetaX && from != null) {
      final lerpedX =
          from.dx * oneMinusProgress + settledMeta.dx * progress;
      final editedShift =
          animateEditedEnter ? editedWidthDiff * oneMinusProgress : 0.0;
      return Offset(lerpedX - editedShift, y);
    }

    return Offset(settledMeta.dx + d.right, y);
  }

  @override
  bool operator ==(Object other) =>
      other is ChatMessageChangeParams &&
      progress == other.progress &&
      deltas == other.deltas &&
      animateMessageText == other.animateMessageText &&
      animateBackgroundBounds == other.animateBackgroundBounds &&
      animateEditedEnter == other.animateEditedEnter &&
      editedWidthDiff == other.editedWidthDiff &&
      holdPaintedBackground == other.holdPaintedBackground &&
      animateFromMetaOffset == other.animateFromMetaOffset &&
      animateFromMetaWidth == other.animateFromMetaWidth &&
      shouldAnimateMetaX == other.shouldAnimateMetaX;

  @override
  int get hashCode => Object.hash(
    progress,
    deltas,
    animateMessageText,
    animateBackgroundBounds,
    animateEditedEnter,
    editedWidthDiff,
    holdPaintedBackground,
    animateFromMetaOffset,
    animateFromMetaWidth,
    shouldAnimateMetaX,
  );
}

/// Builds the starting [ChatMessageChangeParams] when a change begins (`p = 0`).
ChatMessageChangeParams beginChatMessageChange({
  required Rect oldBackground,
  required Rect newBackground,
  required bool textChanged,
  required bool editedEnter,
  required double editedWidthDiff,
  Offset? animateFromMetaOffset,
  double? animateFromMetaWidth,
  Offset? settledMetaOffset,
}) {
  final deltas = ChatMessageChangeDeltas.between(
    oldRect: oldBackground,
    newRect: newBackground,
  );
  final backgroundChanged = deltas != ChatMessageChangeDeltas.zero;
  final from = animateFromMetaOffset;
  final to = settledMetaOffset;
  final shouldAnimateX =
      editedEnter ||
      (from != null && to != null && (from.dx - to.dx).abs() > 1);
  return ChatMessageChangeParams(
    progress: 0,
    deltas: deltas,
    animateMessageText: textChanged,
    animateBackgroundBounds: backgroundChanged,
    animateEditedEnter: editedEnter,
    editedWidthDiff: editedEnter ? editedWidthDiff : 0,
    animateFromMetaOffset: from,
    animateFromMetaWidth: animateFromMetaWidth,
    shouldAnimateMetaX: shouldAnimateX,
  );
}

/// Copies [base] with an updated [progress] (same deltas / flags).
ChatMessageChangeParams chatMessageChangeAtProgress(
  ChatMessageChangeParams base,
  double progress,
) => ChatMessageChangeParams(
  progress: progress.clamp(0.0, 1.0),
  deltas: base.deltas,
  animateMessageText: base.animateMessageText,
  animateBackgroundBounds: base.animateBackgroundBounds,
  animateEditedEnter: base.animateEditedEnter,
  editedWidthDiff: base.editedWidthDiff,
  holdPaintedBackground: base.holdPaintedBackground,
  animateFromMetaOffset: base.animateFromMetaOffset,
  animateFromMetaWidth: base.animateFromMetaWidth,
  shouldAnimateMetaX: base.shouldAnimateMetaX,
);
