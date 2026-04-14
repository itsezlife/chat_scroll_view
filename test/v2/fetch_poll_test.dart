import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_message_render.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_scroll/chat_shimmer_render.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Tracking data source
// ---------------------------------------------------------------------------

class _TrackingDataSource extends ChatDataSource {
  _TrackingDataSource({required this.messageCount});

  final int messageCount;
  final DateTime _baseTime = DateTime(2026, 1, 1);

  int fetchCallCount = 0;
  final List<(int, int)> fetchedRanges = [];

  @override
  Future<List<IChatMessage>> fetch({
    int? from,
    int? to,
    DateTime? after,
  }) async {
    fetchCallCount++;
    final lo = (from ?? 0).clamp(0, messageCount - 1);
    final hi = (to ?? messageCount - 1).clamp(0, messageCount - 1);
    fetchedRanges.add((lo, hi));

    await Future<void>.delayed(const Duration(milliseconds: 50));

    return <IChatMessage>[
      for (var i = lo; i <= hi; i++)
        ChatMessage$User(
          id: i,
          createdAt: _baseTime.add(Duration(minutes: i)),
          updatedAt: _baseTime.add(Duration(minutes: i)),
          content: 'Message #$i',
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Test shimmer
// ---------------------------------------------------------------------------

class _TestShimmer extends ChatShimmerRender {
  @override
  double performLayout(double availableWidth) => 60.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFEEEEEE),
    );
  }
}

// ---------------------------------------------------------------------------
// Test message render
// ---------------------------------------------------------------------------

class _TestRender extends ChatMessageRender {
  _TestRender(IChatMessage? message) {
    if (message is IChatMessage) {
      _message = message;
      dirty = true;
    }
  }

  IChatMessage? _message;

  @override
  void update(IChatMessage? message, ChatMessageStatus status) {
    if (identical(_message, message)) return;
    _message = message;
    dirty = true;
  }

  @override
  double performLayout(double availableWidth) => _message == null ? 0.0 : 60.0;

  @override
  void paintMessage(Canvas canvas, Size size) {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildWidget({
  required _TrackingDataSource dataSource,
  required ChatScrollController controller,
  ChatShimmerRender? shimmer,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 400,
      height: 600,
      child: ChatScrollView(
        dataSource: dataSource,
        controller: controller,
        shimmer: shimmer,
        builder: _TestRender.new,
      ),
    ),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Fetch poll', () {
    testWidgets('no fetch during active scrolling', (tester) async {
      final ds = _TrackingDataSource(messageCount: 4000);
      final ctrl = ChatScrollController()
        ..oldestKnownId = 0
        ..newestKnownId = 3999
        ..reachedOldest = true
        ..reachedNewest = true;
      ctrl.jumpTo(3999);

      await tester.pumpWidget(
        _buildWidget(dataSource: ds, controller: ctrl, shimmer: _TestShimmer()),
      );
      await tester.pump();

      ds.fetchCallCount = 0;
      ds.fetchedRanges.clear();

      // Simulate drag scroll via gesture (uses ticker → marks scroll active).
      final center = tester.getCenter(find.byType(ChatScrollView));
      final gesture = await tester.startGesture(center);
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -50));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();

      // No fetch during active scrolling.
      expect(
        ds.fetchCallCount,
        0,
        reason: 'Poll timer should skip while scroll timestamp is recent',
      );
    });

    testWidgets('fetch triggers after scroll stops for 150ms', (tester) async {
      final ds = _TrackingDataSource(messageCount: 4000);
      final ctrl = ChatScrollController()
        ..oldestKnownId = 0
        ..newestKnownId = 3999
        ..reachedOldest = true
        ..reachedNewest = true;
      ctrl.jumpTo(3999);

      await tester.pumpWidget(
        _buildWidget(dataSource: ds, controller: ctrl, shimmer: _TestShimmer()),
      );
      await tester.pump();

      ds.fetchCallCount = 0;

      // Scroll once then stop.
      ctrl.applyScrollDelta(2000.0);
      tester
          .renderObject<RenderChatScrollView>(find.byType(ChatScrollView))
          .markNeedsLayout();
      await tester.pump();

      // Not enough time passed.
      await tester.pump(const Duration(milliseconds: 100));
      expect(ds.fetchCallCount, 0);

      // Wait for poll interval to fire after scroll is idle.
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        ds.fetchCallCount,
        greaterThan(0),
        reason: 'Fetch should trigger after scroll idle > 150ms',
      );
    });

    testWidgets('single range fetch, not per-chunk', (tester) async {
      final ds = _TrackingDataSource(messageCount: 4000);
      final ctrl = ChatScrollController()
        ..oldestKnownId = 0
        ..newestKnownId = 3999
        ..reachedOldest = true
        ..reachedNewest = true;
      ctrl.jumpTo(3999);

      await tester.pumpWidget(
        _buildWidget(dataSource: ds, controller: ctrl, shimmer: _TestShimmer()),
      );
      await tester.pump();

      ds.fetchCallCount = 0;

      // Wait for poll to trigger.
      await tester.pump(const Duration(milliseconds: 300));

      // Should be exactly 1 fetch call for the entire range.
      expect(
        ds.fetchCallCount,
        1,
        reason: 'Should issue one range fetch, not per-chunk',
      );

      // The range should cover multiple chunks worth of IDs.
      expect(ds.fetchedRanges, hasLength(1));
      final (from, to) = ds.fetchedRanges.first;
      expect(
        to - from,
        greaterThan(63),
        reason: 'Range should span multiple chunks',
      );
    });
  });
}
