import 'package:chat_scroll_view/src/chat_scroll/chat_animator.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

ChatAnimator _animator({
  required ChatScrollController controller,
  double? Function(int id)? offsetToBuiltMessage,
  double Function(int targetId, double messageHeight, double alignment)?
  closePathEndOffsetFor,
  bool Function(int targetId)? isTailClosePathTarget,
  RenderBox? Function(int id)? childForId,
  double Function(RenderBox child)? offsetOfChild,
  double Function(RenderBox child)? heightOfChild,
  VoidCallback? markNeedsPaint,
  VoidCallback? markNeedsLayout,
  VoidCallback? ensureTicker,
  VoidCallback? cancelFling,
  VoidCallback? cancelBounceback,
  void Function(int targetId)? prepareStitchCapture,
  VoidCallback? clearStitchCapture,
  bool Function(int id)? isHighlightReady,
  bool Function(int id)? shouldDropPendingHighlight,
  Duration highlightDuration = const Duration(milliseconds: 1500),
  Color highlightColor = const Color(0x402196F3),
  Duration preferBuiltTimeout = kPreferBuiltTimeout,
}) => ChatAnimator(
  controller: controller,
  offsetToBuiltMessage: offsetToBuiltMessage ?? (_) => null,
  closePathEndOffsetFor:
      closePathEndOffsetFor ?? (_, _, alignment) => 40.0 * alignment,
  isTailClosePathTarget: isTailClosePathTarget ?? (_) => false,
  childForId: childForId ?? (_) => null,
  offsetOfChild: offsetOfChild ?? (_) => 0,
  heightOfChild: heightOfChild ?? (_) => 0,
  isHighlightReady: isHighlightReady ?? (_) => true,
  shouldDropPendingHighlight: shouldDropPendingHighlight ?? (_) => false,
  markNeedsPaint: markNeedsPaint ?? () {},
  markNeedsLayout: markNeedsLayout ?? () {},
  ensureTicker: ensureTicker ?? () {},
  cancelFling: cancelFling ?? () {},
  cancelBounceback: cancelBounceback ?? () {},
  prepareStitchCapture: prepareStitchCapture ?? (_) {},
  clearStitchCapture: clearStitchCapture ?? () {},
  highlightDuration: highlightDuration,
  highlightColor: highlightColor,
  preferBuiltTimeout: preferBuiltTimeout,
);

