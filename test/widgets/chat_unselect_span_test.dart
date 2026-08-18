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

Future<void> _selectSpan(
  WidgetTester tester, {
  required int origin,
  required int far,
}) async {
  final gesture = await _longPressHold(tester, find.text('msg-$origin'));
  await gesture.moveTo(tester.getCenter(find.text('msg-$far')));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Future<ChatSelectionController> _pumpLoaded(
  WidgetTester tester, {
  int count = 32,
}) async {
  final controller = ChatScrollController()..jumpTo(count - 1);
  final selection = ChatSelectionController();
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
  group('ChatScrollView unselect span', () {
    testWidgets('long-press on a selected message unselects the origin', (
      tester,
    ) async {
      const count = 32;
      final selection = await _pumpLoaded(tester);

      await _selectSpan(tester, origin: count - 1, far: count - 3);
      expect(selection.selectedIds, {count - 1, count - 2, count - 3});

      final gesture = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      expect(selection.selectedIds, {count - 2, count - 3});
      expect(selection.isSelectionMode, isTrue);
      await gesture.up();
    });

    testWidgets(
      'drag along present neighbors removes snapshot members on the chain',
      (tester) async {
        const count = 32;
        final selection = await _pumpLoaded(tester);

        await _selectSpan(tester, origin: count - 1, far: count - 4);

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 3}')));
        await tester.pump();
        expect(selection.selectedIds, {count - 4});
        await gesture.up();
      },
    );

    testWidgets('messages that were not in the snapshot stay unselected', (
      tester,
    ) async {
      const count = 32;
      final selection = await _pumpLoaded(tester);

      final start = await _longPressHold(tester, find.text('msg-${count - 1}'));
      await start.up();
      await tester.pump();
      await tester.tap(find.text('msg-${count - 4}'));
      await tester.pump();
      expect(selection.selectedIds, {count - 1, count - 4});

      final gesture = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      await gesture.moveTo(tester.getCenter(find.text('msg-${count - 3}')));
      await tester.pump();
      expect(selection.selectedIds, {count - 4});
      expect(selection.isSelected(count - 2), isFalse);
      expect(selection.isSelected(count - 3), isFalse);
      await gesture.up();
    });

    testWidgets(
      'moving back toward the origin restores snapshot members; origin stays off',
      (tester) async {
        const count = 32;
        final selection = await _pumpLoaded(tester);

        await _selectSpan(tester, origin: count - 1, far: count - 4);

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 3}')));
        await tester.pump();
        expect(selection.selectedIds, {count - 4});

        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 1}')));
        await tester.pump();
        expect(selection.selectedIds, {count - 2, count - 3, count - 4});
        expect(selection.isSelected(count - 1), isFalse);
        await gesture.up();
      },
    );

    testWidgets('after lift, tap-toggle still works on the remaining set', (
      tester,
    ) async {
      const count = 32;
      final selection = await _pumpLoaded(tester);

      await _selectSpan(tester, origin: count - 1, far: count - 3);

      final gesture = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      await gesture.moveTo(tester.getCenter(find.text('msg-${count - 2}')));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(selection.selectedIds, {count - 3});

      await tester.tap(find.text('msg-${count - 3}'));
      await tester.pump();
      expect(selection.selectedIds, isEmpty);
    });

    testWidgets(
      'emptying the set ends the span; a follow-up drag is ordinary scroll',
      (tester) async {
        const count = 32;
        final selection = await _pumpLoaded(tester);

        await _selectSpan(tester, origin: count - 1, far: count - 2);

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 2}')));
        await tester.pump();
        expect(selection.selectedIds, isEmpty);
        expect(selection.isSelectionMode, isFalse);

        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 1}')));
        await tester.pump();
        expect(selection.selectedIds, isEmpty);

        await gesture.up();
        await tester.pump();

        final yBefore = tester.getTopLeft(find.text('msg-${count - 2}')).dy;
        await tester.drag(find.byType(ChatScrollView), const Offset(0, 120));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('msg-${count - 2}')).dy,
          isNot(yBefore),
        );
        expect(selection.selectedIds, isEmpty);
      },
    );
  });
}
