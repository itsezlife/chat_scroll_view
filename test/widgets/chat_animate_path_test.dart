import 'dart:async' show unawaited;

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

/// Tail loaded; older ids stay cold until [releaseTargetWindow] upserts them.
class _GatedColdTargetDataSource extends ChatDataSource {
  _GatedColdTargetDataSource({
    required this.totalCount,
    required int loadedFrom,
  }) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: totalCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (var i = loadedFrom; i < totalCount; i++) {
      upsertMessage(_msg(i));
    }
  }

  final int totalCount;

  void releaseTargetWindow({required int aroundId, int radius = 32}) {
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

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          cacheExtent: 200,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

/// Every [ChatAnimateEnd] the controller emits, in order.
List<ChatAnimateEnd> _recordAnimateEnds(ChatScrollController controller) {
  final ends = <ChatAnimateEnd>[];
  controller.addScrollListener((event) {
    if (event case final ChatAnimateEnd end) ends.add(end);
  });
  return ends;
}

/// Drives [future] with a hard pump budget — stitch keeps scheduling frames,
/// so neither a bare await nor `pumpAndSettle` is safe.
Future<void> _drive(
  WidgetTester tester,
  Future<void> future, {
  int maxPumps = 400,
}) async {
  await tester.pump();
  var done = false;
  unawaited(future.whenComplete(() => done = true));
  for (var i = 0; i < maxPumps && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done, isTrue, reason: 'animateTo did not finish in $maxPumps pumps');
}

void main() {
  group('ChatAnimateEnd.path', () {
    late ChatScrollController controller;
    late List<ChatAnimateEnd> ends;

    Future<void> mount(
      WidgetTester tester,
      ChatDataSource ds,
      int openAt,
    ) async {
      controller = ChatScrollController()..jumpTo(openAt);
      ends = _recordAnimateEnds(controller);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
    }

    testWidgets('a built target reports the close path', (tester) async {
      await mount(tester, _PreloadedDataSource(256), 128);

      await _drive(tester, controller.animateTo(126, highlight: false));

      expect(ends.single.targetId, 126);
      expect(ends.single.path, AnimateToPath.close);
    });

    testWidgets('a target already at its aligned seat reports the close path', (
      tester,
    ) async {
      await mount(tester, _PreloadedDataSource(256), 128);

      await _drive(tester, controller.animateTo(128, highlight: false));

      expect(ends.single.path, AnimateToPath.close);
    });

    testWidgets('a target that is not built reports the stitch path', (
      tester,
    ) async {
      await mount(tester, _PreloadedDataSource(256), 128);

      await _drive(tester, controller.animateTo(0, highlight: false));

      expect(ends.single.targetId, 0);
      expect(ends.single.path, AnimateToPath.stitch);
    });

    testWidgets('an unready target waits on the load gate, then reports the '
        'stitch path', (tester) async {
      const total = 200;
      const target = 10;
      final ds = _GatedColdTargetDataSource(totalCount: total, loadedFrom: 192);
      await mount(tester, ds, total - 1);

      final future = controller.animateTo(target, highlight: false);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.isAnimating, isTrue);
      expect(ends, isEmpty, reason: 'the load gate is still waiting');

      ds.releaseTargetWindow(aroundId: target);
      await _drive(tester, future);

      expect(controller.anchorMessageId, target);
      expect(ends.single.path, AnimateToPath.stitch);
    });

    testWidgets('a navigation cancelled on the load gate reports no path', (
      tester,
    ) async {
      const total = 200;
      final ds = _GatedColdTargetDataSource(totalCount: total, loadedFrom: 192);
      await mount(tester, ds, total - 1);

      final future = controller.animateTo(10, highlight: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      controller.scrollBy(-20);
      await _drive(tester, future);

      expect(ends.single.path, AnimateToPath.none);
    });

    testWidgets('a stitch cancelled mid-flight still reports the stitch path', (
      tester,
    ) async {
      await mount(tester, _PreloadedDataSource(256), 128);

      final future = controller.animateTo(
        0,
        duration: const Duration(milliseconds: 800),
        highlight: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      controller.scrollBy(-20);
      await _drive(tester, future);

      expect(ends.single.path, AnimateToPath.stitch);
    });

    testWidgets('a zero duration reports the instant path', (tester) async {
      await mount(tester, _PreloadedDataSource(256), 128);

      await _drive(
        tester,
        controller.animateTo(0, duration: Duration.zero, highlight: false),
      );

      expect(controller.anchorMessageId, 0);
      expect(ends.single.path, AnimateToPath.instant);
    });

    testWidgets('a coalesced call adds no end; the flight reports its path '
        'once', (tester) async {
      await mount(tester, _PreloadedDataSource(256), 128);

      final first = controller.animateTo(0, highlight: false);
      final second = controller.animateTo(0, highlight: false);
      await _drive(tester, first);

      expect(await second, AnimateToDisposition.coalesced);
      expect(ends.single.path, AnimateToPath.stitch);
    });

    testWidgets('an ignored call reports nothing', (tester) async {
      await mount(tester, _PreloadedDataSource(256), 128);

      final first = controller.animateTo(0, highlight: false);
      expect(
        await controller.animateTo(126, highlight: false),
        AnimateToDisposition.ignored,
      );
      await _drive(tester, first);

      expect(ends.map((end) => end.targetId), [0]);
    });

    test('an unbound controller places the target as a jump and emits no '
        'animate events', () async {
      final unbound = ChatScrollController();
      addTearDown(unbound.dispose);
      final events = <ChatScrollEvent>[];
      unbound.addScrollListener(events.add);

      expect(await unbound.animateTo(42), AnimateToDisposition.accepted);

      expect(events, [isA<ChatProgrammaticJump>()]);
    });
  });
}
