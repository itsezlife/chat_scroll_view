import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_day_header_delegate.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_activity.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../chat_message.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    if (messages.isNotEmpty) {
      seedBoundaries(
        oldestKnownId: 0,
        newestKnownId: messages.length - 1,
        reachedOldest: true,
        reachedNewest: true,
      );
    }
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// Messages per calendar day in the generated fixture.
const int _perDay = 8;

/// `count` messages, [_perDay] per calendar day starting 2026-01-01.
List<IChatMessage> _generate(int count) => <IChatMessage>[
  for (var i = 0; i < count; i++)
    UserChatMessage(
      id: i,
      sender: 'User',
      createdAt: DateTime(2026, 1, 1 + i ~/ _perDay, 9, i % _perDay),
      updatedAt: DateTime(2026, 1, 1 + i ~/ _perDay, 9, i % _perDay),
      content: 'content $i',
    ),
];

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  bool separators = true,
  bool reverse = false,
  ChatDayHeaderDelegate dayHeaderDelegate = const ChatFadingDayHeader(),
  ChatScrollActivityTiming? scrollActivityTiming,
  void Function(DateTime date)? onSeparatorTap,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          reverse: reverse,
          dayHeaderDelegate: dayHeaderDelegate,
          scrollActivityTiming: scrollActivityTiming,
          messageBuilder: (context, id, message, status, runLayout) =>
              SizedBox(height: 60, child: Text('msg-$id')),
          dateSeparatorBuilder: separators
              ? (context, bucket, date) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSeparatorTap == null
                      ? null
                      : () => onSeparatorTap(date),
                  child: SizedBox(
                    height: 24,
                    child: Text('sep-${date.month}-${date.day}'),
                  ),
                )
              : null,
        ),
      ),
    ),
  ),
);

