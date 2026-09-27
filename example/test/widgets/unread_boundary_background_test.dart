import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/unread_boundary_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _selfSender = 'Me';

IChatMessage _msg(int i, {bool self = false}) => UserChatMessage(
  id: i,
  sender: self ? _selfSender : 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

bool _isSelf(IChatMessage message) => message.sender == _selfSender;

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(this.count, {Set<int> omitIds = const {}}) {
    for (var i = 0; i < count; i++) {
      if (!omitIds.contains(i)) upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  _PreloadedDataSource.empty() : count = 0 {
    seedBoundaries(reachedOldest: true, reachedNewest: true);
  }

  final int count;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

const _rowHeight = 60.0;
const _separatorHeight = 32.0;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required UnreadBoundaryController unreadBoundary,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          reverse: true,
          dataSource: dataSource,
          controller: controller,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: _rowHeight,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
          unreadBoundary: unreadBoundary,
          unreadSeparatorBuilder: (context) =>
              const SizedBox(height: _separatorHeight, child: Text('unread')),
        ),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

// ---------------------------------------------------------------------------
// App lifecycle
// ---------------------------------------------------------------------------

/// Sends the app to the background through the intermediate states
/// [AppLifecycleListener] requires. The test is brought back to the
/// foreground at teardown if it does not do so itself, so the binding's
/// lifecycle never leaks into the next test.
void _background() {
  final binding = TestWidgetsFlutterBinding.instance;
  const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ].forEach(binding.handleAppLifecycleStateChanged);
  addTearDown(() {
    if (binding.lifecycleState != AppLifecycleState.resumed) _foreground();
  });
}

void _foreground() {
  const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ].forEach(TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const count = 151;
  const boundaryId = 51;

  /// Opens at [boundaryId] with the separator at the band top, off the
  /// tail, like an open at the first unread message.
  Future<
    ({
      _PreloadedDataSource ds,
      ChatScrollController controller,
      UnreadBoundaryController boundary,
    })
  >
  open(WidgetTester tester, {Set<int> omitIds = const {}}) async {
    final ds = _PreloadedDataSource(count, omitIds: omitIds);
    final controller = ChatScrollController()..jumpTo(boundaryId);
    final boundary = UnreadBoundaryController(
      dataSource: ds,
      controller: controller,
      isSelfMessage: _isSelf,
      boundary: boundaryId,
    );
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);
    addTearDown(boundary.dispose);

    await tester.pumpWidget(
      _harness(
        dataSource: ds,
        controller: controller,
        unreadBoundary: boundary,
      ),
    );
    await _settle(tester);
    expect(find.text('unread'), findsOneWidget);
    expect(controller.isAtTail.value, isFalse);
    return (ds: ds, controller: controller, boundary: boundary);
  }

  Future<void> goToTail(
    WidgetTester tester,
    ChatScrollController controller,
  ) async {
    controller.jumpTo(count - 1);
    await _settle(tester);
    expect(controller.isAtTail.value, isTrue);
  }

  group('background arrivals', () {
    testWidgets('the first incoming arrival while backgrounded moves the '
        'boundary; later arrivals in the same pause leave it', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);

      _background();
      ds.insertMessage(_msg(count));
      expect(boundary.value, count);

      ds
        ..insertMessage(_msg(count + 1))
        ..insertMessages([_msg(count + 2), _msg(count + 3)]);
      expect(boundary.value, count);
    });

    testWidgets('an own arrival while backgrounded still clears the '
        'boundary; the next incoming arrival places it again', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);

      _background();
      ds.insertMessage(_msg(count));
      expect(boundary.value, count);

      ds.insertMessage(_msg(count + 1, self: true));
      expect(boundary.value, isNull);

      ds.insertMessage(_msg(count + 2));
      expect(boundary.value, count + 2);
    });

    testWidgets('arrivals while backgrounded with the tail not loaded '
        'leave the boundary', (tester) async {
      final (:ds, :controller, :boundary) = await open(
        tester,
        omitIds: {count - 1},
      );
      expect(ds.getMessage(count - 1), isNull);

      _background();
      ds.insertMessage(_msg(count));
      ds.seedBoundaries(newestKnownId: count + 1);

      expect(boundary.value, boundaryId);
    });

    testWidgets('an incoming arrival in the foreground leaves the boundary; '
        'a pause that ended places nothing', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);

      _background();
      _foreground();
      ds.insertMessage(_msg(count));

      expect(boundary.value, boundaryId);
    });
  });

  group('resume', () {
    testWidgets('after a pause that moved the boundary, a reader who was at '
        'the tail lands on it with the separator at the band top', (
      tester,
    ) async {
      final (:ds, :controller, :boundary) = await open(tester);
      await goToTail(tester, controller);

      _background();
      ds.insertMessages([for (var i = count; i < count + 15; i++) _msg(i)]);
      expect(boundary.value, count);

      _foreground();
      await _settle(tester);

      final bandTop = tester.getTopLeft(find.byType(ChatScrollView)).dy;
      expect(tester.getTopLeft(find.text('unread')).dy, bandTop);
      expect(
        tester.getTopLeft(find.text('msg-$count')).dy,
        bandTop + _separatorHeight,
      );
      expect(controller.isAtTail.value, isFalse);
    });

    testWidgets('after a pause that moved the boundary, a reader who was '
        'scrolled up keeps the position', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);
      final jumps = <int>[];
      controller.addJumpListener(jumps.add);

      _background();
      ds.insertMessage(_msg(count));
      _foreground();
      await _settle(tester);

      expect(boundary.value, count);
      expect(jumps, isEmpty);
      expect(controller.isAtTail.value, isFalse);
      expect(find.text('unread'), findsNothing);
      final bandTop = tester.getTopLeft(find.byType(ChatScrollView)).dy;
      expect(
        tester.getTopLeft(find.text('msg-$boundaryId')).dy,
        bandTop,
        reason:
            'the row the reader opened at keeps its alignment as the '
            'separator leaves it',
      );
    });

    testWidgets('after a pause that moved nothing, a reader at the tail '
        'stays at the tail', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);
      await goToTail(tester, controller);
      final jumps = <int>[];
      controller.addJumpListener(jumps.add);

      _background();
      _foreground();
      await _settle(tester);

      expect(jumps, isEmpty);
      expect(controller.isAtTail.value, isTrue);
      expect(boundary.value, boundaryId);
    });

    testWidgets('a boundary the pause placed and an own arrival cleared '
        'is not jumped to', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);
      await goToTail(tester, controller);
      final jumps = <int>[];
      controller.addJumpListener(jumps.add);

      _background();
      ds
        ..insertMessage(_msg(count))
        ..insertMessage(_msg(count + 1, self: true));
      _foreground();
      await _settle(tester);

      expect(boundary.value, isNull);
      expect(jumps, isEmpty);
    });

    testWidgets('after dispose, backgrounding and resuming neither moves the '
        'boundary nor jumps', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);
      await goToTail(tester, controller);
      final jumps = <int>[];
      controller.addJumpListener(jumps.add);
      boundary.dispose();

      _background();
      ds.insertMessages([for (var i = count; i < count + 15; i++) _msg(i)]);
      _foreground();
      await _settle(tester);

      expect(boundary.value, boundaryId);
      expect(jumps, isEmpty);
    });
  });

  group('reconnect gap', () {
    testWidgets('makes the boundary pending at the first incoming message '
        'after the newest id known before the drop; the separator appears '
        'when that row loads', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);
      const missed = 20;

      ds.seedBoundaries(newestKnownId: count + missed - 1);
      boundary.markReconnectGap(newestBeforeDrop: count - 1, readMark: 40);
      expect(boundary.value, isNull, reason: 'pending until the rows load');

      ds.upsertMessages([
        _msg(count, self: true),
        for (var i = count + 1; i < count + missed; i++) _msg(i),
      ]);
      expect(boundary.value, count + 1, reason: 'own messages are skipped');

      controller.jumpTo(count + 1);
      await _settle(tester);
      final bandTop = tester.getTopLeft(find.byType(ChatScrollView)).dy;
      expect(tester.getTopLeft(find.text('unread')).dy, bandTop);
    });

    testWidgets('starts at the read mark when it is later than the newest '
        'id known before the drop', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);

      ds.insertMessages([for (var i = count; i < count + 10; i++) _msg(i)]);
      boundary.markReconnectGap(
        newestBeforeDrop: count - 1,
        readMark: count + 4,
      );

      expect(boundary.value, count + 4);
    });

    testWidgets('from a chat that was empty, without a read mark, resolves at '
        "the chat's first incoming message once its oldest is reached", (
      tester,
    ) async {
      final ds = _PreloadedDataSource.empty();
      final controller = ChatScrollController();
      final boundary = UnreadBoundaryController(
        dataSource: ds,
        controller: controller,
        isSelfMessage: _isSelf,
      );
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(boundary.dispose);
      const first = 1000;
      const newest = 1005;

      ds.seedBoundaries(newestKnownId: newest, reachedOldest: false);
      boundary.markReconnectGap(newestBeforeDrop: null);
      expect(boundary.value, isNull, reason: 'pending until the rows load');

      ds
        ..seedBoundaries(oldestKnownId: first, reachedOldest: true)
        ..upsertMessages([
          _msg(first, self: true),
          for (var i = first + 1; i <= newest; i++) _msg(i),
        ]);

      expect(boundary.value, first + 1);
    });

    testWidgets('without a read mark starts right after the newest id known '
        'before the drop', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);

      ds.insertMessages([for (var i = count; i < count + 3; i++) _msg(i)]);
      boundary.markReconnectGap(newestBeforeDrop: count - 1);

      expect(boundary.value, count);
    });

    testWidgets('is silent after dispose', (tester) async {
      final (:ds, :controller, :boundary) = await open(tester);
      ds.insertMessage(_msg(count));
      boundary
        ..dispose()
        ..markReconnectGap(newestBeforeDrop: count - 1);

      expect(boundary.value, boundaryId);
    });
  });
}
