import 'dart:async';

import 'package:chat_scroll_view/src/chat_scroll/chat_animator.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  Duration highlightDuration = const Duration(milliseconds: 600),
  Color highlightColor = const Color(0x80FF0000),
  double cacheExtent = 1000,
  WidgetBuilder? emptyBuilder,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          cacheExtent: cacheExtent,
          highlightColor: highlightColor,
          highlightDuration: highlightDuration,
          emptyBuilder: emptyBuilder,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

/// Helper: drive an animateTo to completion with explicit ticker frames.
/// Never `await` the future before pumping — that deadlocks. Never
/// pumpAndSettle while the animate ticker is live.
Future<void> _driveAnimate(
  WidgetTester tester,
  Future<void> animateFuture, {
  required Duration animateDuration,
  int maxPumps = 200,
}) async {
  await tester.pump();
  var done = false;
  unawaited(animateFuture.whenComplete(() => done = true));
  for (var i = 0; i < maxPumps && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done, isTrue, reason: 'animateTo did not finish in $maxPumps pumps');
  await animateFuture;
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('animateTo highlight', () {
    testWidgets('close-path animateTo lands the highlight on the target', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();
      expect(_render(tester).debugHighlightTargetId, isNull);

      const target = 120;
      final future = controller.animateTo(
        target,
        duration: const Duration(milliseconds: 80),
      );
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        _render(tester).debugHighlightTargetId,
        target,
        reason: 'Telegram: highlight arms at navigate start',
      );
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
      expect(_render(tester).debugHighlightFactor, 1.0);

      await _driveAnimate(
        tester,
        future,
        animateDuration: const Duration(milliseconds: 80),
      );

      expect(_render(tester).debugHighlightTargetId, target);
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
      expect(_render(tester).debugHighlightFactor, 1.0);
    });

    testWidgets('highlight stays solid through hold then fades', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(milliseconds: 200),
        ),
      );
      await tester.pumpAndSettle();

      final future = controller.animateTo(
        120,
        duration: const Duration(milliseconds: 80),
      );
      await _driveAnimate(
        tester,
        future,
        animateDuration: const Duration(milliseconds: 80),
      );
      expect(_render(tester).debugHighlightTargetId, 120);
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);

      // Mid-hold — still solid at full factor.
      await tester.pump(const Duration(milliseconds: 100));
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
      expect(_render(tester).debugHighlightFactor, 1.0);

      // Past hold → fading (factor still 1 at fade start).
      await tester.pump(const Duration(milliseconds: 120));
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.fading);

      await tester.pump(const Duration(milliseconds: 100));
      expect(_render(tester).debugHighlightFactor, lessThan(1.0));

      // Past fade → cleared.
      await tester.pump(const Duration(milliseconds: 250));
      expect(_render(tester).debugHighlightTargetId, isNull);
      expect(_render(tester).debugHighlightFactor, 0.0);
    });

    testWidgets('factor stays 1 during hold then decreases in fade', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(milliseconds: 100),
        ),
      );
      await tester.pumpAndSettle();

      final future = controller.animateTo(
        120,
        duration: const Duration(milliseconds: 60),
      );
      await _driveAnimate(
        tester,
        future,
        animateDuration: const Duration(milliseconds: 60),
      );
      final f0 = _render(tester).debugHighlightFactor;
      expect(f0, 1.0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_render(tester).debugHighlightFactor, 1.0);
      // Enter fade and advance into it.
      await tester.pump(const Duration(milliseconds: 60));
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.fading);
      await tester.pump(const Duration(milliseconds: 100));
      final f1 = _render(tester).debugHighlightFactor;
      await tester.pump(const Duration(milliseconds: 100));
      final f2 = _render(tester).debugHighlightFactor;

      expect(f1, lessThan(1.0));
      expect(f2, lessThan(f1));
    });

    testWidgets(
      'close-path animateTo with highlight false suppresses highlight',
      (tester) async {
        const count = 256;
        final controller = ChatScrollController()..jumpTo(count ~/ 2);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(dataSource: ds, controller: controller),
        );
        await tester.pumpAndSettle();

        final future = controller.animateTo(
          120,
          duration: const Duration(milliseconds: 80),
          highlight: false,
        );
        await _driveAnimate(
          tester,
          future,
          animateDuration: const Duration(milliseconds: 80),
        );

        expect(_render(tester).debugHighlightTargetId, isNull);
      },
    );

    testWidgets(
      'far-path animateTo with highlight false suppresses highlight',
      (tester) async {
        const count = 256;
        final controller = ChatScrollController()..jumpTo(count ~/ 2);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(dataSource: ds, controller: controller, cacheExtent: 200),
        );
        await tester.pumpAndSettle();

        // Target 0 is outside the build range — stitch, not close.
        final future = controller.animateTo(
          0,
          duration: const Duration(milliseconds: 120),
          highlight: false,
        );
        await _driveAnimate(
          tester,
          future,
          animateDuration: const Duration(milliseconds: 120),
        );

        expect(_render(tester).debugHighlightTargetId, isNull);
      },
    );

    testWidgets(
      'far-path stitch keeps highlight armed through jump (not only at settle)',
      (tester) async {
        // Regression: _onJump used to hard-clear highlight on stitch teleport,
        // so select tint only reappeared in _completeAnimate — unlike Telegram
        // highlightMessageId set before scrollHelper.
        const count = 256;
        final controller = ChatScrollController()..jumpTo(count ~/ 2);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            cacheExtent: 200,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pumpAndSettle();

        const target = 0;
        final future = controller.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
        );
        await tester.pump();
        // Drive until stitch has jumped (far active + target anchored).
        var sawStitch = false;
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final r = _render(tester);
          if (r.debugFarAnimateActive && r.debugFarAnimateJumped) {
            sawStitch = true;
            expect(
              r.debugHighlightTargetId,
              target,
              reason: 'highlight must survive stitch jumpTo',
            );
            expect(r.debugHighlightPhase, ChatHighlightPhase.solid);
            expect(r.debugHighlightFactor, 1.0);
            break;
          }
        }
        expect(sawStitch, isTrue, reason: 'expected far-path stitch flight');

        await _driveAnimate(
          tester,
          future,
          animateDuration: const Duration(milliseconds: 200),
          maxPumps: 400,
        );
        expect(_render(tester).debugHighlightTargetId, target);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
      },
    );

    testWidgets('re-entrant animateTo is ignored while in flight', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();

      const expectedEnd = 0.5 * (600 - 60);
      final samples = <double>[];

      final firstFuture = controller.animateTo(
        120,
        duration: const Duration(milliseconds: 120),
        alignment: 0.5,
        highlight: false,
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        samples.add(controller.anchorPixelOffset);
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Telegram: while animating, a different target is dropped.
      final secondFuture = controller.animateTo(
        125,
        duration: const Duration(milliseconds: 120),
        alignment: 0.5,
        highlight: false,
      );
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        samples.add(controller.anchorPixelOffset);
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await firstFuture;
      await secondFuture;

      for (var i = 1; i < samples.length; i++) {
        final prevDist = (samples[i - 1] - expectedEnd).abs();
        final currDist = (samples[i] - expectedEnd).abs();
        expect(
          currDist,
          lessThanOrEqualTo(prevDist + 0.5),
          reason: 'in-flight frame $i offset hitch toward $expectedEnd',
        );
      }
      expect(controller.anchorMessageId, 120);
    });

    testWidgets('re-entrant animateTo with highlight false then true', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(milliseconds: 800),
        ),
      );
      await tester.pumpAndSettle();

      final firstFuture = controller.animateTo(
        120,
        duration: const Duration(milliseconds: 60),
        highlight: false,
      );
      await _driveAnimate(
        tester,
        firstFuture,
        animateDuration: const Duration(milliseconds: 60),
      );
      expect(_render(tester).debugHighlightTargetId, isNull);

      final secondFuture = controller.animateTo(
        125,
        duration: const Duration(milliseconds: 80),
      );
      await _driveAnimate(
        tester,
        secondFuture,
        animateDuration: const Duration(milliseconds: 80),
      );
      expect(_render(tester).debugHighlightTargetId, 125);
    });

    testWidgets('jumpTo produces no post-navigation highlight', (tester) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      controller.jumpTo(120);
      await tester.pump();

      expect(_render(tester).debugHighlightTargetId, isNull);
    });

    testWidgets('zero-duration animate falls through to jumpTo, no highlight', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      // Zero-duration animateTo synchronously jumps and returns immediately.
      await controller.animateTo(120, duration: Duration.zero, highlight: true);
      await tester.pump();

      expect(_render(tester).debugHighlightTargetId, isNull);
    });

    testWidgets('highlightDuration = 0 disables the effect entirely', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();

      final future = controller.animateTo(
        120,
        duration: const Duration(milliseconds: 80),
        highlight: true,
      );
      await _driveAnimate(
        tester,
        future,
        animateDuration: const Duration(milliseconds: 80),
      );

      expect(_render(tester).debugHighlightTargetId, isNull);
    });

    testWidgets('re-entrant animateTo retargets the highlight', (tester) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(milliseconds: 800),
        ),
      );
      await tester.pumpAndSettle();

      // First animation lands.
      final firstFuture = controller.animateTo(
        120,
        duration: const Duration(milliseconds: 60),
      );
      await _driveAnimate(
        tester,
        firstFuture,
        animateDuration: const Duration(milliseconds: 60),
      );
      expect(_render(tester).debugHighlightTargetId, 120);

      // Start a new animation while the previous highlight is still active.
      // Telegram: clear then re-arm the new id at navigate start.
      final secondFuture = controller.animateTo(
        125,
        duration: const Duration(milliseconds: 80),
      );
      await tester.pump();
      expect(
        _render(tester).debugHighlightTargetId,
        125,
        reason: 'highlight retargets at the start of the new animateTo',
      );
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);

      await _driveAnimate(
        tester,
        secondFuture,
        animateDuration: const Duration(milliseconds: 80),
      );
      expect(_render(tester).debugHighlightTargetId, 125);
    });

    testWidgets(
      'drag during highlight fades but keeps target until fade ends',
      (tester) async {
        const count = 256;
        final controller = ChatScrollController()..jumpTo(count ~/ 2);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(milliseconds: 800),
          ),
        );
        await tester.pumpAndSettle();

        final future = controller.animateTo(
          120,
          duration: const Duration(milliseconds: 60),
        );
        await _driveAnimate(
          tester,
          future,
          animateDuration: const Duration(milliseconds: 60),
        );
        expect(_render(tester).debugHighlightTargetId, 120);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);

        // A short drag — won't sweep msg-120 off-screen at 60 px tall.
        await tester.drag(find.byType(ChatScrollView), const Offset(0, 30));
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, 120);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.fading);
      },
    );

    testWidgets(
      'load-gate waits then highlights after destination becomes ready',
      (tester) async {
        const total = 200;
        const loadedFrom = 192;
        const target = 50;
        final controller = ChatScrollController()..jumpTo(total - 1);
        final ds = _GatedLazyTailDataSource(
          totalCount: total,
          loadedFromId: loadedFrom,
        );
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 600,
                  child: ChatScrollView(
                    reverse: true,
                    dataSource: ds,
                    controller: controller,
                    cacheExtent: 2000,
                    highlightDuration: const Duration(seconds: 10),
                    messageBuilder: (context, id, message, status, runLayout) =>
                        SizedBox(
                          height: 60,
                          child: Text(
                            message == null ? 'shimmer-$id' : 'msg-$id',
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final future = controller.animateTo(
          target,
          duration: const Duration(milliseconds: 80),
        );
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(_render(tester).debugLoadGateWaiting, isTrue);
        expect(_render(tester).debugFarAnimateActive, isFalse);
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);

        // Destination window (issue 02 owns auto-fetch); host/test loads it.
        ds.loadTargetWindow(aroundId: target);
        await _driveAnimate(
          tester,
          future,
          animateDuration: const Duration(milliseconds: 80),
          maxPumps: 400,
        );
        await tester.pump();

        final settled = _render(tester);
        expect(find.text('msg-$target'), findsOneWidget);
        expect(find.text('shimmer-$target'), findsNothing);
        expect(settled.debugPendingHighlightTargetId, isNull);
        expect(settled.debugHighlightTargetId, target);
        expect(settled.debugHighlightFactor, greaterThan(0.0));
      },
    );
  });

  group('jumpTo / highlight primitive', () {
    testWidgets(
      'pre-mount jumpTo(highlight: true) on a loaded row arms solid wash',
      (tester) async {
        const count = 256;
        const target = 120;
        final controller = ChatScrollController()
          ..jumpTo(target, highlight: true);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(controller.anchorMessageId, target);
        expect(_render(tester).debugHighlightTargetId, target);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
        expect(_render(tester).debugHighlightFactor, 1.0);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );

    testWidgets('jumpTo without highlight hard-clears a leftover wash', (
      tester,
    ) async {
      const count = 256;
      const origin = 128;
      final controller = ChatScrollController()..jumpTo(origin);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(seconds: 10),
        ),
      );
      await tester.pumpAndSettle();

      controller.highlight(origin);
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, origin);

      controller.jumpTo(120);
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, isNull);
      expect(_render(tester).debugPendingHighlightTargetId, isNull);
    });

    testWidgets(
      'highlight() on an already-aligned row arms solid hold without motion',
      (tester) async {
        const count = 256;
        const origin = 128;
        final controller = ChatScrollController()..jumpTo(origin);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pumpAndSettle();

        final originY = controller.anchorPixelOffset;
        controller.highlight(origin);
        await tester.pump();

        expect(controller.anchorMessageId, origin);
        expect(controller.anchorPixelOffset, originY);
        expect(_render(tester).debugHighlightTargetId, origin);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
        expect(_render(tester).debugHighlightFactor, 1.0);
      },
    );

    testWidgets(
      'unbound animateTo(highlight: true) then mount arms solid like jump sugar',
      (tester) async {
        const count = 256;
        const target = 120;
        final controller = ChatScrollController();
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await controller.animateTo(target, highlight: true);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(controller.anchorMessageId, target);
        expect(_render(tester).debugHighlightTargetId, target);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
        expect(_render(tester).debugHighlightFactor, 1.0);
      },
    );

    testWidgets(
      'unbound animateTo(highlight: false) then mount stays geometry-only',
      (tester) async {
        const count = 256;
        const target = 120;
        final controller = ChatScrollController();
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await controller.animateTo(target, highlight: false);

        await tester.pumpWidget(
          _scaffold(dataSource: ds, controller: controller),
        );
        await tester.pump();
        await tester.pump();

        expect(controller.anchorMessageId, target);
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );

    testWidgets(
      'jumpToCenterBand has no highlight flag and does not arm a wash',
      (tester) async {
        const count = 256;
        const target = 120;
        final controller = ChatScrollController()..jumpToCenterBand(target, 0);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(controller.anchorMessageId, target);
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );

    testWidgets('pending-only highlight does not keep pumping frames', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          cacheExtent: 200,
          highlightDuration: const Duration(seconds: 10),
        ),
      );
      await tester.pumpAndSettle();

      controller.highlight(0);
      await tester.pump();
      expect(_render(tester).debugPendingHighlightTargetId, 0);
      expect(_render(tester).debugHighlightTargetId, isNull);

      await tester.pumpAndSettle();
      expect(_render(tester).debugPendingHighlightTargetId, 0);
      expect(_render(tester).debugHighlightTargetId, isNull);
    });
  });

  group('deferred highlight until built', () {
    testWidgets(
      'highlight while the row is a shimmer defers then arms when loaded and built',
      (tester) async {
        const total = 200;
        const loadedFrom = 192;
        const target = 50;
        final controller = ChatScrollController()
          ..jumpTo(target, highlight: true);
        final ds = _HangFetchLazyDataSource(
          totalCount: total,
          loadedFromId: loadedFrom,
        );
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('shimmer-$target'), findsOneWidget);
        expect(find.text('msg-$target'), findsNothing);
        expect(_render(tester).debugPendingHighlightTargetId, target);
        expect(_render(tester).debugHighlightTargetId, isNull);

        ds.loadMessage(target);
        await tester.pump();
        await tester.pump();

        expect(find.text('msg-$target'), findsOneWidget);
        expect(find.text('shimmer-$target'), findsNothing);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
        expect(_render(tester).debugHighlightTargetId, target);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
        expect(_render(tester).debugHighlightFactor, 1.0);
      },
    );

    testWidgets(
      'absent target drops pending and does not late-arm after a later upsert',
      (tester) async {
        const total = 200;
        const loadedFrom = 192;
        const target = 50;
        final controller = ChatScrollController()
          ..jumpTo(target, highlight: true);
        final ds = _HangFetchLazyDataSource(
          totalCount: total,
          loadedFromId: loadedFrom,
        );
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(_render(tester).debugPendingHighlightTargetId, target);
        expect(_render(tester).debugHighlightTargetId, isNull);

        ds.markSlotAbsent(target);
        await tester.pump();
        await tester.pump();

        expect(_render(tester).debugPendingHighlightTargetId, isNull);
        expect(_render(tester).debugHighlightTargetId, isNull);

        ds.loadMessage(target);
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );

    testWidgets(
      'error target drops pending and does not late-arm after a later upsert',
      (tester) async {
        const total = 200;
        const loadedFrom = 192;
        const target = 50;
        final controller = ChatScrollController()
          ..jumpTo(target, highlight: true);
        final ds = _HangFetchLazyDataSource(
          totalCount: total,
          loadedFromId: loadedFrom,
        );
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(_render(tester).debugPendingHighlightTargetId, target);
        expect(_render(tester).debugHighlightTargetId, isNull);

        ds.markChunkError(target);
        await tester.pump();
        await tester.pump();

        expect(_render(tester).debugPendingHighlightTargetId, isNull);
        expect(_render(tester).debugHighlightTargetId, isNull);

        ds.loadAsValid(target);
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );
  });

  group('highlight clear matrix', () {
    testWidgets('new highlight replaces a pending id', (tester) async {
      const total = 200;
      const loadedFrom = 192;
      const first = 50;
      const second = 51;
      final controller = ChatScrollController()..jumpTo(first, highlight: true);
      final ds = _HangFetchLazyDataSource(
        totalCount: total,
        loadedFromId: loadedFrom,
      );
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(seconds: 10),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_render(tester).debugPendingHighlightTargetId, first);

      controller.highlight(second);
      await tester.pump();
      expect(_render(tester).debugPendingHighlightTargetId, second);
      expect(_render(tester).debugHighlightTargetId, isNull);

      ds.loadMessage(first);
      await tester.pump();
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, isNull);
      expect(_render(tester).debugPendingHighlightTargetId, second);

      ds.loadMessage(second);
      await tester.pump();
      await tester.pump();
      expect(_render(tester).debugPendingHighlightTargetId, isNull);
      expect(_render(tester).debugHighlightTargetId, second);
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
    });

    testWidgets(
      'new highlight hard-clears an armed wash then arms the new id',
      (tester) async {
        const count = 256;
        const origin = 128;
        const next = 129;
        final controller = ChatScrollController()..jumpTo(origin);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pumpAndSettle();

        controller.highlight(origin);
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, origin);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);

        controller.highlight(next);
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, next);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
        expect(_render(tester).debugHighlightFactor, 1.0);
      },
    );

    testWidgets('same-id highlight while on screen restarts hold', (
      tester,
    ) async {
      const count = 256;
      const origin = 128;
      final controller = ChatScrollController()..jumpTo(origin);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(milliseconds: 200),
        ),
      );
      await tester.pumpAndSettle();

      controller.highlight(origin);
      await tester.pump();
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);

      await tester.pump(const Duration(milliseconds: 150));
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);

      controller.highlight(origin);
      await tester.pump();
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
      expect(_render(tester).debugHighlightFactor, 1.0);

      // Original hold would have expired (~300ms). Restarted hold is still
      // inside the 200ms window.
      await tester.pump(const Duration(milliseconds: 150));
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
      expect(_render(tester).debugHighlightTargetId, origin);
    });

    testWidgets(
      'jumpTo without highlight hard-clears pending and does not late-arm',
      (tester) async {
        const total = 200;
        const loadedFrom = 192;
        const target = 50;
        final controller = ChatScrollController()
          ..jumpTo(target, highlight: true);
        final ds = _HangFetchLazyDataSource(
          totalCount: total,
          loadedFromId: loadedFrom,
        );
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugPendingHighlightTargetId, target);

        controller.jumpTo(loadedFrom);
        await tester.pump();
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
        expect(_render(tester).debugHighlightTargetId, isNull);

        ds.loadMessage(target);
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );

    testWidgets('jumpToCenterBand hard-clears pending and armed', (
      tester,
    ) async {
      const count = 256;
      const origin = 128;
      final controller = ChatScrollController()..jumpTo(origin);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(seconds: 10),
        ),
      );
      await tester.pumpAndSettle();

      controller.highlight(origin);
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, origin);

      controller.jumpToCenterBand(120, 0);
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, isNull);
      expect(_render(tester).debugPendingHighlightTargetId, isNull);
    });

    testWidgets('jumpToCenterBand hard-clears a pending request', (
      tester,
    ) async {
      const total = 200;
      const loadedFrom = 192;
      const target = 50;
      final controller = ChatScrollController()
        ..jumpTo(target, highlight: true);
      final ds = _HangFetchLazyDataSource(
        totalCount: total,
        loadedFromId: loadedFrom,
      );
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(seconds: 10),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_render(tester).debugPendingHighlightTargetId, target);

      controller.jumpToCenterBand(loadedFrom, 0);
      await tester.pump();
      expect(_render(tester).debugPendingHighlightTargetId, isNull);
      expect(_render(tester).debugHighlightTargetId, isNull);

      ds.loadMessage(target);
      await tester.pump();
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, isNull);
      expect(_render(tester).debugPendingHighlightTargetId, isNull);
    });

    testWidgets(
      'animateTo(highlight: false) hard-clears leftover wash at start',
      (tester) async {
        const count = 256;
        const origin = 128;
        final controller = ChatScrollController()..jumpTo(origin);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pumpAndSettle();

        controller.highlight(origin);
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, origin);

        final future = controller.animateTo(
          120,
          duration: const Duration(milliseconds: 80),
          highlight: false,
        );
        await tester.pump();
        expect(
          _render(tester).debugHighlightTargetId,
          isNull,
          reason: 'routine hops drop leftover wash at animate start',
        );
        expect(_render(tester).debugPendingHighlightTargetId, isNull);

        await _driveAnimate(
          tester,
          future,
          animateDuration: const Duration(milliseconds: 80),
        );
        expect(_render(tester).debugHighlightTargetId, isNull);
      },
    );

    testWidgets('drag fades an armed wash', (tester) async {
      const count = 256;
      const origin = 128;
      final controller = ChatScrollController()..jumpTo(origin);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(seconds: 10),
        ),
      );
      await tester.pumpAndSettle();

      controller.highlight(origin);
      await tester.pump();
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 30));
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, origin);
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.fading);
    });

    testWidgets(
      'drag hard-clears pending and does not late-arm when the row appears',
      (tester) async {
        const total = 200;
        const loadedFrom = 192;
        const target = 50;
        final controller = ChatScrollController()
          ..jumpTo(target, highlight: true);
        final ds = _HangFetchLazyDataSource(
          totalCount: total,
          loadedFromId: loadedFrom,
        );
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugPendingHighlightTargetId, target);

        await tester.drag(find.byType(ChatScrollView), const Offset(0, 30));
        await tester.pump();
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
        expect(_render(tester).debugHighlightTargetId, isNull);

        ds.loadMessage(target);
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );

    testWidgets('scrollBy fades an armed wash', (tester) async {
      const count = 256;
      const origin = 128;
      final controller = ChatScrollController()..jumpTo(origin);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(seconds: 10),
        ),
      );
      await tester.pumpAndSettle();

      controller.highlight(origin);
      await tester.pump();
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);

      controller.scrollBy(30);
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, origin);
      expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.fading);
    });

    testWidgets(
      'scrollBy hard-clears pending and does not late-arm when the row appears',
      (tester) async {
        const total = 200;
        const loadedFrom = 192;
        const target = 50;
        final controller = ChatScrollController()
          ..jumpTo(target, highlight: true);
        final ds = _HangFetchLazyDataSource(
          totalCount: total,
          loadedFromId: loadedFrom,
        );
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugPendingHighlightTargetId, target);

        controller.scrollBy(30);
        await tester.pump();
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
        expect(_render(tester).debugHighlightTargetId, isNull);

        ds.loadMessage(target);
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );

    testWidgets('overlay hard-clears and remount does not late-arm', (
      tester,
    ) async {
      const count = 256;
      const origin = 128;
      final controller = ChatScrollController()..jumpTo(origin);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(seconds: 10),
          emptyBuilder: (context) => const Text('empty-chat'),
        ),
      );
      await tester.pumpAndSettle();

      controller.highlight(origin);
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, origin);

      ds.seedBoundaries(
        oldestKnownId: null,
        newestKnownId: null,
        reachedOldest: true,
        reachedNewest: true,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('empty-chat'), findsOneWidget);
      expect(_render(tester).debugHighlightTargetId, isNull);
      expect(_render(tester).debugPendingHighlightTargetId, isNull);

      ds.seedBoundaries(
        oldestKnownId: 0,
        newestKnownId: count - 1,
        reachedOldest: true,
        reachedNewest: true,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(seconds: 10),
          emptyBuilder: (context) => const Text('empty-chat'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, isNull);
      expect(_render(tester).debugPendingHighlightTargetId, isNull);
    });

    testWidgets(
      'controller swap hard-clears and swapping back does not late-arm',
      (tester) async {
        const count = 256;
        const origin = 128;
        final first = ChatScrollController()..jumpTo(origin);
        final second = ChatScrollController()..jumpTo(origin);
        final ds = _PreloadedDataSource(count);
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: first,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pumpAndSettle();

        first.highlight(origin);
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, origin);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: second,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: first,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, isNull);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );

    testWidgets('dispose hard-clears pending and armed', (tester) async {
      const count = 256;
      const origin = 128;
      final controller = ChatScrollController()..jumpTo(origin);
      final ds = _PreloadedDataSource(count);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          highlightDuration: const Duration(seconds: 10),
        ),
      );
      await tester.pumpAndSettle();

      controller.highlight(origin);
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, origin);

      controller.dispose();
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, isNull);
      expect(_render(tester).debugPendingHighlightTargetId, isNull);

      controller.highlight(origin);
      await tester.pump();
      expect(_render(tester).debugHighlightTargetId, isNull);
    });

    testWidgets(
      'unmount and remount with the same controller still arms the stored request',
      (tester) async {
        const count = 256;
        const target = 120;
        final controller = ChatScrollController()
          ..jumpTo(target, highlight: true);
        final ds = _PreloadedDataSource(count);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, target);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            highlightDuration: const Duration(seconds: 10),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(_render(tester).debugHighlightTargetId, target);
        expect(_render(tester).debugHighlightPhase, ChatHighlightPhase.solid);
        expect(_render(tester).debugPendingHighlightTargetId, isNull);
      },
    );
  });
}

