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

Future<ChatSelectionController> _pumpTail({
  required WidgetTester tester,
  required ChatScrollController controller,
  required ChatDataSource dataSource,
  bool Function(int messageId)? selectionAllowed,
}) async {
  final selection = ChatSelectionController()
    ..selectionAllowed = selectionAllowed;
  addTearDown(controller.dispose);
  addTearDown(selection.dispose);
  addTearDown(dataSource.dispose);
  await tester.pumpWidget(
    _harness(
      dataSource: dataSource,
      controller: controller,
      selection: selection,
    ),
  );
  await tester.pump();
  return selection;
}

void main() {
  group('ChatScrollView selection-allowed', () {
    testWidgets('long-press on a disallowed message does not enter selection', (
      tester,
    ) async {
      const count = 32;
      const blocked = count - 1;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = await _pumpTail(
        tester: tester,
        controller: controller,
        dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
        selectionAllowed: (id) => id != blocked,
      );

      await tester.longPress(find.text('msg-$blocked'));
      await tester.pumpAndSettle();

      expect(selection.isSelectionMode, isFalse);
      expect(selection.isSelected(blocked), isFalse);
    });

    testWidgets('tap on a disallowed message does not add it', (tester) async {
      const count = 32;
      const blocked = count - 2;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = await _pumpTail(
        tester: tester,
        controller: controller,
        dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
        selectionAllowed: (id) => id != blocked,
      );

      await tester.longPress(find.text('msg-${count - 1}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('msg-$blocked'));
      await tester.pumpAndSettle();

      expect(selection.selectedIds, {count - 1});
      expect(selection.isSelected(blocked), isFalse);
    });

    testWidgets('pointer over a disallowed row freezes the span far end', (
      tester,
    ) async {
      const count = 32;
      const blocked = count - 3;
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = await _pumpTail(
        tester: tester,
        controller: controller,
        dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
        selectionAllowed: (id) => id != blocked,
      );

      final gesture = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      await gesture.moveTo(tester.getCenter(find.text('msg-${count - 2}')));
      await tester.pump();
      expect(selection.selectedIds, {count - 1, count - 2});

      await gesture.moveTo(tester.getCenter(find.text('msg-$blocked')));
      await tester.pump();
      expect(selection.selectedIds, {count - 1, count - 2});
      expect(selection.isSelected(blocked), isFalse);
      await gesture.up();
    });

    testWidgets(
      'a disallowed id on the span chain is omitted from the selection span',
      (tester) async {
        const count = 32;
        const blocked = count - 3;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = await _pumpTail(
          tester: tester,
          controller: controller,
          dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
          selectionAllowed: (id) => id != blocked,
        );

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 4}')));
        await tester.pump();

        expect(selection.selectedIds, {count - 1, count - 2, count - 4});
        expect(selection.isSelected(blocked), isFalse);
        await gesture.up();
      },
    );
  });

  group('ChatScrollView span abort', () {
    testWidgets(
      'deleting the gesture origin ends the span and keeps the selected set',
      (tester) async {
        const count = 32;
        const origin = count - 1;
        final source = _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]);
        final controller = ChatScrollController()..jumpTo(origin);
        final selection = await _pumpTail(
          tester: tester,
          controller: controller,
          dataSource: source,
        );

        final gesture = await _longPressHold(tester, find.text('msg-$origin'));
        await gesture.moveTo(tester.getCenter(find.text('msg-${origin - 3}')));
        await tester.pump();
        expect(selection.selectedIds, {
          origin,
          origin - 1,
          origin - 2,
          origin - 3,
        });

        source.removeMessages([origin]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(selection.isSelected(origin - 1), isTrue);
        expect(selection.isSelected(origin - 2), isTrue);
        expect(selection.isSelected(origin - 3), isTrue);
        expect(selection.isSelectionMode, isTrue);
        final kept = Set<int>.of(selection.selectedIds);

        await gesture.moveTo(tester.getCenter(find.text('msg-${origin - 5}')));
        await tester.pump();
        expect(selection.selectedIds, kept);
        expect(selection.isSelected(origin - 5), isFalse);
        await gesture.up();
      },
    );

    testWidgets('after abort, span auto-scroll no longer writes the origin', (
      tester,
    ) async {
      const count = 32;
      const origin = count - 1;
      final source = _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]);
      final controller = ChatScrollController()..jumpTo(origin);
      final selection = await _pumpTail(
        tester: tester,
        controller: controller,
        dataSource: source,
      );

      final gesture = await _longPressHold(tester, find.text('msg-$origin'));
      await gesture.moveTo(_viewTopBand(tester));
      await tester.pump();

      source.removeMessages([origin]);
      await tester.pump();
      final afterAbort = Set<int>.of(selection.selectedIds);
      final originY = controller.anchorPixelOffset;
      expect(afterAbort, isNotEmpty);
      expect(selection.isSelectionMode, isTrue);

      await tester.pump(const Duration(milliseconds: 400));
      expect(selection.selectedIds, afterAbort);
      expect(controller.anchorPixelOffset, originY);
      await gesture.up();
    });
  });
}
