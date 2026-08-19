import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
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
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: messages.length - 1,
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

class _ManualFailSource extends ChatDataSource {
  _ManualFailSource(this.count) {
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
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw StateError('manual fail');
  }
}

class _Tap {
  _Tap(this.id, this.slotGlobal, this.tapGlobal);
  final int id;
  final Rect slotGlobal;
  final Offset tapGlobal;
}

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ChatSelectionController? selection,
  ChatIdleMessageTapCallback? onIdleMessageTap,
  ChatGroupSeparatorBuilder? dateSeparatorBuilder,
  ChatChunkErrorBuilder? chunkErrorBuilder,
  ChatMessageBuilder? messageBuilder,
  bool reverse = false,
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
          onIdleMessageTap: onIdleMessageTap,
          dateSeparatorBuilder: dateSeparatorBuilder,
          chunkErrorBuilder: chunkErrorBuilder,
          reverse: reverse,
          messageBuilder:
              messageBuilder ??
              (context, id, message, status, runLayout) => SizedBox(
                height: 60,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              ),
        ),
      ),
    ),
  ),
);

void main() {
  group('ChatScrollView idle message tap', () {
    testWidgets(
      'tap on a present slot reports id and a slot rect containing the tap',
      (tester) async {
        const count = 32;
        final taps = <_Tap>[];
        final controller = ChatScrollController()..jumpTo(count - 1);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('msg-${count - 1}'));
        await tester.pump();

        expect(taps, hasLength(1));
        expect(taps.single.id, count - 1);
        expect(taps.single.slotGlobal.isEmpty, isFalse);
        expect(taps.single.slotGlobal.contains(taps.single.tapGlobal), isTrue);
      },
    );

    testWidgets('full-row hit includes the empty side of a short child', (
      tester,
    ) async {
      const count = 32;
      final taps = <_Tap>[];
      final controller = ChatScrollController()..jumpTo(count - 1);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
          controller: controller,
          onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: 60,
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 80,
                child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final view = tester.getRect(find.byType(ChatScrollView));
      final textRect = tester.getRect(find.text('msg-${count - 1}'));
      final tap = Offset(view.left + 16, textRect.center.dy);
      await tester.tapAt(tap);
      await tester.pump();

      expect(taps, hasLength(1));
      expect(taps.single.id, count - 1);
      expect(taps.single.slotGlobal.contains(tap), isTrue);
      expect(taps.single.slotGlobal.width, closeTo(view.width, 0.5));
    });

    testWidgets('tap on empty background does not fire', (tester) async {
      final taps = <_Tap>[];
      final controller = ChatScrollController()..jumpTo(2);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _LoadedSource([for (var i = 0; i < 3; i++) _msg(i)]),
          controller: controller,
          onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
          reverse: true,
        ),
      );
      await tester.pump();

      final view = tester.getRect(find.byType(ChatScrollView));
      await tester.tapAt(Offset(view.center.dx, view.top + 8));
      await tester.pump();

      expect(taps, isEmpty);
    });

    testWidgets('tap on shimmer does not fire', (tester) async {
      final taps = <_Tap>[];
      final controller = ChatScrollController()..jumpTo(5);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _SparseUnloadedSource(),
          controller: controller,
          onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
        ),
      );
      await tester.pump();

      expect(find.text('shimmer-6'), findsOneWidget);
      await tester.tap(find.text('shimmer-6'));
      await tester.pump();

      expect(taps, isEmpty);
    });

    testWidgets('tap on a chunk-error tile does not fire', (tester) async {
      final taps = <_Tap>[];
      final source = _ManualFailSource(256);
      final controller = ChatScrollController()..jumpTo(255);
      addTearDown(controller.dispose);
      addTearDown(source.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: controller,
          onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
          chunkErrorBuilder: (context, details) => SizedBox(
            height: 120,
            child: Text('error-${details.firstId}-${details.lastId}'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(find.text('error-192-255'), findsOneWidget);
      await tester.tap(find.text('error-192-255'));
      await tester.pump();

      expect(taps, isEmpty);
    });

    testWidgets('in message selection a tap toggles and does not idle-tap', (
      tester,
    ) async {
      const count = 32;
      final taps = <_Tap>[];
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
          controller: controller,
          selection: selection,
          onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-${count - 1}'));
      await tester.pumpAndSettle();
      expect(selection.isSelectionMode, isTrue);
      taps.clear();

      await tester.tap(find.text('msg-${count - 2}'));
      await tester.pumpAndSettle();

      expect(selection.isSelected(count - 2), isTrue);
      expect(taps, isEmpty);
    });

    testWidgets('long-press enters selection and does not idle-tap', (
      tester,
    ) async {
      const count = 32;
      final taps = <_Tap>[];
      final controller = ChatScrollController()..jumpTo(count - 1);
      final selection = ChatSelectionController();
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
          controller: controller,
          selection: selection,
          onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-${count - 1}'));
      await tester.pumpAndSettle();

      expect(selection.isSelectionMode, isTrue);
      expect(selection.isSelected(count - 1), isTrue);
      expect(taps, isEmpty);
    });

    testWidgets('selectionAllowed false still fires idle tap', (tester) async {
      const count = 32;
      const blocked = count - 1;
      final taps = <_Tap>[];
      final controller = ChatScrollController()..jumpTo(blocked);
      final selection = ChatSelectionController()
        ..selectionAllowed = (id) => id != blocked;
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
          controller: controller,
          selection: selection,
          onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('msg-$blocked'));
      await tester.pump();

      expect(taps, hasLength(1));
      expect(taps.single.id, blocked);
      expect(selection.isSelectionMode, isFalse);
    });

    testWidgets('null callback stays silent; selection still works', (
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

      await tester.tap(find.text('msg-${count - 1}'));
      await tester.pump();
      expect(selection.isSelectionMode, isFalse);

      await tester.longPress(find.text('msg-${count - 1}'));
      await tester.pumpAndSettle();
      expect(selection.isSelected(count - 1), isTrue);
    });

    testWidgets('callback without a selection controller still fires', (
      tester,
    ) async {
      const count = 32;
      final taps = <_Tap>[];
      final controller = ChatScrollController()..jumpTo(count - 1);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
          controller: controller,
          onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('msg-${count - 1}'));
      await tester.pump();

      expect(taps, hasLength(1));
      expect(taps.single.id, count - 1);
    });

    testWidgets('fling-cancel tap does not fire idle tap', (tester) async {
      const count = 256;
      final taps = <_Tap>[];
      final controller = ChatScrollController()..jumpTo(count - 1);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: _LoadedSource([for (var i = 0; i < count; i++) _msg(i)]),
          controller: controller,
          onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
        ),
      );
      await tester.pump();

      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 600),
        4000,
      );
      await tester.pump();
      await tester.tap(find.byType(ChatScrollView));
      await tester.pump();

      expect(taps, isEmpty);
    });

    testWidgets(
      'tap through the pinned date header hits the message underneath',
      (tester) async {
        const origin = 8;
        final taps = <_Tap>[];
        final controller = ChatScrollController()..jumpTo(origin);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < 32; i++)
                _msg(i, createdAt: DateTime(2026, 1, 1 + i ~/ 4, 9, i % 4)),
            ]),
            controller: controller,
            onIdleMessageTap: (id, slot, tap) => taps.add(_Tap(id, slot, tap)),
            dateSeparatorBuilder: (context, bucket, date) => SizedBox(
              height: 40,
              child: Text('sep-${date.month}-${date.day}'),
            ),
          ),
        );
        await tester.pump();

        final view = tester.getRect(find.byType(ChatScrollView));
        await tester.tapAt(Offset(view.center.dx, view.top + 8));
        await tester.pump();

        expect(taps, hasLength(1));
        expect(taps.single.id, origin);
      },
    );
  });
}
