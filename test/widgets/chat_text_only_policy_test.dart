import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_gesture_exclusion.dart';
import 'package:flutter/foundation.dart';
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

  group(r'ChatSelectionPolicy$TextOnly matrix', () {
    const policy = ChatSelectionPolicy.textOnly();
    const mobile = ChatSelectionPolicy.mobile();

    test('is its own variant', () {
      expect(policy, isA<ChatSelectionPolicy$TextOnly>());
    });

    test('no message selection, direct text entry, timer long-press', () {
      expect(policy.allowsMessageSelection, isFalse);
      expect(policy.allowsTextEntryWithoutMessageSelection, isTrue);
      expect(policy.usesTimerBasedLongPress, isTrue);
      expect(policy.routesLongPressToTextSelection, isFalse);
      expect(policy.nestsTextSubjectInMessageSelection, isFalse);
      expect(policy.routesPrimaryTapToIdleMessage, isFalse);
      expect(policy.shiftsBubbleForSelectionGutter, isFalse);
      expect(policy.appliesSelectedColorToBubble, isFalse);
      expect(policy.suppressesLinkTapInMessageSelection, isFalse);
    });

    test('keeps the mobile touch chrome', () {
      expect(policy.scopesTextRangeSuppressionToSubject, isFalse);
      expect(policy.suppressesTapHighlightDuringSelection, isTrue);
      expect(policy.secondaryMessageTapOwnsFullSlot, isFalse);
      expect(policy.hasBottomCodeCopyBar, isTrue);
      expect(policy.hasInteractiveCodeHeader, isFalse);
    });

    test('mobile and desktop still select messages', () {
      expect(mobile.allowsMessageSelection, isTrue);
      expect(const ChatSelectionPolicy.desktop().allowsMessageSelection, isTrue);
    });

    test('enter membership clears, copy clears the range', () {
      var cleared = 0;
      var replaced = 0;
      policy.applyEnterMembership(
        replaceSelectedIds: (_) => replaced++,
        clearMessageSelection: () => cleared++,
        messageId: 1,
      );
      expect((cleared, replaced), (1, 0));
      var text = 0;
      var message = 0;
      policy.applyCopySuccess(
        clearTextSelection: () => text++,
        clearMessageSelection: () => message++,
      );
      expect((text, message), (1, 1));
    });
  });

  testWidgets(
    'long press on a body selects text with no message selection',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController()..jumpTo(1);
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.textOnly(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
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
                    return SizedBox(
                      height: 80,
                      child: ChatMarkdownBody(
                        controller: selection,
                        messageId: id,
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
        final at = (surface as RenderBox).localToGlobal(boxes.first.center);

        // A plain tap neither selects a message nor text.
        await tester.tapAt(at);
        await tester.pumpAndSettle();
        expect(selection.isSelectionMode, isFalse);
        expect(selection.isTextSelectionActive, isFalse);

        await tester.longPressAt(at);
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.textSelection, isNotNull);
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(selection.isSelectionMode, isFalse);
        expect(selection.selectedIds, isEmpty);
        expect(selection.isSelected(1), isFalse);
        expect(selection.hasDragSelection, isFalse);

        // A tap elsewhere dismisses the range and still selects no message.
        await tester.tapAt(const Offset(200, 400));
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.isSelectionMode, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
