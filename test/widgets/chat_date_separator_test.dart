import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

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

/// Messages per calendar day in the generated fixture.
const int _perDay = 8;

/// `count` messages, [_perDay] per calendar day starting 2026-01-01.
List<IChatMessage> _generate(int count) => <IChatMessage>[
  for (var i = 0; i < count; i++)
    ChatMessage$User(
      id: i,
      sender: 'User',
      createdAt: DateTime(2026, 1, 1 + i ~/ _perDay, 9, i % _perDay),
      updatedAt: DateTime(2026, 1, 1 + i ~/ _perDay, 9, i % _perDay),
      content: 'content $i',
    ),
];

ChatScrollController _boundedController(int count) => ChatScrollController()
  ..oldestKnownId = 0
  ..newestKnownId = count - 1
  ..reachedOldest = true
  ..reachedNewest = true;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  bool separators = true,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          messageBuilder: (context, id, message, status) =>
              SizedBox(height: 60, child: Text('msg-$id')),
          dateSeparatorBuilder: separators
              ? (context, date) => SizedBox(
                  height: 24,
                  child: Text('sep-${date.month}-${date.day}'),
                )
              : null,
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
  group('ChatScrollView day separators', () {
    testWidgets('inline date separators mark day boundaries', (tester) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(16);
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
      final controller = _boundedController(count)..jumpTo(count - 1);
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
      final controller = _boundedController(count)..jumpTo(8);
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

    testWidgets('the next day divider pushes the floating header up', (
      tester,
    ) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(8);
      await tester.pumpWidget(
        _harness(
          dataSource: _PreloadedDataSource(_generate(count)),
          controller: controller,
        ),
      );
      await tester.pump();
      final ro = _render(tester);

      // At rest the header sits at the top inset (0 in this harness).
      expect(ro.debugFloatingHeaderOffset, closeTo(0, 1));

      // Scroll toward newer messages until the next day's divider rises into
      // the header zone — the header is then pushed to a negative offset.
      var pushed = false;
      for (var i = 0; i < 120; i++) {
        controller.applyScrollDelta(-8);
        ro.markNeedsLayout();
        await tester.pump();
        if ((ro.debugFloatingHeaderOffset ?? 0) < -0.5) {
          pushed = true;
          break;
        }
      }
      expect(pushed, isTrue, reason: 'the rising divider should push the header');
    });

    testWidgets('several day separators can be visible at once', (
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

      // A 600px viewport spans more than one ~500px day section: inline
      // dividers for the visible boundaries plus the floating header.
      expect(find.textContaining('sep-'), findsAtLeastNWidgets(2));
    });

    testWidgets('the header date advances while scrolling across days', (
      tester,
    ) async {
      const count = 256;
      final controller = _boundedController(count)..jumpTo(8);
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
  });
}