/// Newest chunk loaded; older ids stay cold until [loadTargetWindow].
class _GatedLazyTailDataSource extends ChatDataSource {
  _GatedLazyTailDataSource({
    required this.totalCount,
    required this.loadedFromId,
  }) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: totalCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (var i = loadedFromId; i < totalCount; i++) {
      upsertMessage(_msg(i));
    }
  }

  final int totalCount;
  final int loadedFromId;

  void loadTargetWindow({required int aroundId, int radius = 32}) {
    final lo = (aroundId - radius).clamp(0, totalCount - 1);
    final hi = (aroundId + radius).clamp(0, totalCount - 1);
    for (var i = lo; i <= hi; i++) {
      upsertMessage(_msg(i));
    }
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// Known span is seeded; only [loadedFromId]..newest are upserted.
///
/// [fetchRange] never completes so poll cannot absent-mark an unloaded
/// origin before the test upserts it.
class _HangFetchLazyDataSource extends ChatDataSource {
  _HangFetchLazyDataSource({
    required this.totalCount,
    required this.loadedFromId,
  }) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: totalCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (var i = loadedFromId; i < totalCount; i++) {
      upsertMessage(_msg(i));
    }
  }

  final int totalCount;
  final int loadedFromId;
  final _fetch = Completer<List<IChatMessage>>();

  void loadMessage(int id) => upsertMessage(_msg(id));

  void markSlotAbsent(int id) {
    final chunkIndex = ChatScrollChunk.chunkOf(id);
    final chunk = chunks.putIfAbsent(
      chunkIndex,
      () =>
          ChatScrollChunk(index: chunkIndex)..status = ChatMessageStatus.valid,
    );
    final slot = id - chunk.firstId;
    chunk.messages[slot] = null;
    if (!chunk.isAbsentSlot(slot)) {
      chunk.markAbsentSlot(slot);
    }
    notifyDataChanged();
  }

  void markChunkError(int id) {
    final chunkIndex = ChatScrollChunk.chunkOf(id);
    final chunk = chunks.putIfAbsent(
      chunkIndex,
      () => ChatScrollChunk(index: chunkIndex),
    );
    chunk.status = ChatMessageStatus.error;
    notifyDataChanged();
  }

  void loadAsValid(int id) {
    loadMessage(id);
    chunks[ChatScrollChunk.chunkOf(id)]?.status = ChatMessageStatus.valid;
    notifyDataChanged();
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) => _fetch.future;
}
