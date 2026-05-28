import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test data sources
// ---------------------------------------------------------------------------

/// All messages preloaded; [fetch] is a no-op.
class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(List<IChatMessage> messages) {
    upsertMessages(messages);
  }

  @override
  Future<List<IChatMessage>> fetch({
    int? from,
    int? to,
    DateTime? after,
  }) async => const <IChatMessage>[];
}

/// Empty until [fetch] resolves (after a delay) — exercises the shimmer path.
class _AsyncDataSource extends ChatDataSource {
  _AsyncDataSource(this.count);

  final int count;

  @override
  Future<List<IChatMessage>> fetch({
    int? from,
    int? to,
    DateTime? after,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final lo = (from ?? 0).clamp(0, count - 1);
    final hi = (to ?? count - 1).clamp(0, count - 1);
    return <IChatMessage>[for (var i = lo; i <= hi; i++) _msg(i)];
  }
}

/// Fails the first [failuresBeforeSuccess] fetches, then resolves normally.
/// Exercises the error → retry path.
class _FlakyDataSource extends ChatDataSource {
  _FlakyDataSource(this.count, {required this.failuresBeforeSuccess});

  final int count;
  final int failuresBeforeSuccess;
  int _attempts = 0;

  @override
  Future<List<IChatMessage>> fetch({
    int? from,
    int? to,
    DateTime? after,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final attempt = _attempts++;
    if (attempt < failuresBeforeSuccess) {
      throw StateError('flaky failure #$attempt');
    }
    final lo = (from ?? 0).clamp(0, count - 1);
    final hi = (to ?? count - 1).clamp(0, count - 1);
    return <IChatMessage>[for (var i = lo; i <= hi; i++) _msg(i)];
  }
}

IChatMessage _msg(int i) => ChatMessage$User(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

List<IChatMessage> _generate(int n) => <IChatMessage>[
  for (var i = 0; i < n; i++) _msg(i),
];

ChatScrollController _boundedController(int count) => ChatScrollController()
  ..oldestKnownId = 0
  ..newestKnownId = count - 1
  ..reachedOldest = true
  ..reachedNewest = true;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double cacheExtent = 250,
  double extraBuildExtent = 0,
  ValueListenable<double>? bottomPadding,
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
          extraBuildExtent: extraBuildExtent,
          bottomPadding: bottomPadding,
          messageBuilder: (context, id, message, status) => SizedBox(
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('widget ChatScrollView', () {
    testWidgets('renders the newest message and virtualizes the rest', (
      tester,
    ) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();

      expect(find.text('msg-255'), findsOneWidget);
      expect(find.text('msg-0'), findsNothing);

      final ro = _render(tester);
      expect(ro.debugChildCount, greaterThan(3));
      expect(ro.debugChildCount, lessThan(40)); // not all 256 are built
      expect(ro.debugChunkCount, greaterThan(0));
    });

    testWidgets('layout-driven scroll reveals older then newer messages', (
      tester,
    ) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();
      final ro = _render(tester);

      // Scroll up far enough to hit the top boundary.
      for (var i = 0; i < 150; i++) {
        controller.applyScrollDelta(200);
        ro.markNeedsLayout();
        await tester.pump();
      }
      expect(find.text('msg-0'), findsOneWidget);
      expect(find.text('msg-255'), findsNothing);

      // Scroll back down to the bottom.
      for (var i = 0; i < 150; i++) {
        controller.applyScrollDelta(-200);
        ro.markNeedsLayout();
        await tester.pump();
      }
      expect(find.text('msg-255'), findsOneWidget);
    });

    testWidgets('drag gesture scrolls the viewport', (tester) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();
      expect(find.text('msg-255'), findsOneWidget);

      // Finger drags down -> content moves down -> older messages appear.
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('msg-255'), findsNothing);
    });

