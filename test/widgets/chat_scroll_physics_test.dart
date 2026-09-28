import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart';
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

/// Painted top of message [id] relative to the viewport top.
double _rowTop(WidgetTester tester, int id) =>
    tester.getTopLeft(find.text('msg-$id')).dy - _viewportTop(tester);

/// Pumps 60 Hz frames until nothing is scheduled; returns the largest
/// painted top of message [id] seen while it was built.
Future<double> _peakRowTop(WidgetTester tester, int id) async {
  var peak = double.negativeInfinity;
  for (var i = 0; i < 300 && tester.binding.hasScheduledFrame; i++) {
    await tester.pump(const Duration(microseconds: 16667));
    if (find.text('msg-$id').evaluate().isNotEmpty) {
      peak = math.max(peak, _rowTop(tester, id));
    }
  }
  return peak;
}

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
    testWidgets('null physics stretches on the test platform', (tester) async {
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

  group('rubber-band', () {
    const rubberBand = ChatScrollPhysics.rubberBand();

    Future<(ChatScrollController, _PreloadedDataSource)> pumpAtOldest(
      WidgetTester tester, {
      int count = 20,
      ChatScrollPhysics? physics = rubberBand,
      ChatSelectionController? selection,
    }) async {
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          physics: physics,
          selection: selection,
        ),
      );
      await tester.pumpAndSettle();
      return (controller, ds);
    }

    testWidgets('translates the message layer, then springs back', (
      tester,
    ) async {
      await pumpAtOldest(tester);
      expect(_rowTop(tester, 0), 0);

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      final offset = _rowTop(tester, 0);
      // At most the 400 px pull on the 600 px band: 600·0.55·400 / 820.
      expect(offset, inInclusiveRange(140, 161));
      expect(
        _rowTop(tester, 4) - offset,
        closeTo(4 * _rowHeight, 0.01),
        reason: 'a translate, not a scale',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(_rowTop(tester, 0), 0);
      expect(_rowTop(tester, 4), 4 * _rowHeight);
    });

    testWidgets('reverse drag consumes the overshoot before content moves', (
      tester,
    ) async {
      await pumpAtOldest(tester);

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      final pulled = _rowTop(tester, 0);

      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 32));
      }
      final eased = _rowTop(tester, 0);
      expect(eased, lessThan(pulled));
      expect(eased, greaterThan(100), reason: 'still past the pin');
      expect(
        _rowTop(tester, 4) - eased,
        closeTo(4 * _rowHeight, 0.01),
        reason: 'layout stays pinned while the overshoot unwinds',
      );

      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 32));
      }
      // The remaining ~300 px of pull unwinds first; the last ~100 px of
      // the 400 px reverse drag scrolls content.
      expect(_rowTop(tester, 4), inInclusiveRange(118, 145));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a fling into the edge overshoots and settles', (tester) async {
      final controller = ChatScrollController()..jumpTo(10);
      final ds = _PreloadedDataSource(40);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      final events = <ChatScrollEvent>[];
      controller.addScrollListener(events.add);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, physics: rubberBand),
      );
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 200),
        3000,
      );
      expect(events.whereType<ChatFlingStart>(), hasLength(1));

      final peak = await _peakRowTop(tester, 0);
      expect(peak, greaterThan(10), reason: 'leftover velocity overshoots');
      expect(events.whereType<ChatFlingEnd>(), hasLength(1));
      await tester.pumpAndSettle();
      expect(_rowTop(tester, 0), 0);
    });

    /// Pulls 400 px past the oldest edge, then flicks back toward content in
    /// [steps] moves of [stepPx] 8 ms apart and lifts while the layer is
    /// still displaced.
    Future<void> flickBackWhileDisplaced(
      WidgetTester tester, {
      required double stepPx,
      int steps = 5,
    }) async {
      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      var t = const Duration(seconds: 10);
      for (var i = 0; i < steps; i++) {
        t += const Duration(milliseconds: 8);
        await gesture.moveBy(Offset(0, -stepPx), timeStamp: t);
      }
      await tester.pump(const Duration(milliseconds: 8));
      expect(_rowTop(tester, 0), greaterThan(50), reason: 'still displaced');
      await gesture.up(timeStamp: t + const Duration(milliseconds: 8));
    }

    testWidgets('a flick back toward content carries into a content fling', (
      tester,
    ) async {
      final (controller, _) = await pumpAtOldest(tester, count: 60);
      final events = <ChatScrollEvent>[];
      controller.addScrollListener(events.add);

      await flickBackWhileDisplaced(tester, stepPx: 20);
      expect(events.whereType<ChatFlingStart>(), hasLength(1));

      var previous = double.infinity;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(microseconds: 16667));
        if (find.text('msg-0').evaluate().isEmpty) break;
        final top = _rowTop(tester, 0);
        expect(top, lessThanOrEqualTo(previous), reason: 'frame $i');
        previous = top;
      }
      await tester.pumpAndSettle();
      final settled = find.text('msg-0').evaluate().isEmpty
          ? double.negativeInfinity
          : _rowTop(tester, 0);
      expect(settled, lessThan(-300), reason: 'momentum scrolls content');
    });

    testWidgets('a weak flick back that dies while displaced springs home', (
      tester,
    ) async {
      await pumpAtOldest(tester, count: 60);
      // ~375 px/s over 30 px: a fling, but one that travels less than the
      // pull left to unwind.
      await flickBackWhileDisplaced(tester, stepPx: 3, steps: 10);
      await tester.pumpAndSettle();
      expect(_rowTop(tester, 0), 0);
      expect(_rowTop(tester, 4), 4 * _rowHeight);
    });

    testWidgets('a flick back on short content springs home', (tester) async {
      await pumpAtOldest(tester, count: 5);
      await flickBackWhileDisplaced(tester, stepPx: 20);
      await tester.pumpAndSettle();
      expect(_rowTop(tester, 0), 0);
    });

    testWidgets('releasing mid-pull does not throw the layer further out', (
      tester,
    ) async {
      await pumpAtOldest(tester);
      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 300),
        steps: 15,
      );
      var t = const Duration(seconds: 10);
      var lastStep = 0.0;
      for (var i = 0; i < 6; i++) {
        final before = _rowTop(tester, 0);
        t += const Duration(microseconds: 16667);
        await gesture.moveBy(const Offset(0, 20), timeStamp: t);
        await tester.pump(const Duration(microseconds: 16667));
        lastStep = _rowTop(tester, 0) - before;
      }
      final released = _rowTop(tester, 0);
      await gesture.up(timeStamp: t + const Duration(microseconds: 16667));

      final peak = await _peakRowTop(tester, 0);
      expect(lastStep, greaterThan(1), reason: 'the pull was still moving');
      expect(
        peak - released,
        lessThanOrEqualTo(lastStep * 1.5),
        reason: 'the overshoot follows the layer, not the finger',
      );
      expect(_rowTop(tester, 0), 0);
    });

    testWidgets('the frame after a moving release keeps moving', (
      tester,
    ) async {
      await pumpAtOldest(tester);
      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 300),
        steps: 15,
      );
      var t = const Duration(seconds: 10);
      var lastStep = 0.0;
      for (var i = 0; i < 6; i++) {
        final before = _rowTop(tester, 0);
        t += const Duration(microseconds: 16667);
        await gesture.moveBy(const Offset(0, 20), timeStamp: t);
        await tester.pump(const Duration(microseconds: 16667));
        lastStep = _rowTop(tester, 0) - before;
      }
      final released = _rowTop(tester, 0);
      await gesture.up(timeStamp: t + const Duration(microseconds: 16667));
      await tester.pump(const Duration(microseconds: 16667));

      expect(lastStep, greaterThan(1));
      // The spring's pull home cancels most of the outward speed within a
      // frame this deep in the band; a stalled clock moves exactly 0.
      expect(
        _rowTop(tester, 0) - released,
        greaterThan(0.1),
        reason: 'the spring clock starts at the last painted frame',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a fling overshoots on its impact frame', (tester) async {
      final controller = ChatScrollController()..jumpTo(10);
      final ds = _PreloadedDataSource(40);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      final events = <ChatScrollEvent>[];
      controller.addScrollListener(events.add);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, physics: rubberBand),
      );
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 200),
        3000,
      );
      var sawPin = false;
      for (var i = 0; i < 120 && tester.binding.hasScheduledFrame; i++) {
        await tester.pump(const Duration(microseconds: 16667));
        if (events.whereType<ChatFlingEnd>().isNotEmpty) {
          sawPin = true;
          expect(
            _rowTop(tester, 0),
            greaterThan(1),
            reason: 'the frame the fling ends at the pin already overshoots',
          );
          break;
        }
      }
      expect(sawPin, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('a press during the spring freezes it without selecting', (
      tester,
    ) async {
      final selection = ChatSelectionController();
      addTearDown(selection.dispose);
      await pumpAtOldest(tester, selection: selection);

      final drag = await _holdDragPast(tester, const Offset(0, 400), steps: 20);
      await drag.up();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_rowTop(tester, 0), greaterThan(1));

      final press = await tester.startGesture(
        tester.getCenter(find.text('msg-2')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final frozen = _rowTop(tester, 0);
      expect(frozen, greaterThan(1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_rowTop(tester, 0), frozen);
      expect(
        selection.isSelectionMode,
        isFalse,
        reason: 'the catching press must not select a moving row',
      );

      await press.up();
      await tester.pumpAndSettle();
      expect(_rowTop(tester, 0), 0);
      expect(selection.isSelectionMode, isFalse);
    });

    testWidgets('hit-testing lands on the translated row', (tester) async {
      await pumpAtOldest(tester);

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      final offset = _rowTop(tester, 0);
      // Two px above row 4's painted bottom — inside row 5's layout rect.
      const contentY = 5 * _rowHeight - 2;
      final global = Offset(
        tester.getCenter(find.byType(ChatScrollView)).dx,
        _viewportTop(tester) + contentY + offset,
      );
      final targets = [
        for (final entry in tester.hitTestOnBinding(global).path) entry.target,
      ];
      expect(targets, contains(_rowBox(tester, 4)));
      expect(targets, isNot(contains(_rowBox(tester, 5))));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('short content still rubber-bands at both edges', (
      tester,
    ) async {
      await pumpAtOldest(tester, count: 5);

      var gesture = await _holdDragPast(
        tester,
        const Offset(0, 200),
        steps: 10,
      );
      expect(_rowTop(tester, 0), greaterThan(50));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_rowTop(tester, 0), 0);

      gesture = await _holdDragPast(tester, const Offset(0, -200), steps: 10);
      expect(_rowTop(tester, 0), lessThan(-50));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_rowTop(tester, 0), 0);
    });

    testWidgets('trackpad pan rubber-bands', (tester) async {
      await pumpAtOldest(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ChatScrollView)),
        kind: PointerDeviceKind.trackpad,
      );
      for (var i = 0; i < 20; i++) {
        await gesture.panZoomUpdate(
          tester.getCenter(find.byType(ChatScrollView)),
          pan: Offset(0, 20.0 * (i + 1)),
        );
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(_rowTop(tester, 0), greaterThan(50));

      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(_rowTop(tester, 0), 0);
    });

    testWidgets('trackpad pan releases a fling', (tester) async {
      const count = 200;
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      final ds = _PreloadedDataSource(count);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      final events = <ChatScrollEvent>[];
      controller.addScrollListener(events.add);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, physics: rubberBand),
      );
      await tester.pumpAndSettle();

      await tester.trackpadFling(
        find.byType(ChatScrollView),
        const Offset(0, 200),
        3000,
      );
      expect(events.whereType<ChatFlingStart>(), hasLength(1));
      await tester.pumpAndSettle();
    });

    testWidgets('mouse wheel stays clamped at the edge', (tester) async {
      await pumpAtOldest(tester);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(ChatScrollView))),
      );
      for (var i = 0; i < 5; i++) {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
        await tester.pump(const Duration(milliseconds: 16));
        expect(_rowTop(tester, 0), 0);
      }
      await tester.pumpAndSettle();
      expect(_rowTop(tester, 0), 0);
    });

    testWidgets('an unequal physics swap drops the translate', (tester) async {
      final (controller, ds) = await pumpAtOldest(tester);

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      expect(_rowTop(tester, 0), greaterThan(50));

      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          physics: const ChatScrollPhysics.stretch(),
        ),
      );
      expect(_rowTop(tester, 0), 0);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('none edge effect', () {
    const clamped = ChatScrollPhysics.clamped();

    testWidgets('a drag past the edge moves nothing', (tester) async {
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, physics: clamped),
      );
      await tester.pumpAndSettle();

      final gesture = await _holdDragPast(
        tester,
        const Offset(0, 400),
        steps: 20,
      );
      expect(_rowTop(tester, 0), 0);
      expect(_rowTop(tester, 4), 4 * _rowHeight);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a fling ends at the pin', (tester) async {
      final controller = ChatScrollController()..jumpTo(10);
      final ds = _PreloadedDataSource(40);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      final events = <ChatScrollEvent>[];
      controller.addScrollListener(events.add);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, physics: clamped),
      );
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 200),
        3000,
      );
      final peak = await _peakRowTop(tester, 0);
      expect(peak, 0);
      expect(events.whereType<ChatFlingEnd>(), hasLength(1));
    });
  });

  group('platform default', () {
    Future<void> dragAtOldest(
      WidgetTester tester,
      void Function() whileHeld,
    ) async {
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
      whileHeld();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets(
      'Android and Fuchsia default to stretch',
      (tester) => dragAtOldest(tester, () {
        expect(_rowTop(tester, 0), 0);
        expect(_rowTop(tester, 4), greaterThan(4 * _rowHeight + 1));
      }),
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.fuchsia,
      }),
    );

    testWidgets(
      'iOS and macOS default to rubber-band',
      (tester) => dragAtOldest(tester, () {
        expect(_rowTop(tester, 0), greaterThan(50));
      }),
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }),
    );

    testWidgets(
      'Windows and Linux default to clamped',
      (tester) => dragAtOldest(tester, () {
        expect(_rowTop(tester, 0), 0);
        expect(_rowTop(tester, 4), 4 * _rowHeight);
      }),
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );
  });
}
