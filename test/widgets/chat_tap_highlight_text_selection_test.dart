import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_gesture_exclusion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'Alice',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'Hello selectable world',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    seedBoundaries(
      oldestKnownId: messages.first.id,
      newestKnownId: messages.last.id,
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
  tearDown(ChatSelectionGestureExclusion.debugReset);

  testWidgets(
    r'ChatTapHighlight over body must not block character-range drag ($Desktop)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController()..jumpTo(1);
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: dataSource,
                  controller: controller,
                  selectionController: selection,
                  // ignore: prefer_expression_function_bodies
                  messageBuilder: (context, id, message, status, runLayout) {
                    // Worst case: highlight hit layer shares the body path
                    // (competing pan used to arm text but leave range null).
                    return ChatTapHighlight(
                      onTap: () {},
                      child: SizedBox(
                        height: 80,
                        child: ChatMarkdownBody(
                          controller: selection,
                          messageId: id,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = selection.surfaceFor(1);
        expect(surface, isNotNull);
        final boxes = surface!.localBoxesForRange(0, 0, 5);
        expect(boxes, isNotEmpty);
        final start = (surface as RenderBox).localToGlobal(boxes.first.center);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: start);
        await tester.pump();
        await mouse.down(start);
        await mouse.moveBy(const Offset(48, 0));
        await tester.pump();

        expect(selection.isTextSelectionActive, isTrue);
        expect(
          selection.textSelection,
          isNotNull,
          reason: 'arm-only is insufficient — range must exist',
        );
        expect(
          selection.textSelection!.isCollapsed,
          isFalse,
          reason: 'highlight must not steal text-selection drag',
        );
        expect(selection.hasDragSelection, isFalse);

        await mouse.up();
        await tester.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
