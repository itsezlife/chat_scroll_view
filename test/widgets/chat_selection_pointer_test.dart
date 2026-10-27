import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kPressTimeout;
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

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required ChatSelectionController selection,
  ChatGroupSeparatorBuilder? dateSeparatorBuilder,
  ChatMessageBuilder? messageBuilder,
}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.iOS),
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
  group('viewport-owned selection pointer', () {
    testWidgets('rows do not wrap selection chrome in a GestureDetector', (
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

      expect(
        find.descendant(
          of: find.byType(SelectableMessage),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );

      await tester.longPress(find.text('msg-${count - 1}'));
      await tester.pumpAndSettle();
      expect(selection.isSelectionMode, isTrue);
      expect(selection.isSelected(count - 1), isTrue);
    });

    testWidgets('tap toggles a loaded message while selection mode is on', (
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
      await tester.tap(find.text('msg-${count - 2}'));
      await tester.pumpAndSettle();
      expect(selection.isSelected(count - 2), isTrue);
      expect(selection.count, 2);

      await tester.tap(find.text('msg-${count - 2}'));
      await tester.pumpAndSettle();
      expect(selection.isSelected(count - 2), isFalse);
      expect(selection.count, 1);
    });

    testWidgets(
      'long-press routing to text selection enters text without starting a span',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          const count = 32;
          const id = count - 1;
          final controller = ChatScrollController()..jumpTo(id);
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.mobile(),
          );
          selection.putBody(id, Markdown.fromString('Hello selectable world'));
          selection.startSelection(id);
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);

          await tester.pumpWidget(
            _harness(
              dataSource: _LoadedSource([
                for (var i = 0; i < count; i++) _msg(i),
              ]),
              controller: controller,
              selection: selection,
              messageBuilder: (context, msgId, message, status, runLayout) =>
                  SizedBox(
                    height: 60,
                    child: ChatMarkdownBody(
                      key: ValueKey('md-$msgId'),
                      controller: selection,
                      messageId: msgId,
                    ),
                  ),
            ),
          );
          await tester.pumpAndSettle();

          final md = find.byKey(const ValueKey('md-$id'));
          final point = tester.getTopLeft(md) + const Offset(24, 16);
          expect(selection.shouldRouteLongPressToText(id, point), isTrue);

          final gesture = await tester.startGesture(point);
          await tester.pump(kLongPressTimeout + kPressTimeout);
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();

          expect(selection.isTextSelectionActive, isTrue);
          expect(selection.textSelectionSubject, id);
          expect(selection.isSelected(id), isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'unselected message with selectable body still starts select span on long-press',
      (tester) async {
        const count = 32;
        const id = count - 1;
        final controller = ChatScrollController()..jumpTo(id);
        final selection = ChatSelectionController();
        selection.putBody(id, Markdown.fromString('msg-$id'));
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < count; i++) _msg(i),
            ]),
            controller: controller,
            selection: selection,
            messageBuilder: (context, msgId, message, status, runLayout) =>
                SizedBox(
                  height: 60,
                  child: ChatMarkdownBody(
                    key: ValueKey('md-$msgId'),
                    controller: selection,
                    messageId: msgId,
                  ),
                ),
          ),
        );
        await tester.pumpAndSettle();

        final target = find.byKey(const ValueKey('md-$id'));
        await tester.longPress(target, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.isSelectionMode, isTrue);
        expect(selection.isSelected(id), isTrue);
      },
    );

    testWidgets(
      'routed long-press on a selected message does not start an unselect span',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          const count = 32;
          const id = count - 1;
          final controller = ChatScrollController()..jumpTo(id);
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.mobile(),
          );
          selection.putBody(id, Markdown.fromString('Hello selectable world'));
          selection.startSelection(id);
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);

          await tester.pumpWidget(
            _harness(
              dataSource: _LoadedSource([
                for (var i = 0; i < count; i++) _msg(i),
              ]),
              controller: controller,
              selection: selection,
              messageBuilder: (context, msgId, message, status, runLayout) =>
                  SizedBox(
                    height: 60,
                    child: ChatMarkdownBody(
                      key: ValueKey('md-$msgId'),
                      controller: selection,
                      messageId: msgId,
                    ),
                  ),
            ),
          );
          await tester.pumpAndSettle();

          final md = find.byKey(const ValueKey('md-$id'));
          final point = tester.getTopLeft(md) + const Offset(24, 16);
          final gesture = await tester.startGesture(point);
          await tester.pump(kLongPressTimeout + kPressTimeout);
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();

          expect(selection.isSelected(id), isTrue);
          expect(selection.isTextSelectionActive, isTrue);
          expect(selection.count, 1);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'unrouted long-press on a selected message without body still starts an unselect span',
      (tester) async {
        const count = 32;
        const id = count - 1;
        final controller = ChatScrollController()..jumpTo(id);
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

        await tester.longPress(find.text('msg-$id'));
        await tester.pumpAndSettle();
        expect(selection.isSelected(id), isTrue);

        await tester.longPress(find.text('msg-$id'));
        await tester.pumpAndSettle();

        expect(selection.isSelected(id), isFalse);
        expect(selection.isSelectionMode, isFalse);
      },
    );

    testWidgets(
      'long-press through the pinned date header selects the message underneath',
      (tester) async {
        const origin = 8;
        final controller = ChatScrollController()..jumpTo(origin);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < 32; i++)
                _msg(i, createdAt: DateTime(2026, 1, 1 + i ~/ 4, 9, i % 4)),
            ]),
            controller: controller,
            selection: selection,
            dateSeparatorBuilder: (context, bucket, date) => SizedBox(
              height: 40,
              child: Text('sep-${date.month}-${date.day}'),
            ),
          ),
        );
        await tester.pump();

        final view = tester.getRect(find.byType(ChatScrollView));
        await tester.longPressAt(Offset(view.center.dx, view.top + 8));
        await tester.pumpAndSettle();

        expect(selection.isSelectionMode, isTrue);
        expect(selection.isSelected(origin), isTrue);
      },
    );

    testWidgets(
      'tap through the pinned date header toggles the message underneath',
      (tester) async {
        const origin = 8;
        final controller = ChatScrollController()..jumpTo(origin);
        final selection = ChatSelectionController();
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: _LoadedSource([
              for (var i = 0; i < 32; i++)
                _msg(i, createdAt: DateTime(2026, 1, 1 + i ~/ 4, 9, i % 4)),
            ]),
            controller: controller,
            selection: selection,
            dateSeparatorBuilder: (context, bucket, date) => SizedBox(
              height: 40,
              child: Text('sep-${date.month}-${date.day}'),
            ),
          ),
        );
        await tester.pump();

        await tester.longPress(find.text('msg-${origin + 2}'));
        await tester.pumpAndSettle();
        expect(selection.isSelected(origin + 2), isTrue);

        final view = tester.getRect(find.byType(ChatScrollView));
        await tester.tapAt(Offset(view.center.dx, view.top + 8));
        await tester.pumpAndSettle();

        expect(selection.isSelected(origin), isTrue);
      },
    );
  });
}
