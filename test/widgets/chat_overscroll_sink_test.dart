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
      oldestKnownId: count == 0 ? null : 0,
      newestKnownId: count == 0 ? null : count - 1,
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

/// Records what a host receiver would see; `take` decides how much of each
/// offer it accepts and `takeRelease` whether it takes the release.
class _Receiver {
  final offers = <double>[];
  final releases = <double>[];
  var starts = 0;
  double Function(double pixels) take = (pixels) => pixels;
  bool takeRelease = true;

  double get offeredTotal => offers.fold(0, (a, b) => a + b);

  ChatOverscrollSink sink({
    ChatOverscrollEdges edges = ChatOverscrollEdges.oldest,
  }) => ChatOverscrollSink(
    edges: edges,
    onStart: () => starts++,
    onDelta: (pixels) {
      offers.add(pixels);
      return take(pixels);
    },
    onEnd: (velocity) {
      releases.add(velocity);
      return takeRelease;
    },
  );
}

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ChatOverscrollSink? sink,
  WidgetBuilder? emptyBuilder,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          overscrollSink: sink,
          emptyBuilder: emptyBuilder,
          physics: const ChatScrollPhysics.stretch(),
          messageBuilder: (context, id, message, status, runLayout) =>
              ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: SizedBox(height: 60, child: Text('msg-$id')),
              ),
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

double _rowTop(WidgetTester tester, int id) =>
    tester.getTopLeft(find.text('msg-$id')).dy -
    tester.getTopLeft(find.byType(ChatScrollView)).dy;

Future<void> _pump(
  WidgetTester tester, {
  required int count,
  required int jumpTo,
  ChatOverscrollSink? sink,
  WidgetBuilder? emptyBuilder,
}) async {
  final controller = ChatScrollController()..jumpTo(jumpTo);
  final ds = _PreloadedDataSource(count);
  addTearDown(controller.dispose);
  addTearDown(ds.dispose);
  await tester.pumpWidget(
    _scaffold(
      dataSource: ds,
      controller: controller,
      sink: sink,
      emptyBuilder: emptyBuilder,
    ),
  );
  await tester.pumpAndSettle();
}

