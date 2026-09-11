import 'package:chat_md_selection/chat_md_selection.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    controller = ChatMdSelectionController(
      messageSelection: messages,
      policy: const ChatMdSelectionPolicy.desktop(),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('desktop policy — direct text entry (no prior membership)', () {
    testWidgets('unselected body exposes a surface and arms markdown gestures', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      expect(controller.exposesSelectionSurface(1), isTrue);
      expect(controller.armsMarkdownGestures, isTrue);
      expect(controller.isTextSelectionActive, isFalse);

      final md = tester.widget<MarkdownWidget>(find.byType(MarkdownWidget));
      expect(md.documentId, 1);
      expect(md.controller, same(controller.markdownSelection));

      final scope = tester.widget<MarkdownSelectionScope>(
        find.byType(MarkdownSelectionScope),
      );
      expect(scope.enabled, isTrue);
    });

    testWidgets('enterTextSelection succeeds without isSelected', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      expect(messages.isSelected(1), isFalse);
      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();

      expect(controller.isTextSelectionActive, isTrue);
      expect(controller.textSelectionSubject, 1);
      expect(messages.selectedIds, isEmpty);
      expect(controller.markdownSelection.getText(), 'Hello selectable world');
    });

    testWidgets(
      'markdown range while inactive adopts exclusive text selection',
      (tester) async {
        controller.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1]),
        );
        await tester.pumpAndSettle();

        expect(controller.isTextSelectionActive, isFalse);
        expect(controller.markdownSelection.documentCount, greaterThan(0));

        final global = tester.getCenter(find.byType(MarkdownWidget));
        final sel = controller.markdownSelection.selectWordAtGlobal(global);
        expect(sel, isNotNull);
        expect(sel!.isCollapsed, isFalse);
        await tester.pump();

        expect(controller.isTextSelectionActive, isTrue);
        expect(controller.textSelectionSubject, 1);
        expect(messages.selectedIds, isEmpty);
        expect(controller.isDocumentArmed(1), isTrue);
        expect(controller.markdownSelection.documentCount, 1);
        expect(controller.markdownSelection.getText(), isNotEmpty);
      },
    );

    testWidgets(
      'cross-message gesture range clamps onto the subject document',
      (tester) async {
        controller
          ..putBody(1, Markdown.fromString('First message body'), order: 0)
          ..putBody(2, Markdown.fromString('Second message body'), order: 1);

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1, 2]),
        );
        await tester.pumpAndSettle();

        // Simulate a drag that briefly spanned two heal-registered docs.
        controller.markdownSelection.selection = MarkdownSelection(
          base: const MarkdownPosition(
            documentId: 1,
            blockIndex: 0,
            offset: 0,
          ),
          extent: const MarkdownPosition(
            documentId: 2,
            blockIndex: 0,
            offset: 4,
          ),
        );
        await tester.pump();
        await tester.pump(); // post-frame single-document sync

        expect(controller.isTextSelectionActive, isTrue);
        expect(controller.textSelectionSubject, 1);
        expect(controller.markdownSelection.documentCount, 1);
        expect(controller.markdownSelection.documents.single.id, 1);
        final sel = controller.markdownSelection.selection;
        expect(sel, isNotNull);
        expect(sel!.base.documentId, 1);
        expect(sel.extent.documentId, 1);
      },
    );

    testWidgets(
      'message membership empty is required for gesture arming',
      (tester) async {
        controller.putBody(1, Markdown.fromString('Hello selectable world'));
        messages.startSelection(1);

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1]),
        );
        await tester.pumpAndSettle();

        expect(controller.armsMarkdownGestures, isFalse);
        expect(controller.exposesSelectionSurface(1), isFalse);

        final scope = tester.widget<MarkdownSelectionScope>(
          find.byType(MarkdownSelectionScope),
        );
        expect(scope.enabled, isFalse);
      },
    );
  });

  group('desktop policy — exclusive enter while messages selected', () {
    testWidgets('enterTextSelection clears the selected set', (tester) async {
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

      expect(messages.selectedIds, isEmpty);
      expect(controller.isTextSelectionActive, isTrue);
      expect(controller.textSelectionSubject, 2);
      expect(controller.isDocumentArmed(2), isTrue);
    });
  });

  group('desktop policy — exit matrix', () {
    testWidgets('Copy success keeps range; message set stays empty', (
      tester,
    ) async {
      final fromListener = <String>[];
      controller.addCopySuccessListener(fromListener.add);
      controller.putBody(1, Markdown.fromString('Hello selectable world'));

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();

      final clipboard = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      expect(await controller.copyTextSelection(), isTrue);
      expect(clipboard, isNotEmpty);
      expect(clipboard.first.arguments['text'], 'Hello selectable world');
      expect(fromListener, <String>['Hello selectable world']);
      expect(controller.isTextSelectionActive, isTrue);
      expect(controller.markdownSelection.getText(), 'Hello selectable world');
      expect(messages.selectedIds, isEmpty);
    });

    testWidgets('dismiss-text clears range; message set already empty', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();
      controller.clearTextSelection();
      await tester.pump();

      expect(controller.isTextSelectionActive, isFalse);
      expect(controller.markdownSelection.selection, isNull);
      expect(messages.selectedIds, isEmpty);
      expect(controller.armsMarkdownGestures, isTrue);
    });

    testWidgets(
      'markdown dismiss (Esc path) clears text; message set already empty',
      (tester) async {
        controller.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1]),
        );
        await tester.pumpAndSettle();

        expect(controller.enterTextSelection(1), isTrue);
        await tester.pump();

        controller.markdownSelection.clear();
        await tester.pump();

        expect(controller.isTextSelectionActive, isFalse);
        expect(controller.markdownSelection.selection, isNull);
        expect(messages.selectedIds, isEmpty);
      },
    );

    testWidgets(
      'starting message selection while text-active clears text (exclusive)',
      (tester) async {
        controller.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1]),
        );
        await tester.pumpAndSettle();

        expect(controller.enterTextSelection(1), isTrue);
        await tester.pump();
        expect(controller.isTextSelectionActive, isTrue);

        messages.startSelection(1);
        await tester.pump();

        expect(controller.isTextSelectionActive, isFalse);
        expect(controller.markdownSelection.selection, isNull);
        expect(messages.selectedIds, <int>{1});
        expect(controller.armsMarkdownGestures, isFalse);
      },
    );

    testWidgets(
      'clear message selection while inactive is a no-op for text',
      (tester) async {
        controller.putBody(1, Markdown.fromString('Hello'));
        messages.startSelection(1);

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1]),
        );
        await tester.pumpAndSettle();

        messages.clear();
        await tester.pump();

        expect(controller.isTextSelectionActive, isFalse);
        expect(messages.selectedIds, isEmpty);
        expect(controller.armsMarkdownGestures, isTrue);
      },
    );

    testWidgets('span yield does not claim under desktop policy', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      // Surface is off while message mode is active; yield still must not claim.
      expect(controller.shouldSpanYield(1, Offset.zero), isFalse);
    });
  });
}
