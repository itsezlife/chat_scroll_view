import 'package:chat_md_selection/chat_md_selection.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
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
      policy: const ChatMdSelectionPolicy.mobile(),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('exit matrix — Copy success (mobile policy)', () {
    testWidgets(
      'copyTextSelection copies plain text then clears text and message mode',
      (tester) async {
        controller.putBody(1, Markdown.fromString('Hello selectable world'));
        messages.startSelection(1);

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
        expect(controller.isTextSelectionActive, isFalse);
        expect(controller.markdownSelection.selection, isNull);
        expect(messages.selectedIds, isEmpty);
      },
    );

    testWidgets(
      'default toolbar Copy runs copyTextSelection exit policy',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          controller.putBody(1, Markdown.fromString('Hello selectable world'));
          messages.startSelection(1);

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

          final state = tester.state<MarkdownSelectionScopeState>(
            find.byType(MarkdownSelectionScope),
          );
          state.showToolbar();
          await tester.pumpAndSettle();
          expect(find.text('Copy'), findsOneWidget);

          await tester.tap(find.text('Copy'));
          await tester.pumpAndSettle();

          expect(clipboard, isNotEmpty);
          expect(clipboard.first.arguments['text'], 'Hello selectable world');
          expect(controller.isTextSelectionActive, isFalse);
          expect(messages.selectedIds, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  group('exit matrix — dismiss text (mobile policy)', () {
    testWidgets('clearTextSelection clears range but keeps the subject selected', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();
      controller.clearTextSelection();
      await tester.pump();

      expect(controller.isTextSelectionActive, isFalse);
      expect(controller.textSelectionSubject, isNull);
      expect(controller.markdownSelection.selection, isNull);
      expect(messages.selectedIds, <int>{1});
    });

    testWidgets(
      'markdown dismiss while active clears text but keeps the subject',
      (tester) async {
        controller.putBody(1, Markdown.fromString('Hello selectable world'));
        messages.startSelection(1);

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1]),
        );
        await tester.pumpAndSettle();

        expect(controller.enterTextSelection(1), isTrue);
        await tester.pump();
        expect(controller.isTextSelectionActive, isTrue);

        // Tap/Esc path: markdown scope clears the range SoT.
        controller.markdownSelection.clear();
        await tester.pump();

        expect(controller.isTextSelectionActive, isFalse);
        expect(controller.markdownSelection.selection, isNull);
        expect(messages.selectedIds, <int>{1});
      },
    );
  });

  group('exit matrix — clear message selection (mobile policy)', () {
    testWidgets('host clear empties membership and clears text selection', (
      tester,
    ) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();
      messages.clear();
      await tester.pump();

      expect(controller.isTextSelectionActive, isFalse);
      expect(controller.markdownSelection.selection, isNull);
      expect(messages.selectedIds, isEmpty);
    });

    testWidgets('last unselect clears text selection', (tester) async {
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();
      messages.toggle(1);
      await tester.pump();

      expect(messages.selectedIds, isEmpty);
      expect(controller.isTextSelectionActive, isFalse);
      expect(controller.markdownSelection.selection, isNull);
    });
  });

  group('exit matrix — replace subject (mobile policy)', () {
    testWidgets(
      'enter on a new subject moves text selection and collapses membership',
      (tester) async {
        controller
          ..putBody(1, Markdown.fromString('First message body'), order: 0)
          ..putBody(2, Markdown.fromString('Second message body'), order: 1);
        messages.startSelection(1);

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1, 2]),
        );
        await tester.pumpAndSettle();

        expect(controller.enterTextSelection(1), isTrue);
        await tester.pump();
        expect(controller.textSelectionSubject, 1);
        expect(messages.selectedIds, <int>{1});

        messages.toggle(2);
        await tester.pump();
        expect(messages.selectedIds, <int>{1, 2});
        expect(controller.isTextSelectionActive, isTrue);
        expect(controller.textSelectionSubject, 1);

        expect(controller.enterTextSelection(2), isTrue);
        await tester.pump();
        await tester.pump();

        expect(messages.selectedIds, <int>{2});
        expect(controller.isTextSelectionActive, isTrue);
        expect(controller.textSelectionSubject, 2);
        expect(controller.isDocumentArmed(1), isFalse);
        expect(controller.isDocumentArmed(2), isTrue);
        expect(controller.markdownSelection.getText(), 'Second message body');
      },
    );
  });

  group('Copy success observation (mobile policy)', () {
    testWidgets('notifies typed listener and optional callback with plain text', (
      tester,
    ) async {
      final fromListener = <String>[];
      final fromCallback = <String>[];
      controller.dispose();
      controller = ChatMdSelectionController(
        messageSelection: messages,
        policy: const ChatMdSelectionPolicy.mobile(),
        onCopySuccess: fromCallback.add,
      );
      controller.addCopySuccessListener(fromListener.add);

      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      expect(controller.enterTextSelection(1), isTrue);
      await tester.pump();

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      expect(await controller.copyTextSelection(), isTrue);
      expect(fromListener, <String>['Hello selectable world']);
      expect(fromCallback, <String>['Hello selectable world']);
    });

    testWidgets('does not notify when Copy returns false', (tester) async {
      final fromListener = <String>[];
      controller.addCopySuccessListener(fromListener.add);

      controller.putBody(1, Markdown.fromString('Hello'));
      messages.startSelection(1);

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      expect(await controller.copyTextSelection(), isFalse);
      expect(fromListener, isEmpty);
    });
  });

  group('desktop policy — Copy keeps range + exclusive enter', () {
    testWidgets(
      'copyTextSelection writes clipboard and keeps text selection active',
      (tester) async {
        controller.dispose();
        controller = ChatMdSelectionController(
          messageSelection: messages,
          policy: const ChatMdSelectionPolicy.desktop(),
        );
        controller.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1]),
        );
        await tester.pumpAndSettle();

        expect(controller.enterTextSelection(1), isTrue);
        await tester.pump();
        expect(messages.selectedIds, isEmpty);
        expect(controller.isTextSelectionActive, isTrue);

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
        expect(controller.isTextSelectionActive, isTrue);
        expect(controller.markdownSelection.getText(), 'Hello selectable world');
        expect(messages.selectedIds, isEmpty);
      },
    );

    testWidgets(
      'enterTextSelection without prior membership clears any selected set',
      (tester) async {
        controller.dispose();
        controller = ChatMdSelectionController(
          messageSelection: messages,
          policy: const ChatMdSelectionPolicy.desktop(),
        );
        controller.putBody(1, Markdown.fromString('Hello selectable world'));
        messages.startSelection(1);

        await tester.pumpWidget(
          _harness(controller: controller, messageIds: const [1]),
        );
        await tester.pumpAndSettle();

        expect(controller.enterTextSelection(1), isTrue);
        await tester.pump();

        expect(messages.selectedIds, isEmpty);
        expect(controller.isTextSelectionActive, isTrue);
        expect(controller.textSelectionSubject, 1);
        expect(controller.isDocumentArmed(1), isTrue);
      },
    );

    testWidgets('span yield does not claim under desktop policy', (
      tester,
    ) async {
      controller.dispose();
      controller = ChatMdSelectionController(
        messageSelection: messages,
        policy: const ChatMdSelectionPolicy.desktop(),
      );
      controller.putBody(1, Markdown.fromString('Hello selectable world'));
      messages.startSelection(1);

      await tester.pumpWidget(
        _harness(controller: controller, messageIds: const [1]),
      );
      await tester.pumpAndSettle();

      final global = tester.getCenter(find.byType(MarkdownWidget));
      expect(controller.shouldSpanYield(1, global), isFalse);
    });
  });
}
