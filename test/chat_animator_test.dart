import 'package:chat_scroll_view/src/chat_scroll/chat_animator.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

ChatAnimator _animator({
  required ChatScrollController controller,
  double? Function(int id)? offsetToBuiltMessage,
  bool Function(int id)? messageIntersectsPaintBand,
  double Function()? viewportHeight,
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
  void Function(StitchCancelSnapshot snapshot)? onStitchCancelled,
  void Function(StitchCancelSnapshot snapshot)? onStitchComplete,
  bool Function(int id)? isHighlightReady,
  bool Function(int id)? shouldDropPendingHighlight,
  bool Function(int id)? isDestinationReady,
  void Function(int id)? requestDestinationWindow,
  VoidCallback? clearDestinationWindow,
  Duration highlightDuration = const Duration(
    milliseconds: kHighlightHoldDurationMs,
  ),
  Color highlightColor = const Color(0x280A90F0),
}) => ChatAnimator(
  controller: controller,
  offsetToBuiltMessage: offsetToBuiltMessage ?? (_) => null,
  messageIntersectsPaintBand: messageIntersectsPaintBand ?? (_) => false,
  viewportHeight: viewportHeight ?? () => 600.0,
  closePathEndOffsetFor:
      closePathEndOffsetFor ?? (_, _, alignment) => 40.0 * alignment,
  isTailClosePathTarget: isTailClosePathTarget ?? (_) => false,
  childForId: childForId ?? (_) => null,
  offsetOfChild: offsetOfChild ?? (_) => 0,
  heightOfChild: heightOfChild ?? (_) => 0,
  isHighlightReady: isHighlightReady ?? (_) => true,
  shouldDropPendingHighlight: shouldDropPendingHighlight ?? (_) => false,
  isDestinationReady: isDestinationReady ?? (_) => true,
  requestDestinationWindow: requestDestinationWindow ?? (_) {},
  clearDestinationWindow: clearDestinationWindow ?? () {},
  markNeedsPaint: markNeedsPaint ?? () {},
  markNeedsLayout: markNeedsLayout ?? () {},
  ensureTicker: ensureTicker ?? () {},
  cancelFling: cancelFling ?? () {},
  cancelBounceback: cancelBounceback ?? () {},
  prepareStitchCapture: prepareStitchCapture ?? (_) {},
  onStitchCancelled: onStitchCancelled ?? (_) {},
  onStitchComplete: onStitchComplete ?? (_) {},
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
    test('solid hold then fade over kHighlightFadeDuration', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        highlightDuration: const Duration(milliseconds: 1000),
      );

      animator
        ..highlightTargetId = 42
        ..highlightPhase = ChatHighlightPhase.solid
        ..highlightFactor = 1.0
        ..startHighlightHold();

      const start = Duration(seconds: 1);
      expect(animator.tickHighlight(start), isTrue);
      expect(animator.highlightFactor, 1.0);
      expect(animator.highlightPhase, ChatHighlightPhase.solid);

      // Mid-hold — still solid.
      expect(
        animator.tickHighlight(start + const Duration(milliseconds: 500)),
        isTrue,
      );
      expect(animator.highlightFactor, 1.0);
      expect(animator.highlightPhase, ChatHighlightPhase.solid);

      // Hold elapsed → fade begins.
      expect(
        animator.tickHighlight(start + const Duration(milliseconds: 1000)),
        isTrue,
      );
      expect(animator.highlightPhase, ChatHighlightPhase.fading);
      expect(animator.highlightFactor, 1.0);

      expect(
        animator.tickHighlight(start + const Duration(milliseconds: 1150)),
        isTrue,
      );
      expect(animator.highlightFactor, closeTo(0.5, 0.001));

      expect(
        animator.tickHighlight(start + const Duration(milliseconds: 1300)),
        isFalse,
      );
      expect(animator.highlightTargetId, isNull);
      expect(animator.highlightFactor, 0.0);
      expect(animator.highlightPhase, ChatHighlightPhase.idle);
    });

    test('highlightDuration zero clears immediately', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        highlightDuration: Duration.zero,
      );

      animator
        ..highlightTargetId = 1
        ..highlightPhase = ChatHighlightPhase.solid
        ..highlightFactor = 1.0
        ..startHighlightHold();

      expect(animator.tickHighlight(Duration.zero), isFalse);
      expect(animator.highlightTargetId, isNull);
    });

    test('beginHighlightFade skips remaining hold', () {
      final controller = ChatScrollController();
      final animator = _animator(
        controller: controller,
        highlightDuration: const Duration(milliseconds: 1000),
      );

      animator
        ..highlightTargetId = 7
        ..highlightPhase = ChatHighlightPhase.solid
        ..highlightFactor = 1.0
        ..startHighlightHold();
      animator.tickHighlight(Duration.zero);
      animator.beginHighlightFade();
      expect(animator.highlightPhase, ChatHighlightPhase.fading);
      expect(animator.tickHighlight(Duration.zero), isTrue);
      expect(animator.tickHighlight(kHighlightFadeDuration), isFalse);
      expect(animator.highlightTargetId, isNull);
    });
  });

  group('highlight arm at animate start', () {
    test('close path arms solid before settle', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 120.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
        highlightDuration: const Duration(milliseconds: 400),
      );

      animator.animate(
        5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );

      expect(animator.highlightTargetId, 5);
      expect(animator.highlightPhase, ChatHighlightPhase.solid);
      expect(animator.highlightFactor, 1.0);
      // Hold clock not running mid-flight.
      animator.tickAnimate(Duration.zero);
      animator.tickHighlight(const Duration(milliseconds: 200));
      expect(animator.highlightPhase, ChatHighlightPhase.solid);
      expect(animator.highlightFactor, 1.0);
    });

    test('settle restarts hold then fades', () {
      final controller = ChatScrollController()..reassignAnchor(1, 100);
      final box = _sizedBox();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 100.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
        highlightDuration: const Duration(milliseconds: 200),
      );

      animator.animate(
        1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      animator.tickAnimate(Duration.zero);
      animator.tickAnimate(animator.animateDuration);
      expect(animator.isAnimating, isFalse);
      expect(animator.highlightPhase, ChatHighlightPhase.solid);

      const t0 = Duration.zero;
      animator.tickHighlight(t0);
      expect(animator.highlightFactor, 1.0);
      animator.tickHighlight(t0 + const Duration(milliseconds: 100));
      expect(animator.highlightPhase, ChatHighlightPhase.solid);
      animator.tickHighlight(t0 + const Duration(milliseconds: 200));
      expect(animator.highlightPhase, ChatHighlightPhase.fading);
      animator.tickHighlight(
        t0 + const Duration(milliseconds: 200) + kHighlightFadeDuration,
      );
      expect(animator.highlightTargetId, isNull);
    });

    test('cancel mid-flight fades highlight', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 120.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
        highlightDuration: const Duration(milliseconds: 400),
      );

      animator.animate(
        5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      expect(animator.highlightPhase, ChatHighlightPhase.solid);
      animator.cancelAnimate();
      expect(animator.isAnimating, isFalse);
      expect(animator.highlightPhase, ChatHighlightPhase.fading);
    });

    test('replace retargets highlight immediately', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (id) => id == 5 ? 120.0 : 80.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
        highlightDuration: const Duration(milliseconds: 400),
      );

      animator.animate(
        5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
      expect(animator.highlightTargetId, 5);

      animator.animate(
        8,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        busyPolicy: AnimateToBusyPolicy.replace,
      );
      expect(animator.highlightTargetId, 8);
      expect(animator.highlightPhase, ChatHighlightPhase.solid);
    });

    test('highlight false never arms', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 120.0,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
      );

      animator.animate(
        5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        highlight: false,
      );
      expect(animator.highlightTargetId, isNull);
      animator.tickAnimate(Duration.zero);
      animator.tickAnimate(animator.animateDuration);
      expect(animator.highlightTargetId, isNull);
    });
  });

  group('cancelAnimate', () {
    test('clears stitch state and completes', () {
      final controller = ChatScrollController();
      var cancelled = false;
      final animator = _animator(
        controller: controller,
        onStitchCancelled: (_) => cancelled = true,
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
      expect(cancelled, isTrue);
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
      var cancelCount = 0;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        onStitchCancelled: (_) => cancelCount++,
      );

      final first = animator.animate(
        1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        highlight: false,
      );
      expect(animator.animateTargetId, 1);
      expect(animator.farAnimateActive, isTrue);
      final clearsAfterStart = cancelCount;

      await animator.animate(
        2,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        highlight: false,
      );

      expect(animator.animateTargetId, 1);
      expect(animator.farAnimateActive, isTrue);
      expect(cancelCount, clearsAfterStart);

      animator.cancelAnimate();
      await first;
    });

    test('replace during flight cancels and starts the new target', () async {
      final controller = ChatScrollController();
      var captured = <int>[];
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        isDestinationReady: (_) => true,
        prepareStitchCapture: captured.add,
      );

      final first = animator.animate(
        1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        highlight: false,
      );
      expect(animator.animateTargetId, 1);
      expect(animator.farAnimateActive, isTrue);

      final second = animator.animate(
        2,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        highlight: false,
        busyPolicy: AnimateToBusyPolicy.replace,
      );
      expect(animator.animateTargetId, 2);
      expect(animator.farAnimateActive, isTrue);
      expect(captured, equals([1, 2]));

      await first;
      animator.cancelAnimate();
      await second;
    });

    test('replace during load-gate retargets immediately', () async {
      final controller = ChatScrollController();
      var requested = <int>[];
      final waiting = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        isDestinationReady: (_) => false,
        requestDestinationWindow: requested.add,
      );
      waiting
          .animate(
            10,
            duration: const Duration(milliseconds: 200),
            curve: Curves.linear,
            highlight: false,
          )
          .ignore();
      expect(waiting.loadGateWaiting, isTrue);
      expect(waiting.animateTargetId, 10);

      waiting
          .animate(
            20,
            duration: const Duration(milliseconds: 200),
            curve: Curves.linear,
            highlight: false,
            busyPolicy: AnimateToBusyPolicy.replace,
          )
          .ignore();
      expect(waiting.loadGateWaiting, isTrue);
      expect(waiting.animateTargetId, 20);
      expect(requested, contains(20));

      waiting.cancelAnimate();
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
      expect(animator.loadGateWaiting, isFalse);
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

      expect(animator.loadGateWaiting, isTrue);
      expect(animator.farAnimateActive, isFalse);
      expect(layoutAsked, isTrue);
    });

    test('immediate waits when destination is not ready', () {
      final controller = ChatScrollController();
      var captured = false;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        isDestinationReady: (_) => false,
        prepareStitchCapture: (_) => captured = true,
      );

      animator.animate(
        99,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.immediate,
      );

      expect(animator.loadGateWaiting, isTrue);
      expect(animator.farAnimateActive, isFalse);
      expect(captured, isFalse);
      expect(controller.anchorMessageId, isNot(99));
    });

    test('immediate stitches when ready but not built', () {
      final controller = ChatScrollController();
      var captured = false;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        isDestinationReady: (_) => true,
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

    test(
      'close path when target is built even beyond kCloseAnimateDistance',
      () {
        // Telegram found → smoothScrollBy; distance must not force stitch.
        final controller = ChatScrollController();
        final box = _sizedBox();
        final animator = _animator(
          controller: controller,
          offsetToBuiltMessage: (_) => kCloseAnimateDistance + 1,
          closePathEndOffsetFor: (_, _, alignment) => 40.0 * alignment,
          childForId: (_) => box,
          heightOfChild: (_) => box.size.height,
          messageIntersectsPaintBand: (_) => false,
        );

        animator.animate(
          1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
          highlight: false,
        );

        expect(animator.farAnimateActive, isFalse);
        expect(animator.isAnimating, isTrue);
      },
    );

    test(
      'close path when band-intersecting even if offset exceeds distance',
      () {
        // Telegram: found among current children → smoothScrollBy, not stitch.
        final controller = ChatScrollController();
        final box = _sizedBox(height: 5000);
        const startY = -(kCloseAnimateDistance + 2000);
        const endY = 90.0;
        final animator = _animator(
          controller: controller,
          offsetToBuiltMessage: (_) => startY,
          messageIntersectsPaintBand: (_) => true,
          viewportHeight: () => 600.0,
          closePathEndOffsetFor: (_, _, _) => endY,
          childForId: (_) => box,
          heightOfChild: (_) => box.size.height,
        );

        animator.animate(
          1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
          highlight: false,
        );

        expect(animator.farAnimateActive, isFalse);
        expect(animator.isAnimating, isTrue);
        // ~4.5k px travel → Telegram max duration, not caller 200ms.
        expect(
          animator.animateDuration,
          chatAnimateTravelDuration(
            travelPx: endY - startY,
            viewportHeight: 600,
          ),
        );
        expect(
          animator.animateDuration.inMilliseconds,
          kAnimateTravelDurationMaxMs,
        );
        expect(animator.animateCurve, Curves.easeOutQuint);
      },
    );

    test(
      'close path short travel uses Telegram min duration + easeOutQuint',
      () {
        final controller = ChatScrollController();
        final box = _sizedBox();
        final animator = _animator(
          controller: controller,
          offsetToBuiltMessage: (_) => 120.0,
          closePathEndOffsetFor: (_, _, _) => 0.0,
          childForId: (_) => box,
          heightOfChild: (_) => box.size.height,
          viewportHeight: () => 600.0,
        );

        animator.animate(
          5,
          duration: const Duration(milliseconds: 80),
          curve: Curves.linear,
          highlight: false,
        );

        expect(animator.farAnimateActive, isFalse);
        expect(
          animator.animateDuration.inMilliseconds,
          kAnimateTravelDurationMinMs,
        );
        expect(animator.animateCurve, Curves.easeOutQuint);
      },
    );

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
      expect(animator.loadGateWaiting, isTrue);

      offset = 80.0;
      animator.onLayoutOpportunity(viewportHeight: 600);
      expect(animator.loadGateWaiting, isFalse);
      expect(animator.farAnimateActive, isFalse);
      expect(controller.anchorMessageId, 5);
    });

    test('preferBuilt does not timeout into stitch while unready', () {
      final controller = ChatScrollController();
      var captured = false;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        isDestinationReady: (_) => false,
        prepareStitchCapture: (_) => captured = true,
      );

      animator.animate(
        99,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.preferBuilt,
        highlight: false,
      );
      expect(animator.loadGateWaiting, isTrue);

      animator.tickAnimate(Duration.zero);
      animator.tickAnimate(const Duration(seconds: 5));
      expect(animator.loadGateWaiting, isTrue);
      expect(animator.farAnimateActive, isFalse);
      expect(captured, isFalse);
    });

    test('load-gate then close path once destination is ready nearby', () {
      final controller = ChatScrollController();
      final box = _sizedBox();
      var ready = false;
      double? offset;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => offset,
        isDestinationReady: (_) => ready,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
      );

      animator.animate(
        5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.immediate,
        highlight: false,
      );
      expect(animator.loadGateWaiting, isTrue);
      expect(animator.farAnimateActive, isFalse);

      ready = true;
      offset = 80.0;
      animator.onLayoutOpportunity(viewportHeight: 600);
      expect(animator.loadGateWaiting, isFalse);
      expect(animator.farAnimateActive, isFalse);
      expect(controller.anchorMessageId, 5);
    });

    test('load-gate then close once ready and built (even if far)', () async {
      final controller = ChatScrollController();
      final box = _sizedBox();
      var ready = false;
      double? offset;
      var captured = false;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => offset,
        isDestinationReady: (_) => ready,
        prepareStitchCapture: (_) => captured = true,
        closePathEndOffsetFor: (_, _, _) => 0.0,
        childForId: (_) => box,
        heightOfChild: (_) => box.size.height,
      );

      animator
          .animate(
            5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.linear,
            loadPolicy: AnimateToLoadPolicy.immediate,
            highlight: false,
          )
          .ignore();
      expect(animator.loadGateWaiting, isTrue);

      ready = true;
      offset = kCloseAnimateDistance + 1;
      animator.onLayoutOpportunity(viewportHeight: 600);
      await Future<void>.delayed(Duration.zero);
      expect(animator.loadGateWaiting, isFalse);
      expect(animator.farAnimateActive, isFalse);
      expect(captured, isFalse);
      expect(animator.isAnimating, isTrue);
    });

    test('unready shimmer offset does not start close or stitch', () {
      final controller = ChatScrollController();
      var captured = false;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => 40.0,
        isDestinationReady: (_) => false,
        prepareStitchCapture: (_) => captured = true,
      );

      animator.animate(
        5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        loadPolicy: AnimateToLoadPolicy.immediate,
        highlight: false,
      );

      expect(animator.loadGateWaiting, isTrue);
      expect(animator.farAnimateActive, isFalse);
      expect(controller.anchorMessageId, isNot(5));
      expect(captured, isFalse);
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

      final midDelta = animator.tickAnimate(animator.animateDuration * 0.5);
      expect(midDelta, lessThan(0.0));

      expect(
        animator.tickAnimate(animator.animateDuration),
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
      animator.tickAnimate(animator.animateDuration);
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

      final quarter = animator.animateDuration * 0.25;
      final half = animator.animateDuration * 0.5;
      animator.tickAnimate(quarter);
      alignedEnd = 160.0;
      animator.rebaseClosePathEnd(elapsed: quarter);
      animator.tickAnimate(half);
      expect(animator.animateEndOffset, 160.0);
      expect(animator.animateStartOffset, controller.anchorPixelOffset);
    });

    test('stitch advances progress after measure and completes', () {
      final controller = ChatScrollController();
      StitchCancelSnapshot? completed;
      final animator = _animator(
        controller: controller,
        offsetToBuiltMessage: (_) => null,
        onStitchComplete: (snapshot) => completed = snapshot,
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
      expect(completed, isNotNull);
      expect(completed!.targetId, 42);
      expect(completed!.progress, 1.0);
      expect(completed!.measured, isTrue);
      expect(completed!.jumped, isTrue);
    });
  });

  group('paintHighlight', () {
    test('uses normalized .a channel scaled by highlightFactor', () {
      const base = Color(0x280A90F0);
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
      animator.tickAnimate(Duration.zero);
      animator.tickAnimate(animator.animateDuration);

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
      animator.tickAnimate(Duration.zero);
      animator.tickAnimate(animator.animateDuration);

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
      animator.tickAnimate(Duration.zero);
      animator.tickAnimate(animator.animateDuration);

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
