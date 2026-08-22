import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_animator.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('animateTo returns ignored when busy under ignore policy', () async {
    final controller = ChatScrollController();
    final animator = ChatAnimator(
      controller: controller,
      offsetToBuiltMessage: (_) => null,
      messageIntersectsPaintBand: (_) => false,
      viewportHeight: () => 600.0,
      closePathEndOffsetFor: (_, _, alignment) => 40.0 * alignment,
      isTailClosePathTarget: (_) => false,
      childForId: (_) => null,
      offsetOfChild: (_) => 0,
      heightOfChild: (_) => 0,
      isHighlightReady: (_) => true,
      shouldDropPendingHighlight: (_) => false,
      isDestinationReady: (_) => true,
      requestDestinationWindow: (_) {},
      clearDestinationWindow: () {},
      markNeedsPaint: () {},
      markNeedsLayout: () {},
      ensureTicker: () {},
      cancelFling: () {},
      cancelBounceback: () {},
      prepareStitchCapture: (_) {},
      onStitchCancelled: (_) {},
      onStitchComplete: (_) {},
      stitchMeasureDeferReason: () => null,
    );
    controller.animator = animator;

    final first = controller.animateTo(
      1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
      highlight: false,
    );
    expect(controller.isAnimating, isTrue);

    final second = await controller.animateTo(
      2,
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
      highlight: false,
      busyPolicy: AnimateToBusyPolicy.ignore,
    );
    expect(second, AnimateToDisposition.ignored);
    expect(animator.animateTargetId, 1);

    animator.cancel();
    await first;
  });
}
