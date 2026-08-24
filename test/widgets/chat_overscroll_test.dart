import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/gestures.dart';
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
    for (final chunk in chunks.values) {
      chunk.status = ChatMessageStatus.valid;
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

Future<TestGesture> _holdDragPast(
  WidgetTester tester,
  Offset totalDelta, {
  required int steps,
}) async {
  final center = tester.getCenter(find.byType(ChatScrollView));
  final gesture = await tester.startGesture(center);
  final stepDelta = totalDelta / steps.toDouble();
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(stepDelta);
    await tester.pump(const Duration(milliseconds: 32));
  }
  return gesture;
}

void main() {
  group('overscroll stretch', () {
    testWidgets('drag past oldest stretches paint, layout stays pinned', (
      tester,
    ) async {
      const count = 20;
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      final viewportTop = tester.getTopLeft(find.byType(ChatScrollView)).dy;
      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      expect(
        _render(tester).debugStretchOverscroll,
        greaterThan(0.01),
        reason: 'unconsumed dy at the oldest edge must paint EdgeEffect stretch',
      );
      expect(
        tester.getTopLeft(find.text('msg-0')).dy,
        closeTo(viewportTop, 0.5),
        reason: 'layout must stay clamped; stretch is paint-only',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_render(tester).debugStretchOverscroll, closeTo(0, 0.001));
      expect(tester.getTopLeft(find.text('msg-0')).dy, closeTo(viewportTop, 0.5));
    });

    testWidgets('mid-content drag does not stretch', (tester) async {
      const count = 40;
      final controller = ChatScrollController()..jumpTo(20);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      final yBefore = tester.getTopLeft(find.text('msg-20')).dy;
      final gesture = await _holdDragPast(
        tester,
        const Offset(0, -240),
        steps: 12,
      );
      expect(
        _render(tester).debugStretchOverscroll.abs(),
        lessThan(0.001),
        reason: 'travel inside the conversation must not feed EdgeEffect',
      );
      expect(
        tester.getTopLeft(find.text('msg-20')).dy,
        isNot(closeTo(yBefore, 1)),
        reason: 'mid-content drag must actually scroll',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_render(tester).debugStretchOverscroll.abs(), lessThan(0.001));
    });

    testWidgets('fling into newest edge absorbs into stretch', (tester) async {
      const count = 40;
      final controller = ChatScrollController()..jumpTo(count - 4);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      // Finger-up fling toward newer — not starting on the edge.
      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, -500),
        8000,
      );

      var sawStretch = false;
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_render(tester).debugStretchOverscroll.abs() > 0.005) {
          sawStretch = true;
          break;
        }
      }
      expect(
        sawStretch,
        isTrue,
        reason: 'fling leftover velocity at the newest pin must absorb',
      );

      await tester.pumpAndSettle();
      expect(_render(tester).debugStretchOverscroll.abs(), lessThan(0.001));
    });

    testWidgets('mouse wheel past boundary is clamped, no stretch spring', (
      tester,
    ) async {
      const count = 20;
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      final viewportTopLeft = tester.getTopLeft(find.byType(ChatScrollView));
      final center = viewportTopLeft + const Offset(200, 300);
      final testPointer = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(center);
      await tester.sendEventToBinding(
        testPointer.scroll(const Offset(0, -1000)),
      );
      await tester.pumpAndSettle();
      expect(_render(tester).debugStretchOverscroll.abs(), lessThan(0.001));
      final firstBoxTop = tester.getTopLeft(find.text('msg-0'));
      expect(firstBoxTop.dy, closeTo(viewportTopLeft.dy, 0.5));
    });

    testWidgets('keyboard scroll past boundary is clamped, no stretch', (
      tester,
    ) async {
      const count = 20;
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      controller.scrollBy(500);
      await tester.pumpAndSettle();

      expect(_render(tester).debugStretchOverscroll.abs(), lessThan(0.001));
      final viewportTopLeft = tester.getTopLeft(find.byType(ChatScrollView));
      final firstBoxTop = tester.getTopLeft(find.text('msg-0'));
      expect(firstBoxTop.dy, closeTo(viewportTopLeft.dy, 0.5));
    });

    testWidgets('short content stretch settles with rest pin intact', (
      tester,
    ) async {
      const count = 3;
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      final viewportTopLeft = tester.getTopLeft(find.byType(ChatScrollView));
      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 250),
        steps: 10,
      );
      expect(_render(tester).debugStretchOverscroll.abs(), greaterThan(0.01));
      expect(
        tester.getTopLeft(find.text('msg-0')).dy,
        closeTo(viewportTopLeft.dy, 1.0),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_render(tester).debugStretchOverscroll.abs(), lessThan(0.001));
      expect(
        tester.getTopLeft(find.text('msg-0')).dy,
        closeTo(viewportTopLeft.dy, 1.0),
      );
    });
  });
}
