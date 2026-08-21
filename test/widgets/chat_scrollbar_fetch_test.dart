import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
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

/// Lazy data source: boundaries are seeded immediately (so the scrollbar
/// has a known range), but chunks are not preloaded — each `fetchRange`
/// is recorded so the test can assert what the viewport asked for.
class _RecordingDataSource extends ChatDataSource {
  _RecordingDataSource(this.totalCount, {this.serveFetches = true}) {
    if (totalCount > 0) {
      seedBoundaries(
        oldestKnownId: 0,
        newestKnownId: totalCount - 1,
        reachedOldest: true,
        reachedNewest: true,
      );
    }
  }

  final int totalCount;
  final List<({int fromId, int toId})> requests = <({int fromId, int toId})>[];

  /// When false, [fetchRange] records but returns empty (load-gate stays open).
  bool serveFetches;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    requests.add((fromId: fromId, toId: toId));
    if (!serveFetches) return const <IChatMessage>[];
    final lo = fromId.clamp(0, totalCount - 1);
    final hi = toId.clamp(0, totalCount - 1);
    return <IChatMessage>[for (var i = lo; i <= hi; i++) _msg(i)];
  }
}

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ChatSelectionController? selectionController,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          selectionController: selectionController,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('scrollbar drag triggers fetch poll', () {
    testWidgets(
      'dragging the scrollbar fetches the chunks at release, no follow-up gesture',
      (tester) async {
        // Closer to the actual user complaint: a continuous *drag* along
        // the scrollbar (multiple PointerMove events), then release.
        // Without the fix, the poll never wakes because something keeps
        // suppressing it across the drag — only a subsequent gesture-scroll
        // on the viewport would actually wake the fetch.
        const total = 5000;
        final controller = ChatScrollController()..jumpTo(0);
        final ds = _RecordingDataSource(total);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(dataSource: ds, controller: controller),
        );
        await tester.pumpAndSettle();
        ds.requests.clear();

        // Drag down along the scrollbar strip from y=80 to y=540.
        final viewportTopLeft = tester.getTopLeft(find.byType(ChatScrollView));
        final start = viewportTopLeft + const Offset(395, 80);
        final end = viewportTopLeft + const Offset(395, 540);
        final gesture = await tester.startGesture(start);
        // Multiple intermediate moves, ~30 px each, to mimic a real drag.
        const stepCount = 15;
        for (var i = 1; i <= stepCount; i++) {
          await gesture.moveTo(
            Offset(start.dx, start.dy + (end.dy - start.dy) * (i / stepCount)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        // Pump beyond the poll interval (150 ms) so the timer can fire.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          ds.requests,
          isNotEmpty,
          reason:
              'scrollbar DRAG (not just tap) must trigger a fetch '
              'without requiring a follow-up viewport gesture.',
        );
        expect(controller.anchorMessageId, greaterThan(1000));
      },
    );

    testWidgets(
      'gesture-scroll first, then scrollbar-jump → fetch still fires',
      (tester) async {
        // This is the exact user-reported sequence: gesture-scroll the
        // viewport (which bumps `_lastScrollTs`), then scrollbar-jump to a
        // far position. Without the fix, `_pollTimer` from the gesture
        // scroll was left armed and `_lastScrollTs` was recent, so the
        // jump's layout silently skipped re-arming and the resulting tick
        // also bailed on the same-window debounce — fetch never fired
        // until the user nudged the viewport with another gesture.
        const total = 5000;
        final controller = ChatScrollController()..jumpTo(100);
        final ds = _RecordingDataSource(total);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(dataSource: ds, controller: controller),
        );
        await tester.pumpAndSettle();

        // Step 1: do a gesture-scroll on the viewport so `_lastScrollTs`
        // is bumped to "now".
        final viewportCenter = tester.getCenter(find.byType(ChatScrollView));
        final dragGesture = await tester.startGesture(viewportCenter);
        for (var i = 0; i < 5; i++) {
          await dragGesture.moveBy(const Offset(0, -20));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await dragGesture.up();
        await tester.pump(const Duration(milliseconds: 32));
        ds.requests.clear();

        // Step 2: IMMEDIATELY (within the debounce window) tap the
        // scrollbar at a far position. Without the fix, the jump's layout
        // would arm a poll with the full 150 ms delay, and the tick would
        // then bail on `now - _lastScrollTs < 150` — fetch silently
        // skipped, poll re-arms forever.
        final viewportTopLeft = tester.getTopLeft(find.byType(ChatScrollView));
        final tapPoint = viewportTopLeft + const Offset(395, 540);
        await tester.tapAt(tapPoint);
        // Pump well past the typical debounce so the timer must have had
        // every opportunity to fire.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          ds.requests,
          isNotEmpty,
          reason:
              'scrollbar jump performed within the post-gesture debounce '
              'window must still trigger a fetch — without a follow-up '
              'gesture-scroll.',
        );
        expect(controller.anchorMessageId, greaterThan(1000));
      },
    );

    testWidgets(
      'in selection mode: scrollbar drag still fetches the new range',
      (tester) async {
        // User-reported regression: entering selection mode (long-press)
        // then dragging the scrollbar reproduces the original
        // "fetch never starts" bug. The SelectableMessage wrapper adds a
        // `GestureDetector(behavior: HitTestBehavior.opaque)` per message,
        // which may interfere with the pointer-event routing or layout
        // cadence even though the scrollbar's pointer is on the trailing
        // strip outside the message body.
        const total = 5000;
        final controller = ChatScrollController()..jumpTo(0);
        final ds = _RecordingDataSource(total);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _scaffold(
            dataSource: ds,
            controller: controller,
            selectionController: selection,
          ),
        );
        await tester.pumpAndSettle();

        // Long-press a visible message to enter selection mode.
        await tester.longPress(find.text('msg-0'));
        await tester.pumpAndSettle();
        expect(selection.isSelectionMode, isTrue);
        ds.requests.clear();

        // Drag the scrollbar to a far position.
        final viewportTopLeft = tester.getTopLeft(find.byType(ChatScrollView));
        final start = viewportTopLeft + const Offset(395, 80);
        final end = viewportTopLeft + const Offset(395, 540);
        final gesture = await tester.startGesture(start);
        for (var i = 1; i <= 10; i++) {
          await gesture.moveTo(
            Offset(start.dx, start.dy + (end.dy - start.dy) * (i / 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          ds.requests,
          isNotEmpty,
          reason:
              'selection mode + scrollbar drag must trigger a fetch '
              'without a follow-up gesture.',
        );
        expect(controller.anchorMessageId, greaterThan(1000));
      },
    );

    testWidgets(
      'tapping the scrollbar at a far position fetches that chunk, no gesture needed',
      (tester) async {
        // Regression: after `_jumpToScrollbar` moved the anchor to a chunk
        // that had not been loaded yet, the fetch poll only fired once the
        // user *also* nudged the viewport with a gesture. The scrollbar drag
        // alone should be enough.
        const total = 5000;
        final controller = ChatScrollController()..jumpTo(0);
        final ds = _RecordingDataSource(total);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await tester.pumpWidget(
          _scaffold(dataSource: ds, controller: controller),
        );
        await tester.pumpAndSettle();

        // Drain the initial fetch — chunk 0 (messages 0..63).
        final initialChunks = ds.requests
            .map((r) => ChatScrollChunk.chunkOf(r.fromId))
            .toSet();
        expect(initialChunks, contains(0));
        ds.requests.clear();

        // Tap the right-edge scrollbar strip near the bottom — `jumpTo`
        // a far-off message id whose chunk has never been requested.
        final viewportTopLeft = tester.getTopLeft(find.byType(ChatScrollView));
        // y = 540 / 600 → progress ≈ 0.9 → target id ≈ 4500.
        final tapPoint = viewportTopLeft + const Offset(395, 540);
        await tester.tapAt(tapPoint);
        // Drive enough frames for layout + post-microtask poll to fire.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          ds.requests,
          isNotEmpty,
          reason:
              'scrollbar drag without a follow-up gesture must trigger '
              'a fetch for the chunks at the new anchor.',
        );
        // The anchor should be far from 0 now.
        expect(controller.anchorMessageId, greaterThan(1000));
        // And the requested range should cover the new anchor's chunk.
        final anchorChunk = ChatScrollChunk.chunkOf(controller.anchorMessageId);
        final requestedChunks = ds.requests.expand((r) {
          final lo = ChatScrollChunk.chunkOf(r.fromId);
          final hi = ChatScrollChunk.chunkOf(r.toId);
          return <int>[for (var i = lo; i <= hi; i++) i];
        }).toSet();
        expect(
          requestedChunks.contains(anchorChunk),
          isTrue,
          reason:
              'fetch must cover the chunk containing the new anchor; '
              'anchor chunk=$anchorChunk, requested=$requestedChunks',
        );
      },
    );

    testWidgets(
      'jump elsewhere during load-gate clears dest pin and fetches new anchor',
      (tester) async {
        // Dest-window pin must not starve scrollbar/jump fetches: jumping to a
        // different id cancels the in-flight animate and requests the new
        // layout range (not only the abandoned animate destination).
        const total = 2000;
        const loadedFrom = 1900;
        const animateTarget = 10;
        const jumpTarget = 1000;
        final controller = ChatScrollController()..jumpTo(total - 1);
        final ds = _RecordingDataSource(total, serveFetches: false);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        for (var i = loadedFrom; i < total; i++) {
          ds.upsertMessage(_msg(i));
        }

        await tester.pumpWidget(
          _scaffold(dataSource: ds, controller: controller),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final animating = controller.animateTo(
          animateTarget,
          duration: const Duration(milliseconds: 200),
          highlight: false,
          loadPolicy: AnimateToLoadPolicy.immediate,
        );
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        final render =
            tester.renderObject(find.byType(ChatScrollView))
                as RenderChatScrollView;
        expect(render.debugLoadGateWaiting, isTrue);

        ds.requests.clear();
        ds.serveFetches = true;
        controller.jumpTo(jumpTarget);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 200));

        expect(render.debugLoadGateWaiting, isFalse);
        expect(controller.anchorMessageId, jumpTarget);
        await animating;

        final jumpChunk = ChatScrollChunk.chunkOf(jumpTarget);
        final animateChunk = ChatScrollChunk.chunkOf(animateTarget);
        final requestedChunks = ds.requests.expand((r) {
          final lo = ChatScrollChunk.chunkOf(r.fromId);
          final hi = ChatScrollChunk.chunkOf(r.toId);
          return <int>[for (var i = lo; i <= hi; i++) i];
        }).toSet();
        expect(
          requestedChunks.contains(jumpChunk),
          isTrue,
          reason:
              'after jump-away, fetch must cover the new anchor chunk '
              '($jumpChunk); requested=$requestedChunks',
        );
        // Must not keep exclusive-storming only the abandoned animate window.
        expect(
          requestedChunks.length == 1 && requestedChunks.single == animateChunk,
          isFalse,
        );
      },
    );
  });
}
