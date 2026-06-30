import 'dart:async';

import 'package:chatscrollview/src/chat_scroll/chat_animator.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tickHighlight', () {
    test('opacity progresses from 1.0 toward 0.0 over highlightDuration', () {
      final controller = ChatScrollController();
      final animator = ChatAnimator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        alignedTopForMessage: (_, _) => 0,
        childForId: (_) => null,
        offsetOfChild: (_) => 0,
        heightOfChild: (_) => 0,
        markNeedsPaint: () {},
        ensureTicker: () {},
        cancelFling: () {},
        cancelBounceback: () {},
        onAnimateComplete: (_) {},
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
      final animator = ChatAnimator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        alignedTopForMessage: (_, _) => 0,
        childForId: (_) => null,
        offsetOfChild: (_) => 0,
        heightOfChild: (_) => 0,
        markNeedsPaint: () {},
        ensureTicker: () {},
        cancelFling: () {},
        cancelBounceback: () {},
        onAnimateComplete: (_) {},
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
      final animator = ChatAnimator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        alignedTopForMessage: (_, _) => 0,
        childForId: (_) => null,
        offsetOfChild: (_) => 0,
        heightOfChild: (_) => 0,
        markNeedsPaint: () => painted = true,
        ensureTicker: () {},
        cancelFling: () {},
        cancelBounceback: () {},
        onAnimateComplete: (_) {},
      );

      animator.animateCompleter = Completer<void>();
      animator.fadeOpacity = 0.3;

      animator.cancelAnimate();

      expect(animator.fadeOpacity, 1.0);
      expect(animator.isAnimating, isFalse);
      expect(painted, isTrue);
    });
  });
}