RenderBox _sizedBox({double height = 60}) {
  final box = RenderConstrainedBox(
    additionalConstraints: BoxConstraints.tightFor(height: height),
  );
  box.layout(BoxConstraints.tightFor(width: 400, height: height));
  return box;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tickHighlight', () {
    test('opacity progresses from 1.0 toward 0.0 over highlightDuration', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        highlightDuration: const Duration(milliseconds: 1000),
      );

      animator.highlightTargetId = 42;
      animator.highlightFactor = 1.0;

      const start = Duration(seconds: 1);
      expect(animator.tickHighlight(start), isTrue);
      expect(animator.highlightFactor, 1.0);

      expect(
        animator.tickHighlight(start + const Duration(milliseconds: 500)),
        isTrue,
      );
      expect(animator.highlightFactor, closeTo(0.5, 0.001));

      expect(
        animator.tickHighlight(start + const Duration(milliseconds: 1000)),
        isFalse,
      );
      expect(animator.highlightTargetId, isNull);
      expect(animator.highlightFactor, 0.0);
    });

    test('highlightDuration zero clears immediately', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        highlightDuration: Duration.zero,
      );

      animator.highlightTargetId = 1;
      animator.highlightFactor = 1.0;

      expect(animator.tickHighlight(Duration.zero), isFalse);
      expect(animator.highlightTargetId, isNull);
    });
  });

  group('cancelAnimate', () {
    test('clears stitch state and completes', () {
      final controller = ChatScrollController();
      var cleared = false;
      final animator = _animator(
        controller: controller,
        clearStitchCapture: () => cleared = true,
      );

      animator.animate(
        9,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.immediate,
        highlight: false,
      );
      expect(animator.farAnimateActive, isTrue);

      animator.cancelAnimate();

      expect(animator.isAnimating, isFalse);
      expect(animator.farAnimateActive, isFalse);
      expect(cleared, isTrue);
      expect(animator.fadeOpacity, 1.0);
    });
  });

  group('animate coalesce / short-circuit', () {
    test('same target while in flight returns the same future', () async {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
      );

      final first = animator.animate(
        42,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.immediate,
        highlight: false,
      );
      expect(animator.farAnimateActive, isTrue);

      final second = animator.animate(
        42,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.immediate,
        highlight: false,
      );

      expect(identical(first, second), isTrue);
      expect(animator.farAnimateActive, isTrue);

      animator.cancelAnimate();
      await first;
    });

    test('different target while in flight is ignored', () async {
      final controller = ChatScrollController();
      var clearCount = 0;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        clearStitchCapture: () => clearCount++,
      );

      final first = animator.animate(
        1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        highlight: false,
      );
      expect(animator.animateTargetId, 1);
      expect(animator.farAnimateActive, isTrue);
      final clearsAfterStart = clearCount;

      await animator.animate(
        2,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        highlight: false,
      );

      expect(animator.animateTargetId, 1);
      expect(animator.farAnimateActive, isTrue);
      expect(clearCount, clearsAfterStart);

      animator.cancelAnimate();
      await first;
    });

    test('already at aligned end short-circuits', () async {
      final controller = ChatScrollController();
      final box = _sizedBox();
      var stitchPrep = 0;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 0.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
        prepareStitchCapture: (_) => stitchPrep++,
      );

      await animator.animate(
        7,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        highlight: false,
      );

      expect(animator.isAnimating, isFalse);
      expect(stitchPrep, 0);
      expect(animator.farAnimateActive, isFalse);
    });
  });

  group('animate path selection', () {
    test('close path when target offset is within kCloseAnimateDistance', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 120.0,
        closePathEndOffsetFor: (_, _, alignment) => 40.0 * alignment,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
      );

      animator.animate(
        5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );

      expect(animator.farAnimateActive, isFalse);
      expect(animator.preferBuiltWaiting, isFalse);
      expect(animator.animateStartOffset, 120.0);
      expect(animator.animateEndOffset, 0.0);
      expect(controller.anchorMessageId, 5);
      expect(controller.anchorPixelOffset, 120.0);
    });

    test('preferBuilt waits when target is not built', () {
      final controller = ChatScrollController();
      var layoutAsked = false;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        markNeedsLayout: () => layoutAsked = true,
      );

      animator.animate(
        99,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.preferBuilt,
      );

      expect(animator.preferBuiltWaiting, isTrue);
      expect(animator.farAnimateActive, isFalse);
      expect(layoutAsked, isTrue);
    });

    test('immediate stitches when target is not built', () {
      final controller = ChatScrollController();
      var captured = false;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        prepareStitchCapture: (_) => captured = true,
      );

      animator.animate(
        99,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );

      expect(animator.farAnimateActive, isTrue);
      expect(animator.farAnimateJumped, isTrue);
      expect(captured, isTrue);
      expect(controller.anchorMessageId, 99);
    });

    test('far path when target offset exceeds kCloseAnimateDistance', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => kCloseAnimateDistance + 1,
      );

      animator.animate(
        1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );

      expect(animator.farAnimateActive, isTrue);
      expect(animator.farAnimateJumped, isTrue);
    });

    test('preferBuilt becomes close path once target builds nearby', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      double? offset;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => offset,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
      );

      animator.animate(
        5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.preferBuilt,
        highlight: false,
      );
      expect(animator.preferBuiltWaiting, isTrue);

      offset = 80.0;
      animator.onLayoutOpportunity(viewportHeight: 600);
      expect(animator.preferBuiltWaiting, isFalse);
      expect(animator.farAnimateActive, isFalse);
      expect(controller.anchorMessageId, 5);
    });

    test('preferBuilt times out into stitch', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        preferBuiltTimeout: Duration.zero,
      );

      animator.animate(
        99,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.preferBuilt,
        highlight: false,
      );
      expect(animator.preferBuiltWaiting, isTrue);

      animator.tickAnimate(Duration.zero);
      expect(animator.preferBuiltWaiting, isFalse);
      expect(animator.farAnimateActive, isTrue);
      expect(animator.farAnimateJumped, isTrue);
    });

    test('zero duration jumps without arming animation', () {
      final controller = ChatScrollController();
      final animator = _animator(controller: controller);

      animator.animate(7, duration: Duration.zero, curve: Curves.linear);

      expect(animator.isAnimating, isFalse);
      expect(controller.anchorMessageId, 7);
    });
  });

  group('tickAnimate', () {
    test('close path returns anchor delta and completes', () {
      final controller = ChatScrollController()..reassignAnchor(1, 100);
      final box = _sizedBox();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 100.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
      );

      animator.animate(
        1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        highlight: false,
      );

      expect(animator.tickAnimate(Duration.zero), closeTo(0.0, 0.001));

      final midDelta = animator.tickAnimate(const Duration(milliseconds: 50));
      expect(midDelta, lessThan(0.0));

      expect(
        animator.tickAnimate(const Duration(milliseconds: 100)),
        0.0,
        reason: 'final tick applies settle in render, not via stale delta',
      );
      expect(animator.isAnimating, isFalse);
      expect(animator.takePendingSettleTargetId(), 1);
      expect(animator.takePendingSettleTargetId(), isNull);
    });

    test('close path tail target uses tail-pin end offset', () {
      final controller = ChatScrollController();
      const tailHeight = 900.0;
      const bottomEdge = 600.0;
      const tailEnd = bottomEdge - tailHeight;
      final box = _sizedBox(height: tailHeight);
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 200.0,
        closePathEndOffsetFor: (targetId, height, alignment) {
          if (targetId == 9) return bottomEdge - height;
          return 0.0;
        },
        isTailClosePathTarget: (id) => id == 9,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
      );

      animator.animate(
        9,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        highlight: false,
      );

      expect(animator.animateEndOffset, tailEnd);
      animator.tickAnimate(Duration.zero);
      animator.tickAnimate(const Duration(milliseconds: 100));
      expect(controller.anchorPixelOffset, closeTo(tailEnd, 0.001));
    });

    test('rebaseClosePathEnd retargets when aligned end moves', () {
      final controller = ChatScrollController()..reassignAnchor(1, 200);
      final box = _sizedBox(height: 60);
      var alignedEnd = 100.0;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 200.0,
        closePathEndOffsetFor: (_, _, _) => alignedEnd,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
      );

      animator.animate(
        1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        alignment: 0.5,
        highlight: false,
      );

      animator.tickAnimate(const Duration(milliseconds: 25));
      alignedEnd = 160.0;
      animator.rebaseClosePathEnd(elapsed: const Duration(milliseconds: 25));
      animator.tickAnimate(const Duration(milliseconds: 50));
      expect(animator.animateEndOffset, 160.0);
      expect(animator.animateStartOffset, controller.anchorPixelOffset);
    });

    test('stitch advances progress after measure and completes', () {
      final controller = ChatScrollController();
      var cleared = false;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        clearStitchCapture: () => cleared = true,
      );

      animator.animate(
        42,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        alignment: 0.25,
        highlight: false,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );

      expect(animator.farAnimateJumped, isTrue);
      expect(controller.anchorMessageId, 42);
      expect(animator.stitchMeasured, isFalse);

      // Waiting for measure — progress stays 0.
      animator.tickAnimate(const Duration(milliseconds: 10));
      expect(animator.stitchProgress, 0.0);
      expect(animator.isAnimating, isTrue);

      animator.applyStitchMeasure(
        scrollLength: 400,
        towardNewer: false,
        viewportHeight: 600,
      );
      expect(animator.stitchMeasured, isTrue);
      expect(
        animator.animateDuration.inMilliseconds,
        greaterThanOrEqualTo(300),
      );

      // Clock starts at measure (or first tick after). Drive past duration.
      const start = Duration(milliseconds: 100);
      animator.tickAnimate(start);
      expect(animator.stitchProgress, lessThan(1.0));
      animator.tickAnimate(start + animator.animateDuration);
      expect(animator.isAnimating, isFalse);
      expect(animator.stitchProgress, 0.0);
      expect(cleared, isTrue);
    });
  });

  group('paintHighlight', () {
    test('uses normalized .a channel scaled by highlightFactor', () {
      const base = Color(0x402196F3);
      const factor = 0.5;
      final alpha = (base.a * factor).clamp(0.0, 1.0);
      final painted = base.withValues(alpha: alpha);
      expect(painted.a, closeTo(base.a * factor, 0.001));
    });

    PaintingContext context() =>
        PaintingContext(ContainerLayer(), const Rect.fromLTWH(0, 0, 400, 600));

    test('no-op when no highlight target', () {
      final animator = _animator(controller: ChatScrollController());
      expect(
        () => animator.paintHighlight(
          context: context(),
          offset: Offset.zero,
          viewportWidth: 400,
          viewportHeight: 600,
        ),
        returnsNormally,
      );
    });

    test('no-op when target is culled off-screen', () {
      final box = _sizedBox();
      final animator =
          _animator(
              controller: ChatScrollController(),
              childForId: (_) => box,
              offsetOfChild: (_) => 700.0,
              heightOfChild: (_) => box.size.height,
            )
            ..highlightTargetId = 1
            ..highlightFactor = 1.0;

      expect(
        () => animator.paintHighlight(
          context: context(),
          offset: Offset.zero,
          viewportWidth: 400,
          viewportHeight: 600,
        ),
        returnsNormally,
      );
    });

    test('no-op when highlightFactor is zero', () {
      final box = _sizedBox();
      final animator =
          _animator(
              controller: ChatScrollController(),
              childForId: (_) => box,
              offsetOfChild: (_) => 80.0,
              heightOfChild: (_) => box.size.height,
            )
            ..highlightTargetId = 1
            ..highlightFactor = 0.0;

      expect(
        () => animator.paintHighlight(
          context: context(),
          offset: Offset.zero,
          viewportWidth: 400,
          viewportHeight: 600,
        ),
        returnsNormally,
      );
    });
  });

  group('deferred highlight', () {
    test('defers arm until isHighlightReady', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      var ready = false;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 100.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
        isHighlightReady: (_) => ready,
        highlightDuration: const Duration(milliseconds: 500),
      );

      animator.animate(
        1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      animator.tickAnimate(const Duration(seconds: 1));
      animator.tickAnimate(const Duration(seconds: 1, milliseconds: 100));

      expect(animator.highlightTargetId, isNull);
      expect(animator.pendingHighlightTargetId, 1);

      ready = true;
      expect(animator.tryArmPendingHighlight(), isTrue);
      expect(animator.highlightTargetId, 1);
      expect(animator.pendingHighlightTargetId, isNull);
    });

    test('defers when message is loaded but child is not built yet', () {
      final controller = ChatScrollController();
      RenderBox? child;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 100.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => child,
        heightOfChild: (_) => child?.size.height ?? 0,
        isHighlightReady: (_) => child != null,
        highlightDuration: const Duration(milliseconds: 500),
      );

      animator.animate(
        1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      animator.tickAnimate(const Duration(seconds: 1));
      animator.tickAnimate(const Duration(seconds: 1, milliseconds: 100));

      expect(animator.highlightTargetId, isNull);
      expect(animator.pendingHighlightTargetId, 1);

      child = _sizedBox();
      expect(animator.tryArmPendingHighlight(), isTrue);
      expect(animator.highlightTargetId, 1);
    });

    test('arms immediately when message and child are ready at settle', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 100.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
        isHighlightReady: (_) => true,
        highlightDuration: const Duration(milliseconds: 500),
      );

      animator.animate(
        1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      animator.tickAnimate(const Duration(seconds: 1));
      animator.tickAnimate(const Duration(seconds: 1, milliseconds: 100));

      expect(animator.pendingHighlightTargetId, isNull);
      expect(animator.highlightTargetId, 1);
      expect(animator.highlightFactor, 1.0);
    });

    test('drops pending highlight when shouldDropPendingHighlight', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        isHighlightReady: (_) => false,
        shouldDropPendingHighlight: (_) => true,
      )..pendingHighlightTargetId = 9;

      expect(animator.tryArmPendingHighlight(), isFalse);
      expect(animator.pendingHighlightTargetId, isNull);
      expect(animator.highlightTargetId, isNull);
    });

    test('clearHighlight drops pending arm', () {
      final animator = _animator(controller: ChatScrollController())
        ..pendingHighlightTargetId = 3;

      animator.clearHighlight();

      expect(animator.pendingHighlightTargetId, isNull);
    });
  });
}
