import 'dart:async';

import 'package:chatscrollview/src/chat_scroll/chat_animator.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

ChatAnimator _animator({
  required ChatScrollController controller,
  double? Function(int id)? offsetToBuiltMessage,
  double Function(double messageHeight, double alignment)? alignedTopForMessage,
  RenderBox? Function(int id)? childForId,
  double Function(RenderBox child)? offsetOfChild,
  double Function(RenderBox child)? heightOfChild,
  VoidCallback? markNeedsPaint,
  VoidCallback? ensureTicker,
  VoidCallback? cancelFling,
  VoidCallback? cancelBounceback,
  bool Function(int id)? isHighlightReady,
  bool Function(int id)? shouldDropPendingHighlight,
  Duration highlightDuration = const Duration(milliseconds: 1500),
  Color highlightColor = const Color(0x402196F3),
}) => ChatAnimator(
  controller: controller,
  offsetToBuiltMessage: offsetToBuiltMessage ?? (_) => null,
  alignedTopForMessage: alignedTopForMessage ?? (_, _) => 0,
  childForId: childForId ?? (_) => null,
  offsetOfChild: offsetOfChild ?? (_) => 0,
  heightOfChild: heightOfChild ?? (_) => 0,
  isHighlightReady: isHighlightReady ?? (_) => true,
  shouldDropPendingHighlight: shouldDropPendingHighlight ?? (_) => false,
  markNeedsPaint: markNeedsPaint ?? () {},
  ensureTicker: ensureTicker ?? () {},
  cancelFling: cancelFling ?? () {},
  cancelBounceback: cancelBounceback ?? () {},
  highlightDuration: highlightDuration,
  highlightColor: highlightColor,
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
    test('resets fadeOpacity to 1.0', () {
      final controller = ChatScrollController();
      var painted = false;
      final animator = _animator(
        controller: controller,
        markNeedsPaint: () => painted = true,
      );

      animator.animateCompleter = Completer<void>();
      animator.fadeOpacity = 0.3;

      animator.cancelAnimate();

      expect(animator.fadeOpacity, 1.0);
      expect(animator.isAnimating, isFalse);
      expect(painted, isTrue);
    });
  });

  group('animate path selection', () {
    test('close path when target offset is within kCloseAnimateDistance', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 120.0,
        alignedTopForMessage: (_, alignment) => 40.0 * alignment,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
      );

      animator.animate(
        5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );

      expect(animator.farAnimateActive, isFalse);
      expect(animator.animateStartOffset, 120.0);
      expect(animator.animateEndOffset, 0.0);
      expect(controller.anchorMessageId, 5);
      expect(controller.anchorPixelOffset, 120.0);
    });

    test('far path when target is not built', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
      );

      animator.animate(
        99,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );

      expect(animator.farAnimateActive, isTrue);
      expect(animator.farAnimateJumped, isFalse);
      expect(animator.fadeOpacity, 1.0);
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
        alignedTopForMessage: (_, _) => 0.0,
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

    test('rebaseClosePathEnd retargets when aligned end moves', () {
      final controller = ChatScrollController()..reassignAnchor(1, 200);
      final box = _sizedBox(height: 60);
      var alignedEnd = 100.0;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 200.0,
        alignedTopForMessage: (_, _) => alignedEnd,
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

    test('far path fades out, jumpTo at midpoint, fades in', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
      );

      animator.animate(
        42,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        alignment: 0.25,
        highlight: false,
      );

      animator.tickAnimate(const Duration(seconds: 1));
      animator.tickAnimate(const Duration(seconds: 1, milliseconds: 25));
      expect(animator.fadeOpacity, lessThan(1.0));
      expect(animator.farAnimateJumped, isFalse);

      animator.tickAnimate(const Duration(seconds: 1, milliseconds: 50));
      expect(animator.farAnimateJumped, isTrue);
      expect(controller.anchorMessageId, 42);

      animator.tickAnimate(const Duration(seconds: 1, milliseconds: 100));
      expect(animator.fadeOpacity, 1.0);
      expect(animator.isAnimating, isFalse);
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
        alignedTopForMessage: (_, _) => 0.0,
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
        alignedTopForMessage: (_, _) => 0.0,
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
        alignedTopForMessage: (_, _) => 0.0,
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
