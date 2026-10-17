import 'package:flutter/animation.dart';
import 'package:flutter/widgets.dart' show MagnifierInfo, Offset, Rect, Size;

import 'selection_handle_motion.dart' show smoothMagnifierInfo;

/// Phase of moving-handle chrome during / after a handle drag.
enum HandleDragChromePhase {
  /// Not dragging; overlay sits on the caret anchor.
  idle,

  /// Finger down; overlay follows `pointer + grabOffset`.
  dragging,

  /// Finger up; overlay eases toward the caret anchor.
  settling,
}

/// Observable outputs of [computeHandleDragChrome].
class HandleDragChrome {
  /// Creates drag-chrome outputs.
  const HandleDragChrome({
    required this.handleOverlay,
    required this.magnifierInfo,
    required this.settleProgress,
  });

  /// Visual position of the moving handle overlay.
  final Offset handleOverlay;

  /// Smoothed (or target) magnifier info for the pointer-line focal.
  final MagnifierInfo magnifierInfo;

  /// Settle progress in `0…1` after easeOut (`1` = at caret).
  final double settleProgress;
}

/// Builds the **pointer-line** magnifier target (not yet smoothed).
///
/// Focal X = [pointer] X clamped to [lineBounds]; focal Y = line center.
MagnifierInfo pointerLineMagnifierTarget({
  required Offset pointer,
  required Rect lineBounds,
  required Rect fieldBounds,
  required Size caretSize,
}) {
  final double focalX = pointer.dx.clamp(lineBounds.left, lineBounds.right);
  final double focalY = lineBounds.center.dy;
  final Offset focal = Offset(focalX, focalY);
  return MagnifierInfo(
    globalGesturePosition: focal,
    caretRect: Rect.fromCenter(
      center: focal,
      width: caretSize.width.clamp(1.0, double.infinity),
      height: caretSize.height.clamp(1.0, double.infinity),
    ),
    currentLineBoundaries: lineBounds,
    fieldBounds: fieldBounds,
  );
}

/// Sole unit-test seam for editable handle drag-chrome math.
///
/// - **dragging:** overlay = [pointer] + [grabOffset], clamped to
///   [fieldBounds]; pointer-line magnifier.
/// - **settling:** overlay eases from drag overlay to [caretAnchor]
///   with [Curves.easeOut] over [settleT] in `0…1` (time fraction; see
///   [settleTForElapsed] for the ~250ms mapping).
/// - **idle:** overlay = [caretAnchor]; settle progress = 1.
HandleDragChrome computeHandleDragChrome({
  required HandleDragChromePhase phase,
  required Offset pointer,
  required Offset grabOffset,
  required Offset caretAnchor,
  required Rect lineBounds,
  required Rect fieldBounds,
  required Size caretSize,
  required MagnifierInfo? previousMagnifier,
  required Duration magnifierElapsed,
  double settleT = 0,
}) {
  final Offset rawDragOverlay = pointer + grabOffset;
  final Offset dragOverlay = Offset(
    rawDragOverlay.dx.clamp(fieldBounds.left, fieldBounds.right),
    rawDragOverlay.dy.clamp(fieldBounds.top, fieldBounds.bottom),
  );

  final Offset handleOverlay;
  final double settleProgress;
  switch (phase) {
    case HandleDragChromePhase.idle:
      handleOverlay = caretAnchor;
      settleProgress = 1;
    case HandleDragChromePhase.dragging:
      handleOverlay = dragOverlay;
      settleProgress = 0;
    case HandleDragChromePhase.settling:
      final double t = settleT.clamp(0.0, 1.0);
      settleProgress = Curves.easeOut.transform(t);
      handleOverlay = Offset.lerp(dragOverlay, caretAnchor, settleProgress)!;
  }

  final MagnifierInfo target = pointerLineMagnifierTarget(
    pointer: pointer,
    lineBounds: lineBounds,
    fieldBounds: fieldBounds,
    caretSize: caretSize,
  );
  final MagnifierInfo magnifierInfo = smoothMagnifierInfo(
    previous: previousMagnifier,
    target: target,
    elapsed: magnifierElapsed,
  );

  return HandleDragChrome(
    handleOverlay: handleOverlay,
    magnifierInfo: magnifierInfo,
    settleProgress: settleProgress,
  );
}
