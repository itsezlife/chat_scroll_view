import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

const _count = 256;

class _LoadedSource extends ChatDataSource {
  _LoadedSource() {
    upsertMessages([
      for (var i = 0; i < _count; i++)
        UserChatMessage(
          id: i,
          sender: 'User',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'content $i',
        ),
    ]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: _count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Widget _harness(ChatScrollController controller, {double? platformSlop}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            gestureSettings: DeviceGestureSettings(touchSlop: platformSlop),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: _LoadedSource(),
                  controller: controller,
                  // A tappable row, as in a chat: the drag has a rival in
                  // the arena, so it must win on travel.
                  messageBuilder: (context, id, message, status, runLayout) =>
                      GestureDetector(
                        onTap: () {},
                        child: SizedBox(height: 60, child: Text('msg-$id')),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// The top of the first message laid out on screen, and its finder.
(Finder, double) _probe(WidgetTester tester) {
  final view = tester.getRect(find.byType(ChatScrollView));
  for (final element in find.textContaining('msg-').evaluate()) {
    final text = (element.widget as Text).data!;
    final finder = find.text(text);
    final top = tester.getTopLeft(finder).dy;
    if (top > view.top + 60 && top < view.bottom - 120) return (finder, top);
  }
  throw StateError('no message on screen');
}

/// How far the probed message moves when a pressed finger travels [travel]
/// and then 4 px more.
Future<double> _moveAfterPress(
  WidgetTester tester, {
  required double travel,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(ChatScrollView)),
  );
  await tester.pump();
  final (finder, before) = _probe(tester);
  await gesture.moveBy(Offset(0, travel));
  await tester.pump();
  await gesture.moveBy(const Offset(0, 4));
  await tester.pump();
  final after = tester.getTopLeft(finder).dy;
  await gesture.up();
  await tester.pumpAndSettle();
  return after - before;
}

void main() {
  group('ChatScrollView drag slop', () {
    testWidgets('a press at rest waits for the touch slop', (tester) async {
      final controller = ChatScrollController()..jumpTo(_count - 1);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      expect(await _moveAfterPress(tester, travel: kTouchSlop / 2), 0);
    });

    testWidgets('a press that catches a fling drags from the first pixel', (
      tester,
    ) async {
      final controller = ChatScrollController()..jumpTo(_count - 1);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller));
      await tester.pump();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 400),
        3000,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        await _moveAfterPress(tester, travel: kTouchSlop / 2),
        moreOrLessEquals(kTouchSlop / 2 + 4, epsilon: 0.5),
      );
    });

    testWidgets("the platform's touch slop replaces the default", (
      tester,
    ) async {
      const platformSlop = 8.0;
      final controller = ChatScrollController()..jumpTo(_count - 1);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller, platformSlop: platformSlop));
      await tester.pumpAndSettle();

      // Past the platform's slop, short of the framework default.
      expect(await _moveAfterPress(tester, travel: platformSlop + 4), isNot(0));
    });
  });
}