/// Shift content by [dy] (positive moves rows down) and relayout.
Future<void> _shift(
  WidgetTester tester,
  ChatScrollController controller,
  double dy,
) async {
  controller.applyScrollDelta(dy);
  _render(tester).markNeedsLayout();
  await tester.pump();
}

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChatScrollView day separators', () {
    testWidgets('inline date separators mark day boundaries', (tester) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(16);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();

      // jumpTo(16): msg-16 starts day 3 (2026-01-03); msg-24 starts day 4.
      expect(find.text('msg-16'), findsOneWidget);
      expect(find.text('sep-1-3'), findsWidgets);
      expect(find.text('sep-1-4'), findsWidgets);
    });

    testWidgets('no separators and no header when the builder is null', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          separators: false,
        ),
      );
      await tester.pump();

      expect(find.textContaining('sep-'), findsNothing);
      expect(_render(tester).debugHasFloatingHeader, isFalse);
    });

    testWidgets('a floating header is present and tracks the topmost day', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(8);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();
      final ro = _render(tester);

      expect(ro.debugHasFloatingHeader, isTrue);
      // jumpTo(8): msg-8 is the first message of day 2 (2026-01-02).
      expect(ro.debugHeaderDate, isNotNull);
      expect(ro.debugHeaderDate!.month, 1);
      expect(ro.debugHeaderDate!.day, 2);

      // Teleport deep into another day — the header follows.
      controller.jumpTo(80); // 80 ~/ 8 == 10 -> 2026-01-11
      await tester.pump();
      expect(ro.debugHeaderDate!.day, 11);
    });

    testWidgets('short content hides the floating header in reverse mode', (
      tester,
    ) async {
      const count = 3;
      final controller = ChatScrollController()..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
          reverse: true,
        ),
      );
      await tester.pump();
      expect(_render(tester).debugHasFloatingHeader, isFalse);
    });

    testWidgets('top overscroll keeps floating header viewport-fixed', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(0);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();
      final ro = _render(tester);
      expect(ro.debugFloatingHeaderVisible, isTrue);
      final headerY = ro.debugFloatingHeaderOffset;

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ChatScrollView)),
      );
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(
        ro.debugStretchOverscroll,
        greaterThan(0.01),
        reason: 'pull past oldest paints stretch',
      );
      expect(
        ro.debugFloatingHeaderVisible,
        isTrue,
        reason: 'header stays painted outside the stretch transform',
      );
      expect(ro.debugFloatingHeaderOffset, closeTo(headerY!, 0.5));
      await gesture.up();
    });

    testWidgets('the inline date separator fades out as it nears the top', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(8);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();
      final ro = _render(tester);

      // jumpTo(8): msg-8 (first of day 2) sits at the very top, inside the
      // floating header's zone — its inline separator is faded out.
      expect(ro.debugDividerOpacity(8), isNotNull);
      expect(ro.debugDividerOpacity(8), lessThan(0.5));

      // msg-16 (first of day 3) is far below — its separator is fully opaque.
      expect(ro.debugDividerOpacity(16), closeTo(1.0, 0.01));

      // The floating header stays pinned — it is never pushed.
      expect(ro.debugFloatingHeaderOffset, closeTo(0, 1));

      // Scroll msg-16's separator up into the fade band near the top edge:
      // it is then partially transparent.
      controller.applyScrollDelta(-490);
      ro.markNeedsLayout();
      await tester.pump();
      final fading = ro.debugDividerOpacity(16);
      expect(fading, isNotNull);
      expect(fading, greaterThan(0.1));
      expect(fading, lessThan(0.9));
    });

    testWidgets('several day separators can be visible at once', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(count - 1);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();

      // A 600px viewport spans more than one ~500px day section: inline
      // dividers for the visible boundaries plus the floating header.
      expect(find.textContaining('sep-'), findsAtLeastNWidgets(2));
    });

    testWidgets('the header date advances while scrolling across days', (
      tester,
    ) async {
      const count = 256;
      final controller = ChatScrollController()..jumpTo(8);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();
      final ro = _render(tester);
      expect(ro.debugHeaderDate!.day, 2);

      // A long scroll toward newer messages crosses many day boundaries.
      for (var i = 0; i < 100; i++) {
        controller.applyScrollDelta(-60);
        ro.markNeedsLayout();
        await tester.pump();
      }
      expect(
        ro.debugHeaderDate!.isAfter(DateTime(2026, 1, 2, 23, 59)),
        isTrue,
        reason: 'the header should follow the topmost message into later days',
      );
    });

    testWidgets('custom groupBy bucket reaches separator builder', (
      tester,
    ) async {
      const count = 24;
      final messages = <IChatMessage>[
        for (var i = 0; i < count; i++)
          UserChatMessage(
            id: i,
            sender: 'User',
            createdAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
            updatedAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
            content: 'content $i',
          ),
      ];
      final controller = ChatScrollController()..jumpTo(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: _PreloadedDataSource(messages),
                  controller: controller,
                  groupBy: (message) =>
                      message.id < 12 ? 'morning' : 'afternoon',
                  messageBuilder: (context, id, message, status, runLayout) =>
                      SizedBox(height: 60, child: Text('msg-$id')),
                  dateSeparatorBuilder: (context, bucket, date) =>
                      SizedBox(height: 24, child: Text('grp-$bucket')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('grp-morning'), findsWidgets);
      expect(find.text('grp-afternoon'), findsWidgets);
      final ro = _render(tester);
      expect(ro.debugHeaderBucket, 'morning');
    });

    testWidgets('tap inside the floating header reaches its builder', (
      tester,
    ) async {
      // Regression: the floating header paints on top of messages but used to
      // be excluded from hit-testing — any tap target inside the header
      // builder (jump-to-date pill, dismiss button) was dead and the tap
      // fell through to the message underneath.
      const count = 256;
      // jumpTo(50) so the floating header pins at y=0..24 over msg-50, and
      // every visible inline separator sits well below the header zone.
      final controller = ChatScrollController()..jumpTo(50);
      var headerTaps = 0;
      var messageTaps = 0;

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
                  messageBuilder: (context, id, message, status, runLayout) =>
                      SizedBox(
                        height: 60,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => messageTaps++,
                          child: Text('msg-$id'),
                        ),
                      ),
                  dateSeparatorBuilder: (context, bucket, date) => SizedBox(
                    height: 24,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => headerTaps++,
                      child: Text('hdr-${date.month}-${date.day}'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The floating header sits at y=0..24, x=200..600 (Center inside an
      // 800x600 test surface). Tap inside that zone — msg-50 paints under
      // the header at the same position; the header must intercept.
      await tester.tapAt(const Offset(400, 12));
      await tester.pump();
      expect(headerTaps, 1, reason: 'floating header should receive the tap');
      expect(
        messageTaps,
        0,
        reason: 'message under the header must not receive the tap',
      );

      // Sanity: a tap well below the header zone reaches the underlying
      // message, proving messageTaps is wired and the header is not
      // swallowing all taps.
      await tester.tapAt(const Offset(400, 100));
      await tester.pump();
      expect(messageTaps, 1);
      expect(headerTaps, 1, reason: 'no double-count');
    });
  });

  // Geometry: rows are 60 tall, a day-starting row adds a 24 px separator,
  // the header is 24 tall and rests at y = 0. jumpTo(8) puts msg-8 (first of
  // day 2) at the top.
  group('ChatPushingDayHeader', () {
    Future<RenderChatScrollView> pump(
      WidgetTester tester,
      ChatScrollController controller, {
      ChatScrollActivityTiming? scrollActivityTiming,
      void Function(DateTime date)? onSeparatorTap,
    }) async {
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(256)),
          controller: controller,
          dayHeaderDelegate: const ChatPushingDayHeader(),
          scrollActivityTiming: scrollActivityTiming,
          onSeparatorTap: onSeparatorTap,
        ),
      );
      await tester.pump();
      return _render(tester);
    }

    testWidgets('the header stands in for a separator at the rest line', (
      tester,
    ) async {
      final controller = ChatScrollController()..jumpTo(8);
      final ro = await pump(tester, controller);

      expect(ro.debugHeaderDate, DateTime(2026, 1, 2, 9));
      expect(ro.debugFloatingHeaderOffset, 0);
      expect(ro.debugDividerOpacity(8), 0, reason: 'inline hides under it');
      expect(ro.debugDividerOpacity(16), 1);
    });

    testWidgets('the next separator pushes the header up as it rises', (
      tester,
    ) async {
      final controller = ChatScrollController()..jumpTo(8);
      final ro = await pump(tester, controller);

      // msg-8's separator at y = 10: the header (day 1 now) is pushed so its
      // bottom touches the separator's top.
      await _shift(tester, controller, 10);
      expect(ro.debugHeaderDate?.day, 1);
      expect(ro.debugFloatingHeaderOffset, closeTo(-14, 0.01));
      expect(ro.debugDividerOpacity(8), 1);

      // A full extent below the rest line: the header rests again.
      await _shift(tester, controller, 20);
      expect(ro.debugFloatingHeaderOffset, 0);
    });

    testWidgets('without an activity clock the header never hides', (
      tester,
    ) async {
      final controller = ChatScrollController()..jumpTo(8);
      final ro = await pump(tester, controller);
      await _shift(tester, controller, 10);

      await tester.pump(const Duration(seconds: 5));
      expect(ro.debugScrollActivity, 1);
      expect(ro.debugFloatingHeaderOpacity, 1);
    });

    testWidgets('with an activity clock the header hides once idle and '
        'returns on drag', (tester) async {
      final taps = <int>[];
      final controller = ChatScrollController()..jumpTo(8);
      final ro = await pump(
        tester,
        controller,
        scrollActivityTiming: const ChatScrollActivityTiming(),
        onSeparatorTap: (date) => taps.add(date.day),
      );
      await _shift(tester, controller, 10);

      // Opening the list counts as navigation: shown, then hidden after
      // 1000 ms + a 150 ms fade.
      await tester.pump(const Duration(milliseconds: 150));
      expect(ro.debugFloatingHeaderOpacity, 1);
      await tester.tapAt(const Offset(400, 5));
      expect(taps, <int>[1], reason: 'a visible header takes the tap');

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 150));
      expect(ro.debugScrollActivity, 0);
      expect(ro.debugFloatingHeaderOpacity, 0);
      expect(
        find.text('sep-1-1'),
        findsOneWidget,
        reason: 'the header stays built while hidden',
      );
      expect(
        tester.layers.whereType<OpacityLayer>().where((l) => l.alpha! < 255),
        isEmpty,
        reason: 'a hidden header is skipped, not painted at alpha 0',
      );
      await tester.tapAt(const Offset(400, 5));
      expect(taps, <int>[1], reason: 'a hidden header takes no input');

      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(ro.debugScrollActivity, 1);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(ro.debugScrollActivity, 1, reason: '500 ms user idle delay');
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(ro.debugScrollActivity, 0);
    });

    testWidgets('an idle header stays while it stands in for a separator', (
      tester,
    ) async {
      final controller = ChatScrollController()..jumpTo(8);
      final ro = await pump(
        tester,
        controller,
        scrollActivityTiming: const ChatScrollActivityTiming(),
      );

      await tester.pump(const Duration(seconds: 2));
      expect(ro.debugScrollActivity, 1, reason: 'pinned while standing in');
      expect(ro.debugFloatingHeaderOpacity, 1);
      expect(ro.debugDividerOpacity(8), 0);
    });

    testWidgets('scrolling away from a standing-in header does not blink', (
      tester,
    ) async {
      final controller = ChatScrollController()..jumpTo(8);
      final ro = await pump(
        tester,
        controller,
        scrollActivityTiming: const ChatScrollActivityTiming(),
      );
      await tester.pump(const Duration(seconds: 2));

      await _shift(tester, controller, 10);
      expect(ro.debugFloatingHeaderOffset, closeTo(-14, 0.01));
      expect(ro.debugFloatingHeaderOpacity, 1);
      await tester.pump(const Duration(milliseconds: 16));
      expect(ro.debugFloatingHeaderOpacity, 1);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 150));
      expect(ro.debugFloatingHeaderOpacity, 0, reason: 'then idles out');
    });

    // The pushing policy relies on this: the oldest row rests at the rest
    // line, so the oldest separator never pushes a header showing its own
    // day.
    testWidgets('at the oldest message the header stands in for its '
        'separator', (tester) async {
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(9)),
          controller: ChatScrollController(),
          dayHeaderDelegate: const ChatPushingDayHeader(),
        ),
      );
      await tester.pump();
      final ro = _render(tester);

      expect(ro.debugHeaderDate?.day, 1);
      expect(ro.debugFloatingHeaderOffset, 0);
      expect(ro.debugFloatingHeaderOpacity, 1);
      expect(ro.debugDividerOpacity(0), 0);
    });
  });
}
