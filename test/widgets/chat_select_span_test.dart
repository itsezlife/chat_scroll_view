import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../chat_message.dart';

IChatMessage _msg(int id, {DateTime? createdAt}) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: createdAt ?? DateTime(2026),
  updatedAt: createdAt ?? DateTime(2026),
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

/// Boundaries 0–9; only id 5 is loaded — neighbors render as shimmer.
class _SparseUnloadedSource extends ChatDataSource {
  _SparseUnloadedSource() {
    upsertMessage(_msg(5));
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: 9,
      reachedOldest: false,
      reachedNewest: false,
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
  ChatGroupSeparatorBuilder? dateSeparatorBuilder,
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
          dateSeparatorBuilder: dateSeparatorBuilder,
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

void main() {
  group('ChatScrollView select span', () {
    testWidgets(
      'long-press then drag onto further present messages selects the chain',
      (tester) async {
        const count = 32;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        final gesture = await _longPressHold(
          tester,
          find.text('msg-${count - 1}'),
        );
        expect(selection.selectedIds, {count - 1});

        await gesture.moveTo(tester.getCenter(find.text('msg-${count - 3}')));
        await tester.pump();
        expect(selection.selectedIds, {count - 1, count - 2, count - 3});
        await gesture.up();
      },
    );

    testWidgets('long-press then lift without passing slop selects only origin', (
      tester,
    ) async {
      const count = 32;
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

      await tester.longPress(find.text('msg-${count - 1}'));
      await tester.pumpAndSettle();
      expect(selection.selectedIds, {count - 1});
    });

    testWidgets('moving back toward the origin drops ids this gesture added', (
      tester,
    ) async {
      const count = 32;
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

      final gesture = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      await gesture.moveTo(tester.getCenter(find.text('msg-${count - 3}')));
      await tester.pump();
      expect(selection.selectedIds, {count - 1, count - 2, count - 3});

      await gesture.moveTo(tester.getCenter(find.text('msg-${count - 1}')));
      await tester.pump();
      expect(selection.selectedIds, {count - 1});
      await gesture.up();
    });

    testWidgets('pointer over a date separator does not change the far end', (
      tester,
    ) async {
      final messages = [
        for (var i = 0; i < 16; i++)
          _msg(i, createdAt: DateTime(2026, 1, 1 + i ~/ 8, 9, i % 8)),
      ];
      final controller = ChatScrollController()..jumpTo(8);
      final selection = ChatSelectionController();
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _LoadedSource(messages),
          controller: controller,
          selection: selection,
          dateSeparatorBuilder: (context, bucket, date) => SizedBox(
            height: 24,
            child: Text('sep-${date.month}-${date.day}'),
          ),
        ),
      );
      await tester.pump();

      final gesture = await _longPressHold(tester, find.text('msg-8'));
      expect(selection.selectedIds, {8});

      await gesture.moveTo(tester.getCenter(find.text('sep-1-2')));
      await tester.pump();
      expect(selection.selectedIds, {8});
      await gesture.up();
    });

    testWidgets('pointer over shimmer does not change the far end', (
      tester,
    ) async {
      final controller = ChatScrollController()..jumpTo(5);
      final selection = ChatSelectionController();
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _SparseUnloadedSource(),
          controller: controller,
          selection: selection,
        ),
      );
      await tester.pump();

      final gesture = await _longPressHold(tester, find.text('msg-5'));
      expect(selection.selectedIds, {5});

      await gesture.moveTo(tester.getCenter(find.text('shimmer-4')));
      await tester.pump();
      expect(selection.selectedIds, {5});
      await gesture.up();
    });

    testWidgets('absent ids are skipped and never selected', (tester) async {
      const count = 32;
      final source = _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]);
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);
      addTearDown(source.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: controller,
          selection: selection,
        ),
      );
      await tester.pump();

      source.removeMessages([count - 2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final gesture = await _longPressHold(
        tester,
        find.text('msg-${count - 1}'),
      );
      await gesture.moveTo(tester.getCenter(find.text('msg-${count - 3}')));
      await tester.pump();

      expect(selection.selectedIds, {count - 1, count - 3});
      expect(selection.isSelected(count - 2), isFalse);
      await gesture.up();
    });

    testWidgets(
      'a vertical drag that did not start from this long-press still scrolls',
      (tester) async {
        const count = 32;
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pump();

        await tester.longPress(find.text('msg-${count - 1}'));
        await tester.pumpAndSettle();
        expect(selection.selectedIds, {count - 1});

        final yBefore = tester.getTopLeft(find.text('msg-${count - 2}')).dy;
        await tester.drag(find.byType(ChatScrollView), const Offset(0, 120));
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.text('msg-${count - 2}')).dy,
          isNot(yBefore),
        );
        expect(selection.selectedIds, {count - 1});
      },
    );
  });
}
