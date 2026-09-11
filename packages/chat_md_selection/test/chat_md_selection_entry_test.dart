import 'package:chat_md_selection/chat_md_selection.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness({
  required ChatMdSelectionController controller,
  required List<int> messageIds,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ChatMdSelectionScope(
        controller: controller,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final id in messageIds)
                  ChatMdBody(controller: controller, messageId: id),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late ChatSelectionController messages;
  late ChatMdSelectionController controller;

  setUp(() {
    messages = ChatSelectionController();
    controller = ChatMdSelectionController(messageSelection: messages);
  });

  tearDown(() {
    controller.dispose();
  });

  group('inert until text-selection entry', () {
    testWidgets('registered bodies stay unarmed and gestures disabled', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);

      await tester.pumpWidget(_harness(controller: controller, messageIds: const [1]));
      await tester.pumpAndSettle();

      expect(controller.isTextSelectionActive, isFalse);
      expect(controller.isDocumentArmed(1), isFalse);
      expect(controller.markdownSelection.selection, isNull);
      expect(controller.markdownSelection.documentCount, 0);

      final md = tester.widget<MarkdownWidget>(find.byType(MarkdownWidget));
      expect(md.documentId, isNull);
    });
  });

  group('enterTextSelection — collapse + single subject', () {
    testWidgets('collapses multi-select to subject and arms only that id', (
      tester,
    ) async {
      controller
        ..putBody(1, Markdown.fromString('First message body'), order: 0)
        ..putBody(2, Markdown.fromString('Second message body'), order: 1);
      messages
        ..startSelection(1)
        ..toggle(2);
      expect(messages.selectedIds, <int>{1, 2});

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1, 2]),
      );
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(2), isTrue);
      await tester.pump();
      await tester.pump();

      expect(messages.selectedIds, <int>{2});
      expect(controller.isTextSelectionActive, isTrue);
      expect(controller.textSelectionSubject, 2);
      expect(controller.isDocumentArmed(1), isFalse);
      expect(controller.isDocumentArmed(2), isTrue);
      expect(controller.markdownSelection.documentCount, 1);
      expect(controller.markdownSelection.documents.single.id, 2);

      final widgets = tester
          .widgetList<MarkdownWidget>(find.byType(MarkdownWidget))
          .toList();
      expect(widgets, hasLength(2));
      expect(
        widgets.where((w) => w.documentId != null).map((w) => w.documentId),
        <Object?>[2],
      );
    });
  });

  group('enterTextSelection — programmatic word at global', () {
    testWidgets('creates a non-empty range and wants default toolbar chrome', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);

      await tester.pumpWidget(_harness(controller: controller, messageIds: const [1]));
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(MarkdownWidget));
      final global = box.center;

      expect(controller.enterTextSelection(1, globalOffset: global), isTrue);
      await tester.pump(); // apply arming rebuild
      await tester.pump(); // post-frame selectWordAtGlobal

      final sel = controller.markdownSelection.selection;
      expect(sel, isNotNull);
      expect(sel!.isCollapsed, isFalse);
      expect(sel.base.documentId, 1);
      expect(sel.extent.documentId, 1);
      expect(controller.markdownSelection.getText(), isNotEmpty);
      expect(controller.markdownSelection.toolbarWanted, isTrue);
    });
  });

  group('enterTextSelection — explicit Select text', () {
    testWidgets('selects whole subject without a prior yield notify or point', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);

      await tester.pumpWidget(_harness(controller: controller, messageIds: const [1]));
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();

      final sel = controller.markdownSelection.selection;
      expect(sel, isNotNull);
      expect(sel!.isCollapsed, isFalse);
      expect(controller.markdownSelection.getText(), 'Hello selectable world');
      expect(controller.markdownSelection.toolbarWanted, isTrue);
    });

    testWidgets('fails when message is not already selected', (tester) async {
      controller.putBody(1, Markdown.fromString('Hello'));
      await tester.pumpWidget(_harness(controller: controller, messageIds: const [1]));
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isFalse);
      expect(controller.isTextSelectionActive, isFalse);
      expect(controller.markdownSelection.selection, isNull);
    });
  });

  group('clearTextSelection', () {
    testWidgets('disarms documents and keeps message selection', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);
      await tester.pumpWidget(_harness(controller: controller, messageIds: const [1]));
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();
      controller.clearTextSelection();
      await tester.pump();

      expect(controller.isTextSelectionActive, isFalse);
      expect(controller.isDocumentArmed(1), isFalse);
      expect(controller.markdownSelection.selection, isNull);
      expect(messages.selectedIds, <int>{1});
    });

    testWidgets('clearing message selection also clears text selection', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);
      await tester.pumpWidget(_harness(controller: controller, messageIds: const [1]));
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();
      messages.clear();
      await tester.pump();

      expect(controller.isTextSelectionActive, isFalse);
      expect(controller.markdownSelection.selection, isNull);
      expect(messages.selectedIds, isEmpty);
    });
  });
}
