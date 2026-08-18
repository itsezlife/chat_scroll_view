import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    final ids = messages.map((m) => m.id).toList()..sort();
    seedBoundaries(
      oldestKnownId: ids.first,
      newestKnownId: ids.last,
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

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required ChatSelectionController selection,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          selectionController: selection,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: 60,
            child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
          ),
        ),
      ),
    ),
  ),
);

Future<TestGesture> _longPressHold(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump(kLongPressTimeout + kPressTimeout);
  return gesture;
}

Offset _viewTopBand(WidgetTester tester) {
  final view = tester.getRect(find.byType(ChatScrollView));
  return Offset(view.center.dx, view.top + 8);
}

Offset _viewBottomBand(WidgetTester tester) {
  final view = tester.getRect(find.byType(ChatScrollView));
  return Offset(view.center.dx, view.bottom - 8);
}

Future<ChatSelectionController> _pumpTail({
  required WidgetTester tester,
  required ChatScrollController controller,
  int count = 32,
  int? selectionCap,
}) async {
  final selection = ChatSelectionController()..selectionCap = selectionCap;
  addTearDown(controller.dispose);
  addTearDown(selection.dispose);
  await tester.pumpWidget(
    _harness(
      dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
      controller: controller,
      selection: selection,
    ),
  );
  await tester.pump();
  return selection;
}

void main() {
  group('ChatScrollView selection cap', () {
    testWidgets(
      'default cap is null so a select span grows without a hardcoded 100',
      (tester) async {
        const count = 32;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = await _pumpTail(
          tester: tester,
          controller: controller,
        );

        expect(selection.selectionCap, isNull);

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 4}')));
        await tester.pump();

        expect(selection.selectedIds, {
          count - 1,
          count - 2,
          count - 3,
          count - 4,
        });
        expect(selection.capHits.value, 0);
        await gesture.up();
      },
    );

    testWidgets('select span does not add ids past the host cap', (
      tester,
    ) async {
      const count = 32;
      const cap = 3;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = await _pumpTail(
        tester: tester,
        controller: controller,
        selectionCap: cap,
      );

      final gesture = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      await gesture.moveTo(tester.getCenter(find.text('msg-${count - 6}')));
      await tester.pump();

      expect(selection.count, cap);
      expect(selection.selectedIds, {count - 1, count - 2, count - 3});
      await tester.pump();
      expect(selection.capHits.value, 1);
      await gesture.moveTo(tester.getCenter(find.text('msg-${count - 8}')));
      await tester.pump();
      expect(selection.capHits.value, 1);
      await gesture.up();
    });

    testWidgets(
      'at cap, auto-scroll in the grow direction does not move the scroll anchor',
      (tester) async {
        const count = 32;
        const cap = 3;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = await _pumpTail(
          tester: tester,
          controller: controller,
          selectionCap: cap,
        );

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(_viewTopBand(tester));
        await tester.pump();
        expect(selection.count, cap);

        final anchorY = controller.anchorPixelOffset;
        final anchorId = controller.anchorMessageId;
        await tester.pump(const Duration(milliseconds: 400));

        expect(selection.count, cap);
        expect(controller.anchorPixelOffset, anchorY);
        expect(controller.anchorMessageId, anchorId);
        await tester.pump();
        expect(selection.capHits.value, greaterThan(0));
        await gesture.up();
      },
    );

    testWidgets('auto-scroll that reaches the cap bumps capHits', (
      tester,
    ) async {
      const count = 32;
      const cap = 12;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = await _pumpTail(
        tester: tester,
        controller: controller,
        selectionCap: cap,
      );

      final gesture = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      await gesture.moveTo(_viewTopBand(tester));
      await tester.pump();
      expect(selection.count, lessThan(cap));
      expect(selection.capHits.value, 0);

        for (var i = 0; i < 90 && selection.count < cap; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(selection.count, cap);
        for (var i = 0; i < 10 && selection.capHits.value == 0; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump();

        expect(selection.capHits.value, 1);
        await gesture.up();
    });

    testWidgets(
      'auto-scroll over already-selected messages does not bump capHits',
      (tester) async {
        const cap = 10;
        final controller = ChatScrollController()..jumpTo(19);
        final selection = await _pumpTail(
          tester: tester,
          controller: controller,
          count: 29,
          selectionCap: cap,
        );
        for (var id = 20; id <= 28; id++) {
          selection.startSelection(id);
        }
        expect(selection.count, 9);

        final gesture = await _longPressHold(tester, find.text('msg-19'));
        expect(selection.count, cap);
        expect(selection.capHits.value, 0);

        await gesture.moveTo(_viewBottomBand(tester));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        expect(selection.capHits.value, 0);
        expect(selection.count, cap);
        await gesture.up();
      },
    );

    testWidgets(
      'at cap, moving back toward the origin drops this gesture\'s extra ids',
      (tester) async {
        const count = 32;
        const cap = 3;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = await _pumpTail(
          tester: tester,
          controller: controller,
          selectionCap: cap,
        );

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 6}')));
        await tester.pump();
        expect(selection.selectedIds, {count - 1, count - 2, count - 3});

        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 1}')));
        await tester.pump();
        expect(selection.selectedIds, {count - 1});
        await gesture.up();
      },
    );

    testWidgets(
      'at cap, auto-scroll toward the gesture origin still moves the scroll anchor',
      (tester) async {
        const cap = 3;
        const origin = 8;
        final controller = ChatScrollController()..jumpTo(origin);
        final selection = await _pumpTail(
          tester: tester,
          controller: controller,
          selectionCap: cap,
        );

        final gesture = await _longPressHold(tester, find.text('msg-$origin'));
        await gesture.moveTo(_viewBottomBand(tester));
        await tester.pump();
        expect(selection.count, cap);
        final frozenY = controller.anchorPixelOffset;

        await gesture.moveTo(_viewTopBand(tester));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(controller.anchorPixelOffset, isNot(frozenY));
        expect(selection.isSelected(origin), isTrue);
        expect(selection.count, lessThanOrEqualTo(cap));
        await gesture.up();
      },
    );

    testWidgets('unselect span can shrink the set when at cap', (tester) async {
      const count = 32;
      const cap = 3;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = await _pumpTail(
        tester: tester,
        controller: controller,
        selectionCap: cap,
      );

      final select = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      await select.moveTo(tester.getCenter(find.text('msg-${count - 6}')));
      await tester.pump();
      await select.up();
      await tester.pump();
      expect(selection.selectedIds, {count - 1, count - 2, count - 3});

      final unselect = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      expect(selection.selectedIds, {count - 2, count - 3});
      await unselect.moveTo(tester.getCenter(find.text('msg-${count - 3}')));
      await tester.pump();
      expect(selection.selectedIds, isEmpty);
      await unselect.up();
    });
  });
}
