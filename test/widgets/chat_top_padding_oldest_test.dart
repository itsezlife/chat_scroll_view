import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

class _Source extends ChatDataSource {
  _Source(int count) {
    upsertMessages(<IChatMessage>[
      for (var i = 0; i < count; i++)
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
      newestKnownId: count - 1,
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
  testWidgets(
    'tall reverse chat scrolled to the oldest end rests the oldest row below topPadding',
    (tester) async {
      final controller = ChatScrollController()..jumpTo(39);
      final ds = _Source(40);
      final topPad = ValueNotifier<double>(72);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(topPad.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatScrollView(
              reverse: true,
              dataSource: ds,
              controller: controller,
              topPadding: topPad,
              messageBuilder: (context, id, message, status, runLayout) =>
                  SizedBox(height: 60, child: Text('msg-$id')),
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.fling(find.byType(ChatScrollView), const Offset(0, 1500), 3000);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('msg-0'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('msg-0')).dy,
        greaterThanOrEqualTo(72 - 0.5),
        reason: 'oldest row must not stay under the reserved top inset',
      );
    },
  );
}