    testWidgets('a fling keeps revealing messages after the finger lifts', (
      tester,
    ) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();
      final ro = _render(tester);

      // A downward fling reveals older messages: the finger lifts, inertia
      // carries the viewport onward on its own.
      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 600),
        4000,
      );
      await tester.pump();
      final afterThrow = ro.debugFirstId!;
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        ro.debugFirstId,
        lessThan(afterThrow),
        reason: 'inertia should keep revealing older messages',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a scroll repaints far more often than it relayouts (Tier-1)', (
      tester,
    ) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count ~/ 2);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      final ro = _render(tester);

      final layoutBefore = ro.debugLayoutFrameId;
      final paintBefore = ro.debugPaintFrameId;

      // The ticker repositions cached children and repaints; layout only
      // re-runs on the rare frame where the built range stops covering.
      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, -200),
        800,
      );
      await tester.pumpAndSettle();

      final layoutFrames = ro.debugLayoutFrameId - layoutBefore;
      final paintFrames = ro.debugPaintFrameId - paintBefore;
      expect(paintFrames, greaterThan(0));
      expect(
        paintFrames,
        greaterThan(layoutFrames),
        reason: 'scrolling should repaint far more than it relayouts',
      );
    });

    testWidgets('dragging the scrollbar teleports through the conversation', (
      tester,
    ) async {
      const count = 1000;
      final controller = _boundedController(count)..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();
      expect(controller.anchorMessageId, count - 1);

      // Press near the top of the right-edge scrollbar strip.
      final box = tester.getRect(find.byType(ChatScrollView));
      await tester.tapAt(Offset(box.right - 6, box.top + 24));
      await tester.pump();

      expect(
        controller.anchorMessageId,
        lessThan(count - 1),
        reason: 'a scrollbar tap near the top jumps toward older messages',
      );
    });

    testWidgets('jumpTo teleports to an arbitrary message', (tester) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();

      controller.jumpTo(40);
      await tester.pump();

      expect(find.text('msg-40'), findsOneWidget);
      expect(find.text('msg-255'), findsNothing);
    });

    testWidgets('shows shimmer placeholders, then content as chunks load', (
      tester,
    ) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(dataSource: _AsyncDataSource(count), controller: controller),
      );
      await tester.pump();

      // No data yet -> shimmer placeholders.
      expect(find.textContaining('shimmer-'), findsWidgets);
      expect(find.text('msg-255'), findsNothing);

      // Poll timer (150ms) triggers fetch; fetch resolves after 100ms.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('msg-255'), findsOneWidget);
    });

    testWidgets('evicts data chunks beyond maxChunks', (tester) async {
      const count = 4000; // ~63 chunks of 64 messages
      final ds = _PreloadedDataSource(_generate(count));
      final controller = _boundedController(count)..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller),
      );
      await tester.pump();
      final ro = _render(tester);

      // The data source created ~63 chunks up front; the first layout's LRU
      // pass trims live chunks down to ChatDataSource.maxChunks.
      expect(ro.debugChunkCount, lessThanOrEqualTo(ds.maxChunks));
      expect(ro.debugChunkCount, lessThan(63), reason: 'eviction must run');

      // Teleporting elsewhere keeps the live set bounded.
      controller.jumpTo(count ~/ 2);
      await tester.pump();
      expect(ro.debugChunkCount, lessThanOrEqualTo(ds.maxChunks));
    });

    testWidgets('exposes scroll-action semantics that track position', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();

      // Pinned at the bottom — can reveal older (scrollDown), not newer.
      final bottom = tester
          .getSemantics(find.byType(ChatScrollView))
          .getSemanticsData();
      expect(bottom.hasAction(SemanticsAction.scrollDown), isTrue);
      expect(bottom.hasAction(SemanticsAction.scrollUp), isFalse);

      // Mid-conversation — both directions available.
      controller.jumpTo(count ~/ 2);
      await tester.pump();
      final middle = tester
          .getSemantics(find.byType(ChatScrollView))
          .getSemanticsData();
      expect(middle.hasAction(SemanticsAction.scrollUp), isTrue);
      expect(middle.hasAction(SemanticsAction.scrollDown), isTrue);

      handle.dispose();
    });

    testWidgets('extraBuildExtent keeps extra children mounted', (tester) async {
      const count = 256;

      final base = _boundedController(count)..jumpTo(count ~/ 2);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: base,
          cacheExtent: 100,
        ),
      );
      await tester.pumpAndSettle();
      final withoutExtra = _render(tester).debugChildCount;

      final kept = _boundedController(count)..jumpTo(count ~/ 2);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: kept,
          cacheExtent: 100,
          extraBuildExtent: 1200,
        ),
      );
      await tester.pumpAndSettle();
      final withExtra = _render(tester).debugChildCount;

      expect(withExtra, greaterThan(withoutExtra));
    });

    testWidgets('bottomPadding reserves space after the newest message', (
      tester,
    ) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      final inset = ValueNotifier<double>(150);
      addTearDown(inset.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          bottomPadding: inset,
        ),
      );
      await tester.pump();

      // Viewport is 600 tall, messages 60 tall: the newest message is pinned
      // so its bottom sits `inset` pixels above the viewport bottom.
      expect(
        tester.getTopLeft(find.text('msg-255')).dy,
        closeTo(600 - 150 - 60, 1),
      );

      // Growing the inset while pinned at the bottom carries the message up.
      inset.value = 260;
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('msg-255')).dy,
        closeTo(600 - 260 - 60, 1),
      );
    });

    testWidgets('topPadding leaves room for an overlay header', (tester) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(8);
      final inset = ValueNotifier<double>(0);
      addTearDown(inset.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: _PreloadedDataSource(_generate(count)),
                  controller: controller,
                  topPadding: inset,
                  messageBuilder: (context, id, message, status) => SizedBox(
                    height: 60,
                    child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
                  ),
                  dateSeparatorBuilder: (context, date) => SizedBox(
                    height: 24,
                    child: Text('sep-${date.day}'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final ro = _render(tester);

      // Floating header pinned to the very top while topPadding is 0.
      expect(ro.debugFloatingHeaderOffset, closeTo(0, 0.1));

      inset.value = 50;
      await tester.pump();
      // After bumping topPadding the floating header sits below the inset.
      expect(ro.debugFloatingHeaderOffset, closeTo(50, 0.1));
    });

    testWidgets('swapping bottomPadding to a listenable with a larger value '
        'follows the new inset', (tester) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      final firstInset = ValueNotifier<double>(50);
      final secondInset = ValueNotifier<double>(200);
      addTearDown(firstInset.dispose);
      addTearDown(secondInset.dispose);

      Widget build(ValueListenable<double> inset) => _harness(
        dataSource: _PreloadedDataSource(_generate(count)),
        controller: controller,
        bottomPadding: inset,
      );

      await tester.pumpWidget(build(firstInset));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('msg-255')).dy,
        closeTo(600 - 50 - 60, 1),
      );

      // Swap the listenable itself — different instance, different current
      // value. The viewport's setter must catch the value change, not just
      // listener-value changes on the existing instance.
      await tester.pumpWidget(build(secondInset));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('msg-255')).dy,
        closeTo(600 - 200 - 60, 1),
      );
    });

    testWidgets('messageBuilder swap re-inflates messages with the new '
        'output', (tester) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(count - 1);
      final dataSource = _PreloadedDataSource(_generate(count));

      Widget build(String prefix) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 600,
              child: ChatScrollView(
                dataSource: dataSource,
                controller: controller,
                messageBuilder: (context, id, message, status) =>
                    SizedBox(height: 60, child: Text('$prefix-$id')),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(build('first'));
      await tester.pump();
      expect(find.text('first-255'), findsOneWidget);

      await tester.pumpWidget(build('second'));
      await tester.pump();
      // Skip-rebuild cache must clear on builder change; otherwise the new
      // builder's output would not reach already-built messages.
      expect(find.text('second-255'), findsOneWidget);
      expect(find.text('first-255'), findsNothing);
    });

    testWidgets('swapping the data source cancels in-flight fetches on the '
        'old one', (tester) async {
      const count = 64;
      final controller = _boundedController(count)..jumpTo(count - 1);
      final first = _AsyncDataSource(count);
      final second = _PreloadedDataSource(_generate(count));

      await tester.pumpWidget(
        _harness(dataSource: first, controller: controller),
      );
      // First layout primes the poll; flush microtasks so it actually arms.
      await tester.pump();
      // Mid-fetch — the async source's 100ms delay has not elapsed yet.
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        first.chunks.values.any((c) => c.status.isFetching),
        isTrue,
        reason: 'fetch should be in flight before the swap',
      );

      await tester.pumpWidget(
        _harness(dataSource: second, controller: controller),
      );
      // Past the original 100ms window — the cancelled fetch must NOT mark
      // chunks valid (no listener would resurrect it anyway, but cancelFetch
      // also clears the fetching flag so we can observe it dropped).
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        first.chunks.values.any((c) => c.status.isFetching),
        isFalse,
        reason: 'old source must have dropped the fetching flag',
      );
      expect(find.text('msg-63'), findsOneWidget);
    });

    testWidgets('detaching cancels the in-flight fetch', (tester) async {
      const count = 64;
      final controller = _boundedController(count)..jumpTo(count - 1);
      final source = _AsyncDataSource(count);
      // Dispose drains pending timers in the source's `Future.delayed`.
      addTearDown(source.dispose);

      await tester.pumpWidget(
        _harness(dataSource: source, controller: controller),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        source.chunks.values.any((c) => c.status.isFetching),
        isTrue,
      );

      // Tear the viewport out of the tree.
      await tester.pumpWidget(const SizedBox.shrink());
      // The cancellation clears the flag synchronously via cancelFetch().
      expect(
        source.chunks.values.any((c) => c.status.isFetching),
        isFalse,
      );
      // Let the orphaned Future.delayed timer fire before the test ends so
      // flutter_test's "timer still pending" guard doesn't trip on the
      // (harmless) fetch resolution that lands in a now-null _fetchToken.
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a failed fetch flips chunks to error and retries', (
      tester,
    ) async {
      const count = 64;
      final controller = _boundedController(count)..jumpTo(count - 1);
      final source = _FlakyDataSource(count, failuresBeforeSuccess: 1);

      await tester.pumpWidget(
        _harness(dataSource: source, controller: controller),
      );
      await tester.pump();
      // First fetch fails (after its 30ms delay) — chunks should land in
      // error.
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        source.chunks.values.any((c) => c.status.isError),
        isTrue,
        reason: 'failed fetch should mark chunks error',
      );
      expect(find.text('msg-63'), findsNothing);

      // Backoff is 500–1000ms (step 0); after one retry the second fetch
      // succeeds and msg-63 appears.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('msg-63'), findsOneWidget);
      expect(
        source.chunks.values.any((c) => c.status.isError),
        isFalse,
      );
    });
  });
}
