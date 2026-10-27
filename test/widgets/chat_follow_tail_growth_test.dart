import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
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

class _Source extends ChatDataSource {
  _Source(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
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

/// The last row (id [lastId]) takes its height from [lastHeight], so it grows
/// in place in layout while its message object stays fixed, like a streaming
/// reply.
Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required ValueNotifier<double> lastHeight,
  required int lastId,
  required ValueNotifier<double> viewportHeight,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: ValueListenableBuilder<double>(
        valueListenable: viewportHeight,
        builder: (context, height, _) => SizedBox(
          width: 400,
          height: height,
          child: ChatScrollView(
            dataSource: dataSource,
            controller: controller,
            messageBuilder: (context, id, message, status, runLayout) {
              if (id != lastId) {
                return SizedBox(height: 60, child: Text('msg-$id'));
              }
              return ValueListenableBuilder<double>(
                valueListenable: lastHeight,
                builder: (_, h, _) =>
                    SizedBox(height: h, child: Text('msg-$id')),
              );
            },
          ),
        ),
      ),
    ),
  ),
);

double _bandBottom(WidgetTester tester) =>
    tester.getBottomLeft(find.byType(ChatScrollView)).dy;

void main() {
  late _Source ds;
  late ChatScrollController controller;
  late ValueNotifier<double> lastHeight;
  late ValueNotifier<double> viewportHeight;

  Future<void> mount(WidgetTester tester, {int count = 40}) async {
    ds = _Source(count);
    controller = ChatScrollController()..jumpTo(count - 1);
    lastHeight = ValueNotifier<double>(60);
    viewportHeight = ValueNotifier<double>(600);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);
    addTearDown(lastHeight.dispose);
    addTearDown(viewportHeight.dispose);
    await tester.pumpWidget(
      _scaffold(
        dataSource: ds,
        controller: controller,
        lastHeight: lastHeight,
        lastId: count - 1,
        viewportHeight: viewportHeight,
      ),
    );
    await tester.pump();
    expect(controller.isAtTail.value, isTrue);
  }

  group('follow tail: growing last row', () {
    testWidgets('stays pinned to the bottom across many appends', (
      tester,
    ) async {
      await mount(tester);
      for (var i = 0; i < 50; i++) {
        lastHeight.value += 7;
        await tester.pump();
        expect(
          tester.getBottomLeft(find.text('msg-39')).dy,
          closeTo(_bandBottom(tester), 0.5),
          reason: 'step $i',
        );
      }
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('user scrolls up mid-stream: following stops, history drifts '
        '0 px', (tester) async {
      await mount(tester);
      for (var i = 0; i < 5; i++) {
        lastHeight.value += 20;
        await tester.pump();
      }
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isAtTail.value, isFalse);

      final before = tester.getTopLeft(find.text('msg-30')).dy;
      for (var i = 0; i < 30; i++) {
        lastHeight.value += 20;
        await tester.pump();
      }
      expect(tester.getTopLeft(find.text('msg-30')).dy, closeTo(before, 0.01));
      expect(controller.isAtTail.value, isFalse);
    });
  });

  group('follow tail: viewport shrink', () {
    testWidgets('still following after the band shrinks at the tail', (
      tester,
    ) async {
      await mount(tester);
      viewportHeight.value = 350;
      await tester.pump();
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);
      expect(
        tester.getBottomLeft(find.text('msg-39')).dy,
        closeTo(_bandBottom(tester), 0.5),
      );

      // Following survives: a growing row is still pinned afterwards.
      lastHeight.value += 40;
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);
      expect(
        tester.getBottomLeft(find.text('msg-39')).dy,
        closeTo(_bandBottom(tester), 0.5),
      );
    });

    testWidgets('shrink while reading history does not yank to the tail', (
      tester,
    ) async {
      await mount(tester);
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isAtTail.value, isFalse);
      viewportHeight.value = 350;
      await tester.pump();
      await tester.pump();
      expect(controller.isAtTail.value, isFalse);
    });
  });
}
