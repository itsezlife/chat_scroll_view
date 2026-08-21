import 'dart:async';

import 'package:chat_scroll_view/src/chat_scroll/chat_animator.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
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

    testWidgets('highlight stays solid through hold then fades', (tester) async {
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

    testWidgets('drag during highlight fades but keeps target until fade ends', (
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
    });

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
