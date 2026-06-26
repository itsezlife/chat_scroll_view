import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(this.count) {
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

  final int count;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;
const _messageHeight = 60.0;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double bottomPadding = 0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _viewportWidth,
          height: _viewportHeight,
          child: ChatScrollView(
            reverse: true,
            dataSource: dataSource,
            controller: controller,
            bottomPadding: ValueNotifier<double>(bottomPadding),
            messageBuilder: (context, id, message, status) => SizedBox(
              height: _messageHeight,
              child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
            ),
          ),
        ),
      ),
    ),
  );
}

double _expectedAlignedTop({
  required double viewportHeight,
  required double bottomPadding,
  required double messageHeight,
  required double alignment,
}) {
  final travel = viewportHeight - bottomPadding - messageHeight;
  if (travel <= 0) return 0;
  return alignment * travel;
}

void main() {
  group('navigation alignment', () {
    testWidgets('jumpTo alignment 0 keeps message top at viewport top', (
      tester,
    ) async {
      const count = 100;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(50);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(controller.anchorMessageId, 50);
      expect(controller.anchorPixelOffset, closeTo(0, 1));
    });

    testWidgets('jumpTo alignment 0.5 centers message in scroll band', (
      tester,
    ) async {
      const count = 100;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()
        ..jumpTo(50, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      final expected = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: 0,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      expect(controller.anchorMessageId, 50);
      expect(controller.anchorPixelOffset, closeTo(expected, 1));
    });

    testWidgets('jumpTo alignment 0.5 respects bottom inset', (tester) async {
      const count = 100;
      const bottomPadding = 96.0;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()
        ..jumpTo(50, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          bottomPadding: bottomPadding,
        ),
      );
      await tester.pump();

      final expected = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: bottomPadding,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      expect(controller.anchorPixelOffset, closeTo(expected, 1));
    });

    testWidgets('jumpTo alignment 0.5 near oldest clamps via oldest pin', (
      tester,
    ) async {
      const count = 100;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()
        ..jumpTo(0, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(controller.anchorMessageId, 0);
      expect(controller.anchorPixelOffset, closeTo(0, 1));
    });

    testWidgets('jumpTo newest ignores alignment in favor of tail pin', (
      tester,
    ) async {
      const count = 100;
      final newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()
        ..jumpTo(newest, alignment: 0.5);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, bottomPadding: 96),
      );
      await tester.pump();

      expect(controller.anchorMessageId, newest);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('animateTo alignment 0.5 settles at centered offset', (
      tester,
    ) async {
      const count = 256;
      final ds = _PreloadedDataSource(count);
      final controller = ChatScrollController()..jumpTo(count ~/ 2);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller),
      );
      await tester.pumpAndSettle();

      const targetId = 120;
      final future = controller.animateTo(
        targetId,
        duration: const Duration(milliseconds: 200),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await future;

      final expected = _expectedAlignedTop(
        viewportHeight: _viewportHeight,
        bottomPadding: 0,
        messageHeight: _messageHeight,
        alignment: 0.5,
      );
      expect(controller.anchorMessageId, targetId);
      expect(controller.anchorPixelOffset, closeTo(expected, 1));
    });
  });
}
