import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_events.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

const _count = 256;
const _frame = Duration(microseconds: 8333);

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

void main() {
  testWidgets('the frame after a fling release moves on', (tester) async {
    final controller = ChatScrollController()..jumpTo(_count - 1);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: ChatScrollView(
              dataSource: _LoadedSource(),
              controller: controller,
              messageBuilder: (context, id, message, status, runLayout) =>
                  SizedBox(height: 60, child: Text('msg-$id')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The list's travel on each frame.
    final steps = <double>[];
    var frameTravel = 0.0;
    void onScroll(ChatScrollEvent event) {
      if (event case ChatViewportScrolled(:final delta)) frameTravel += delta;
    }

    controller.addScrollListener(onScroll);
    addTearDown(() => controller.removeScrollListener(onScroll));
    Future<void> frame() async {
      frameTravel = 0;
      await tester.pump(_frame);
      steps.add(frameTravel);
    }

    // A finger at 20 px a frame (2400 px/s), one move per frame, as the
    // platform delivers them; then the release between two frames.
    var time = Duration.zero;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChatScrollView)),
    );
    for (var i = 0; i < 12; i++) {
      time += _frame;
      await gesture.moveBy(const Offset(0, 20), timeStamp: time);
      await frame();
    }
    await gesture.up(timeStamp: time + _frame);
    final released = steps.length;
    for (var i = 0; i < 3; i++) {
      await frame();
    }

    // Before: the release frame stood still, and the next one jumped.
    expect(steps[released - 1], moreOrLessEquals(20, epsilon: 0.01));
    expect(steps[released], moreOrLessEquals(20, epsilon: 4));
    expect(steps[released + 1], moreOrLessEquals(20, epsilon: 4));
    await tester.pumpAndSettle();
  });
}
