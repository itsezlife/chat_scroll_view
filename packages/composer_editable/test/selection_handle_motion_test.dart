import 'package:composer_editable/src/widget/handle_drag_chrome.dart';
import 'package:composer_editable/src/widget/selection_handle_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OvershootCurve', () {
    test('starts at 0 and ends at 1', () {
      const curve = OvershootCurve();
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
    });

    test('overshoots above 1 near the end', () {
      const curve = OvershootCurve();
      // Android OvershootInterpolator peaks above 1 before settling.
      expect(curve.transform(0.85), greaterThan(1.0));
    });
  });

  group('smoothMagnifierInfo', () {
    const previous = MagnifierInfo(
      globalGesturePosition: Offset(0, 0),
      caretRect: Rect.fromLTWH(0, 0, 10, 20),
      currentLineBoundaries: Rect.fromLTWH(0, 0, 100, 20),
      fieldBounds: Rect.fromLTWH(0, 0, 200, 200),
    );
    const target = MagnifierInfo(
      globalGesturePosition: Offset(100, 100),
      caretRect: Rect.fromLTWH(100, 100, 10, 20),
      currentLineBoundaries: Rect.fromLTWH(0, 100, 100, 20),
      fieldBounds: Rect.fromLTWH(0, 0, 200, 200),
    );

    test('returns target when previous is null', () {
      expect(
        smoothMagnifierInfo(
          previous: null,
          target: target,
          elapsed: const Duration(milliseconds: 16),
        ),
        target,
      );
    });

    test('X and Y advance at the same AOSP ~100ms rate', () {
      final smoothed = smoothMagnifierInfo(
        previous: previous,
        target: target,
        elapsed: const Duration(milliseconds: 16),
      );
      // 16/100 of remaining on both axes (AOSP MagnifierMotionAnimator parity).
      expect(smoothed.globalGesturePosition.dx, closeTo(16, 0.01));
      expect(smoothed.globalGesturePosition.dy, closeTo(16, 0.01));
    });

    test('settles to target when elapsed is large', () {
      final smoothed = smoothMagnifierInfo(
        previous: previous,
        target: target,
        elapsed: const Duration(milliseconds: 500),
      );
      expect(smoothed.globalGesturePosition, target.globalGesturePosition);
      expect(smoothed.caretRect, target.caretRect);
    });
  });

  group('magnifierInfoSettled', () {
    test('true when infos match', () {
      const info = MagnifierInfo(
        globalGesturePosition: Offset(10, 20),
        caretRect: Rect.fromLTWH(1, 2, 3, 4),
        currentLineBoundaries: Rect.fromLTWH(0, 0, 50, 10),
        fieldBounds: Rect.fromLTWH(0, 0, 100, 100),
      );
      expect(magnifierInfoSettled(info, info), isTrue);
    });

    test('false when gesture X differs', () {
      const a = MagnifierInfo(
        globalGesturePosition: Offset(0, 0),
        caretRect: Rect.zero,
        currentLineBoundaries: Rect.zero,
        fieldBounds: Rect.zero,
      );
      const b = MagnifierInfo(
        globalGesturePosition: Offset(10, 0),
        caretRect: Rect.zero,
        currentLineBoundaries: Rect.zero,
        fieldBounds: Rect.zero,
      );
      expect(magnifierInfoSettled(a, b), isFalse);
    });
  });

  group('computeHandleDragChrome', () {
    const line = Rect.fromLTWH(0, 40, 200, 20);
    const field = Rect.fromLTWH(0, 0, 300, 400);
    const caretAnchor = Offset(80, 60);
    const caretSize = Size(10, 20);

    HandleDragChrome chrome({
      required HandleDragChromePhase phase,
      Offset pointer = const Offset(100, 200),
      Offset grabOffset = const Offset(-5, -10),
      MagnifierInfo? previousMagnifier,
      Duration magnifierElapsed = const Duration(milliseconds: 16),
      double settleT = 0,
    }) {
      return computeHandleDragChrome(
        phase: phase,
        pointer: pointer,
        grabOffset: grabOffset,
        caretAnchor: caretAnchor,
        lineBounds: line,
        fieldBounds: field,
        caretSize: caretSize,
        previousMagnifier: previousMagnifier,
        magnifierElapsed: magnifierElapsed,
        settleT: settleT,
      );
    }

    test('dragging: overlay is pointer + grabOffset', () {
      final result = chrome(
        phase: HandleDragChromePhase.dragging,
        pointer: const Offset(120, 180),
        grabOffset: const Offset(-8, -12),
      );
      expect(result.handleOverlay, const Offset(112, 168));
      expect(result.settleProgress, 0);
    });

    test('dragging: overlay clamps inside fieldBounds', () {
      final result = chrome(
        phase: HandleDragChromePhase.dragging,
        pointer: const Offset(-50, -80),
        grabOffset: Offset.zero,
      );
      expect(result.handleOverlay, Offset.zero);
    });

    test('idle: overlay is caret anchor', () {
      final result = chrome(phase: HandleDragChromePhase.idle);
      expect(result.handleOverlay, caretAnchor);
      expect(result.settleProgress, 1);
    });

    test(
      'dragging: pointer-line magnifier clamps X to line, Y is line center',
      () {
        final result = chrome(
          phase: HandleDragChromePhase.dragging,
          pointer: const Offset(250, 300), // X past line.right, Y far below
          previousMagnifier: null,
        );
        final MagnifierInfo info = result.magnifierInfo;
        expect(info.globalGesturePosition.dx, line.right);
        expect(info.globalGesturePosition.dy, line.center.dy);
        expect(info.caretRect.center.dx, line.right);
        expect(info.caretRect.center.dy, line.center.dy);
        expect(info.currentLineBoundaries, line);
      },
    );

    test('dragging: pointer X below line.left clamps to left', () {
      final result = chrome(
        phase: HandleDragChromePhase.dragging,
        pointer: const Offset(-20, 50),
        previousMagnifier: null,
      );
      expect(result.magnifierInfo.globalGesturePosition.dx, line.left);
    });

    test('settling: easeOut progress lerps overlay toward caret', () {
      const pointer = Offset(100, 200);
      const grab = Offset(0, 0);
      final start = pointer + grab;

      final mid = chrome(
        phase: HandleDragChromePhase.settling,
        pointer: pointer,
        grabOffset: grab,
        settleT: 0.5,
      );
      expect(mid.settleProgress, closeTo(Curves.easeOut.transform(0.5), 0.001));
      expect(
        mid.handleOverlay.dx,
        closeTo(
          start.dx + (caretAnchor.dx - start.dx) * mid.settleProgress,
          0.01,
        ),
      );
      expect(
        mid.handleOverlay.dy,
        closeTo(
          start.dy + (caretAnchor.dy - start.dy) * mid.settleProgress,
          0.01,
        ),
      );

      final done = chrome(
        phase: HandleDragChromePhase.settling,
        pointer: pointer,
        grabOffset: grab,
        settleT: 1,
      );
      expect(done.settleProgress, 1);
      expect(done.handleOverlay, caretAnchor);
    });

    test('settleTForElapsed maps 250ms to 1 and half duration to 0.5', () {
      expect(settleTForElapsed(Duration.zero), 0);
      expect(settleTForElapsed(kHandleSettleDuration), 1);
      expect(
        settleTForElapsed(const Duration(milliseconds: 125)),
        closeTo(0.5, 0.001),
      );
    });

    test('dragging: magnifier smooth uses unified ~100ms from previous', () {
      final previous = MagnifierInfo(
        globalGesturePosition: const Offset(0, 40),
        caretRect: Rect.fromCenter(
          center: const Offset(0, 40),
          width: 10,
          height: 20,
        ),
        currentLineBoundaries: line,
        fieldBounds: field,
      );
      // Pointer at line right → target (200, 50).
      final result = chrome(
        phase: HandleDragChromePhase.dragging,
        pointer: const Offset(200, 999),
        previousMagnifier: previous,
        magnifierElapsed: const Duration(milliseconds: 16),
      );
      // 16/100 toward (200, 50) from (0, 40).
      expect(result.magnifierInfo.globalGesturePosition.dx, closeTo(32, 0.5));
      expect(result.magnifierInfo.globalGesturePosition.dy, closeTo(41.6, 0.5));
    });
  });
}
