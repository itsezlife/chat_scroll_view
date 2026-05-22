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
  double keepAliveExtent = 0,
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
          keepAliveExtent: keepAliveExtent,
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

    testWidgets('keepAliveExtent keeps extra children mounted', (tester) async {
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
      final withoutKeepAlive = _render(tester).debugChildCount;

      final kept = _boundedController(count)..jumpTo(count ~/ 2);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: kept,
          cacheExtent: 100,
          keepAliveExtent: 1200,
        ),
      );
      await tester.pumpAndSettle();
      final withKeepAlive = _render(tester).debugChildCount;

      expect(withKeepAlive, greaterThan(withoutKeepAlive));
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
