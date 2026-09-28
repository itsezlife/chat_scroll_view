import 'package:chat_scroll_view/chat_scroll_view.dart';
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

const double _rowHeight = 60;

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ChatScrollPhysics? physics,
  ChatSelectionController? selection,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          physics: physics,
          selectionController: selection,
          messageBuilder: (context, id, message, status, runLayout) =>
              ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: SizedBox(
                  height: _rowHeight,
                  child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
                ),
              ),
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

double _viewportTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(ChatScrollView)).dy;

/// Opaque row box of message [id] — hit anywhere inside its extent.
RenderBox _rowBox(WidgetTester tester, int id) =>
    tester.renderObject<RenderBox>(
      find
          .ancestor(of: find.text('msg-$id'), matching: find.byType(ColoredBox))
          .first,
    );

/// Global top of a built row near the middle of the built range.
({int id, double top}) _probeRow(WidgetTester tester) {
  final render = _render(tester);
  final id = (render.debugFirstId! + render.debugLastId!) ~/ 2;
  return (id: id, top: tester.getTopLeft(find.text('msg-$id')).dy);
}

/// The viewport child hosting message [id].
ChatMessageParentData _viewportParentData(WidgetTester tester, int id) {
  RenderObject? node = _rowBox(tester, id);
  while (node != null) {
    if (node.parentData case final ChatMessageParentData data) return data;
    node = node.parent;
  }
  throw StateError('msg-$id is not a viewport child');
}

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
  group('scroll physics', () {
    testWidgets('null physics runs the android stretch', (tester) async {
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      expect(_render(tester).debugStretchOverscroll, greaterThan(0.01));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('unequal physics swap cancels the fling with a fling end', (
      tester,
    ) async {
      const count = 200;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      final events = <ChatScrollEvent>[];
      controller.addScrollListener(events.add);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 200),
        3000,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(events.whereType<ChatFlingStart>(), hasLength(1));
      events.clear();

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          physics: const ChatScrollPhysics(
            fling: ChatFling.spline(friction: 0.03),
            edgeEffect: ChatEdgeEffect.stretch(),
          ),
        ),
      );
      expect(events.whereType<ChatFlingEnd>(), hasLength(1));

      final probe = _probeRow(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(find.text('msg-${probe.id}')).dy,
        closeTo(probe.top, 0.01),
        reason: 'the swap stopped inertial travel',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('equal physics rebuild keeps the fling running', (
      tester,
    ) async {
      const count = 200;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      final events = <ChatScrollEvent>[];
      controller.addScrollListener(events.add);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 200),
        3000,
      );
      await tester.pump(const Duration(milliseconds: 16));
      events.clear();

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          // Non-const on purpose: an equal value, not the identical one.
          // ignore: prefer_const_constructors
          physics: ChatScrollPhysics(
            // ignore: prefer_const_constructors
            fling: ChatFling.spline(),
            // ignore: prefer_const_constructors
            edgeEffect: ChatEdgeEffect.stretch(),
          ),
        ),
      );
      expect(events.whereType<ChatFlingEnd>(), isEmpty);

      final probe = _probeRow(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(find.text('msg-${probe.id}')).dy,
        greaterThan(probe.top + 1),
        reason: 'the fling kept travelling',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('unequal physics swap resets the edge effect', (tester) async {
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      expect(_render(tester).debugStretchOverscroll, greaterThan(0.01));

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          physics: const ChatScrollPhysics(
            fling: ChatFling.spline(),
            edgeEffect: ChatEdgeEffect.stretch(intensity: 0.03),
          ),
        ),
      );
      expect(_render(tester).debugStretchOverscroll, 0);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('press during an edge spring', () {
    testWidgets('freezes the stretch and suppresses long-press', (
      tester,
    ) async {
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(20);
      final selection = ChatSelectionController();
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, selection: selection),
      );
      await tester.pumpAndSettle();

      final drag = await _holdDragPast(tester, const Offset(0, 400), steps: 20);
      await drag.up();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final springing = _render(tester).debugStretchOverscroll;
      expect(springing, greaterThan(0.004));

      final press = await tester.startGesture(
        tester.getCenter(find.text('msg-2')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final frozen = _render(tester).debugStretchOverscroll;
      expect(frozen, greaterThan(0.004));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _render(tester).debugStretchOverscroll,
        frozen,
        reason: 'the press holds the stretch where it caught it',
      );

      await tester.pump(const Duration(milliseconds: 600));
      expect(
        selection.isSelectionMode,
        isFalse,
        reason: 'the catching press must not select a moving row',
      );

      await press.up();
      await tester.pumpAndSettle();
      expect(_render(tester).debugStretchOverscroll, closeTo(0, 0.001));
      expect(selection.isSelectionMode, isFalse);

      await tester.longPress(find.text('msg-2'));
      await tester.pumpAndSettle();
      expect(
        selection.isSelectionMode,
        isTrue,
        reason: 'suppression ends with the catching press',
      );
    });
  });

  group('edge transform geometry', () {
    testWidgets('reported paint transform follows the stretch', (tester) async {
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      final s = _render(tester).debugStretchOverscroll;
      expect(s, greaterThan(0.01));
      expect(
        tester.getTopLeft(find.text('msg-4')).dy - _viewportTop(tester),
        closeTo(4 * _rowHeight * (1 + s), 0.01),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('hit-testing lands on the painted row', (tester) async {
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      final s = _render(tester).debugStretchOverscroll;
      // Two px above row 4's bottom edge in layout, which paints below
      // row 5's layout top once stretched.
      const contentY = 5 * _rowHeight - 2;
      expect(contentY * (1 + s), greaterThan(5 * _rowHeight));
      final global = Offset(
        tester.getCenter(find.byType(ChatScrollView)).dx,
        _viewportTop(tester) + contentY * (1 + s),
      );
      final result = tester.hitTestOnBinding(global);
      final targets = [for (final entry in result.path) entry.target];
      expect(targets, contains(_rowBox(tester, 4)));
      expect(targets, isNot(contains(_rowBox(tester, 5))));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('row chrome paint top follows the stretch', (tester) async {
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      final s = _render(tester).debugStretchOverscroll;
      expect(s, greaterThan(0.01));
      expect(
        _viewportParentData(tester, 4).paintTop,
        closeTo(4 * _rowHeight * (1 + s), 0.01),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_viewportParentData(tester, 4).paintTop, closeTo(240, 0.01));
    });
  });
}