Future<TestGesture> _drag(WidgetTester tester, List<double> steps) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ChatScrollView)),
  );
  for (final dy in steps) {
    await gesture.moveBy(Offset(0, dy));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void main() {
  group('overscroll sink', () {
    testWidgets('no sink: the edge effect takes the pull', (tester) async {
      await _pump(tester, count: 20, jumpTo: 0);
      final gesture = await _drag(tester, List.filled(20, 20));
      expect(_render(tester).debugStretchOverscroll, greaterThan(0.01));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('at the oldest edge the pull goes to the sink, no stretch', (
      tester,
    ) async {
      final receiver = _Receiver();
      await _pump(tester, count: 20, jumpTo: 0, sink: receiver.sink());
      final gesture = await _drag(tester, List.filled(20, 20));
      expect(receiver.starts, 1);
      expect(receiver.offeredTotal, greaterThan(300));
      expect(receiver.offers.every((o) => o > 0), isTrue);
      expect(_render(tester).debugStretchOverscroll, 0);
      expect(_rowTop(tester, 0), closeTo(0, 0.01), reason: 'content stays');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('nothing is offered while content can still scroll', (
      tester,
    ) async {
      final receiver = _Receiver();
      await _pump(tester, count: 40, jumpTo: 20, sink: receiver.sink());
      final before = _rowTop(tester, 20);
      final gesture = await _drag(tester, List.filled(5, 20));
      expect(receiver.offers, isEmpty);
      expect(_rowTop(tester, 20), greaterThan(before + 50));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(receiver.releases, isEmpty, reason: 'sink never engaged');
    });

    testWidgets('a drag crossing the edge offers only the unconsumed part', (
      tester,
    ) async {
      // A sheet that is fully open takes only downward pixels.
      final receiver = _Receiver()..take = (p) => p > 0 ? p : 0;
      await _pump(tester, count: 40, jumpTo: 0, sink: receiver.sink());
      // Scroll away from the oldest pin first, then drag back past it.
      var gesture = await _drag(tester, List.filled(10, -20));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        receiver.offers.where((o) => o > 0),
        isEmpty,
        reason: 'moving away from the edge',
      );
      final travel = -_rowTop(tester, 0);
      expect(travel, greaterThan(100));

      gesture = await _drag(tester, List.filled(40, 20));
      // The drag covered at most 800 px, minus the touch slop; the content
      // consumed `travel`, the rest went to the sink.
      expect(receiver.offeredTotal, greaterThan(0));
      expect(receiver.offeredTotal, lessThan(800 - travel));
      expect(_rowTop(tester, 0), closeTo(0, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a declined offer falls back to the edge effect', (
      tester,
    ) async {
      final receiver = _Receiver()..take = (_) => 0;
      await _pump(tester, count: 20, jumpTo: 0, sink: receiver.sink());
      final gesture = await _drag(tester, List.filled(20, 20));
      expect(receiver.offers, isNotEmpty);
      expect(_render(tester).debugStretchOverscroll, greaterThan(0.01));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('an over-reporting sink is clamped to the offer', (
      tester,
    ) async {
      final receiver = _Receiver()..take = (pixels) => pixels * 3;
      await _pump(tester, count: 20, jumpTo: 0, sink: receiver.sink());
      final gesture = await _drag(tester, List.filled(20, 20));
      expect(_render(tester).debugStretchOverscroll, 0);
      expect(_rowTop(tester, 0), closeTo(0, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the newest edge does not hand over by default', (
      tester,
    ) async {
      final receiver = _Receiver();
      await _pump(tester, count: 20, jumpTo: 19, sink: receiver.sink());
      final gesture = await _drag(tester, List.filled(20, -20));
      expect(receiver.offers, isEmpty);
      expect(_render(tester).debugStretchOverscroll.abs(), greaterThan(0.01));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('edges: newest hands the bottom edge over', (tester) async {
      final receiver = _Receiver();
      await _pump(
        tester,
        count: 20,
        jumpTo: 19,
        sink: receiver.sink(edges: ChatOverscrollEdges.newest),
      );
      final gesture = await _drag(tester, List.filled(20, -20));
      expect(receiver.offeredTotal, lessThan(-300));
      expect(_render(tester).debugStretchOverscroll, 0);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('at the edge a reverse drag is offered before content', (
      tester,
    ) async {
      final receiver = _Receiver();
      await _pump(tester, count: 20, jumpTo: 0, sink: receiver.sink());
      final gesture = await _drag(tester, [...List.filled(10, 20)]);
      // The receiver has been displaced; dragging back up must reach it
      // before the list moves.
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(receiver.offers.last, lessThan(0));
      expect(_rowTop(tester, 0), closeTo(0, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a reverse drag the sink declines scrolls the content', (
      tester,
    ) async {
      final receiver = _Receiver()..take = (p) => p > 0 ? p : 0;
      await _pump(tester, count: 20, jumpTo: 0, sink: receiver.sink());
      final gesture = await _drag(tester, [...List.filled(5, 20)]);
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_rowTop(tester, 0), lessThan(-20));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the release velocity goes to the sink; no content fling', (
      tester,
    ) async {
      final receiver = _Receiver();
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      final events = <ChatScrollEvent>[];
      controller.addScrollListener(events.add);
      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          sink: receiver.sink(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 300),
        2000,
      );
      await tester.pumpAndSettle();
      expect(receiver.releases, hasLength(1));
      expect(receiver.releases.single, greaterThan(1000));
      expect(events.whereType<ChatFlingStart>(), isEmpty);
      expect(_render(tester).debugStretchOverscroll, 0);
    });

    testWidgets('a declined release lets the content fling', (tester) async {
      final receiver = _Receiver()
        ..takeRelease = false
        ..take = (p) => p > 0 ? p : 0;
      final controller = ChatScrollController()..jumpTo(0);
      final ds = _PreloadedDataSource(60);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      final events = <ChatScrollEvent>[];
      controller.addScrollListener(events.add);
      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          sink: receiver.sink(),
        ),
      );
      await tester.pumpAndSettle();

      // A downward drag at the edge engages the sink, then the finger turns
      // and flicks up: the sink declines the release, the content flings.
      final gesture = await _drag(tester, [...List.filled(5, 20)]);
      var stamp = const Duration(milliseconds: 200);
      for (var i = 0; i < 6; i++) {
        stamp += const Duration(milliseconds: 8);
        await gesture.moveBy(const Offset(0, -40), timeStamp: stamp);
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pump();
      expect(receiver.releases, hasLength(1));
      expect(events.whereType<ChatFlingStart>(), hasLength(1));
      await tester.pumpAndSettle();
    });

    testWidgets('an empty chat forwards drags to the sink', (tester) async {
      final receiver = _Receiver();
      await _pump(
        tester,
        count: 0,
        jumpTo: 0,
        sink: receiver.sink(),
        emptyBuilder: (context) => const Center(child: Text('empty-chat')),
      );
      expect(find.text('empty-chat'), findsOneWidget);
      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 300),
        2000,
      );
      await tester.pumpAndSettle();
      expect(receiver.starts, 1);
      expect(receiver.offeredTotal, greaterThan(200));
      expect(receiver.releases, hasLength(1));
    });

    testWidgets('an empty chat without a sink forwards nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        count: 0,
        jumpTo: 0,
        emptyBuilder: (context) => const Center(child: Text('empty-chat')),
      );
      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 300),
        2000,
      );
      await tester.pumpAndSettle();
      expect(find.text('empty-chat'), findsOneWidget);
    });
  });
}
