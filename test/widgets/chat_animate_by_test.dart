import 'package:chat_scroll_view/chat_scroll_view.dart';
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

class _Source extends ChatDataSource {
  _Source(int count) {
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

void main() {
  late _Source ds;
  late ChatScrollController controller;

  Future<void> mount(WidgetTester tester, {int count = 80}) async {
    ds = _Source(count);
    controller = ChatScrollController()..jumpTo(count - 1);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 400,
              height: 600,
              child: ChatScrollView(
                dataSource: ds,
                controller: controller,
                messageBuilder: (context, id, message, status, runLayout) =>
                    SizedBox(height: 60, child: Text('msg-$id')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double top(WidgetTester tester, int id) =>
      tester.getTopLeft(find.text('msg-$id')).dy;

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  }

  group('animateBy', () {
    testWidgets('travels exactly the delta, older then newer', (tester) async {
      await mount(tester);
      final before = top(tester, 75);

      final done = controller.animateBy(
        200,
        duration: const Duration(milliseconds: 400),
        curve: Curves.linear,
      );
      expect(controller.isAnimatingBy, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final mid = top(tester, 75) - before;
      expect(mid, inExclusiveRange(40, 160), reason: 'moves smoothly');
      await tester.pump(const Duration(milliseconds: 400));
      expect(await done, AnimateToDisposition.accepted);
      expect(controller.isAnimatingBy, isFalse);
      expect(top(tester, 75) - before, closeTo(200, 0.01));

      final done2 = controller.animateBy(
        -120,
        duration: const Duration(milliseconds: 300),
      );
      await settle(tester);
      expect(await done2, AnimateToDisposition.accepted);
      expect(top(tester, 75) - before, closeTo(80, 0.01));
    });

    testWidgets('default duration scales with travel and lands exactly', (
      tester,
    ) async {
      await mount(tester);
      final before = top(tester, 75);
      final done = controller.animateBy(900);
      await settle(tester);
      expect(await done, AnimateToDisposition.accepted);
      // Row 75 left the screen; the instant reverse shift brings it back to
      // exactly where it started iff the flight travelled exactly 900.
      controller.scrollBy(-900);
      await tester.pump();
      expect(top(tester, 75), closeTo(before, 0.01));
    });

    testWidgets('a user drag cancels the flight and keeps what it travelled', (
      tester,
    ) async {
      await mount(tester);
      final done = controller.animateBy(
        400,
        duration: const Duration(milliseconds: 800),
        curve: Curves.linear,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(controller.isAnimatingBy, isFalse);
      await done;
      await gesture.up();
      await settle(tester);
      final rest = top(tester, 75);
      await tester.pump(const Duration(seconds: 1));
      expect(top(tester, 75), closeTo(rest, 0.01), reason: 'flight is over');
    });

    testWidgets('scrollBy and jumpTo cancel the flight', (tester) async {
      await mount(tester);
      final done = controller.animateBy(
        400,
        duration: const Duration(milliseconds: 800),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.scrollBy(10);
      await tester.pump();
      expect(controller.isAnimatingBy, isFalse);
      await done;

      final second = controller.animateBy(
        400,
        duration: const Duration(milliseconds: 800),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.jumpTo(40);
      await tester.pump();
      expect(controller.isAnimatingBy, isFalse);
      await second;
    });

    testWidgets('busy: animateTo and animateBy honour the busy policy', (
      tester,
    ) async {
      await mount(tester);
      final by = controller.animateBy(
        300,
        duration: const Duration(milliseconds: 800),
      );
      await tester.pump();

      final ignoredTo = await controller.animateTo(30, highlight: false);
      expect(ignoredTo, AnimateToDisposition.ignored);
      expect(controller.isAnimatingBy, isTrue);

      final ignoredBy = await controller.animateBy(-50);
      expect(ignoredBy, AnimateToDisposition.ignored);

      final replacing = controller.animateTo(
        60,
        highlight: false,
        busyPolicy: AnimateToBusyPolicy.replace,
      );
      await tester.pump();
      expect(controller.isAnimatingBy, isFalse, reason: 'animateTo took over');
      await by;
      await settle(tester);
      expect(await replacing, AnimateToDisposition.accepted);

      final to = controller.animateTo(20, highlight: false);
      await tester.pump();
      expect(controller.isAnimating, isTrue);
      expect(
        await controller.animateBy(100),
        AnimateToDisposition.ignored,
        reason: 'animateTo in flight',
      );
      final replaced = controller.animateBy(
        100,
        busyPolicy: AnimateToBusyPolicy.replace,
      );
      await tester.pump();
      expect(controller.isAnimating, isFalse);
      expect(controller.isAnimatingBy, isTrue);
      await to;
      await settle(tester);
      expect(await replaced, AnimateToDisposition.accepted);
    });

    testWidgets('the same delta while in flight coalesces', (tester) async {
      await mount(tester);
      final before = top(tester, 75);
      final first = controller.animateBy(
        200,
        duration: const Duration(milliseconds: 500),
      );
      await tester.pump();
      final second = controller.animateBy(200);
      await settle(tester);
      expect(await first, AnimateToDisposition.accepted);
      expect(await second, AnimateToDisposition.coalesced);
      expect(top(tester, 75) - before, closeTo(200, 0.01), reason: 'once');
    });

    testWidgets('duration zero is an instant scrollBy', (tester) async {
      await mount(tester);
      final before = top(tester, 75);
      final result = await controller.animateBy(150, duration: Duration.zero);
      expect(result, AnimateToDisposition.accepted);
      expect(controller.isAnimatingBy, isFalse);
      await tester.pump();
      expect(top(tester, 75) - before, closeTo(150, 0.01));
    });

    testWidgets('zero and non-finite deltas start nothing', (tester) async {
      await mount(tester);
      final before = top(tester, 75);
      for (final pixels in [
        0.0,
        double.nan,
        double.infinity,
        -double.infinity,
      ]) {
        expect(
          await controller.animateBy(pixels),
          AnimateToDisposition.ignored,
          reason: '$pixels',
        );
      }
      expect(controller.isAnimatingBy, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(top(tester, 75), closeTo(before, 0.01));
    });

    testWidgets('a boundary ends the flight at the tail', (tester) async {
      await mount(tester);
      final before = top(tester, 79);
      final done = controller.animateBy(
        -300,
        duration: const Duration(milliseconds: 300),
      );
      await settle(tester);
      await done;
      expect(controller.isAnimatingBy, isFalse);
      expect(top(tester, 79), closeTo(before, 0.5));
    });

    testWidgets('a disposed controller ignores the call', (tester) async {
      await mount(tester);
      controller.dispose();
      expect(await controller.animateBy(100), AnimateToDisposition.ignored);
    });

    testWidgets('disposing mid-flight completes the future', (tester) async {
      await mount(tester);
      final done = controller.animateBy(
        400,
        duration: const Duration(milliseconds: 800),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.dispose();
      expect(await done, AnimateToDisposition.accepted);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    test('without a viewport it shifts like scrollBy', () async {
      final detached = ChatScrollController();
      addTearDown(detached.dispose);
      final before = detached.anchorPixelOffset;
      expect(await detached.animateBy(75), AnimateToDisposition.accepted);
      expect(detached.anchorPixelOffset, before + 75);
    });
  });
}
