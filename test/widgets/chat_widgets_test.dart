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
  });
}
