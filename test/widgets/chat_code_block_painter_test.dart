import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampleDartCode = '''
void main() {
  print('Hello, world!');
}
''';

  final sampleLongCode = 'final buffer = StringBuffer();\n' * 5; // > 75 chars

  final defaultTheme = MarkdownThemeData(
    textStyle: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
    textDirection: TextDirection.ltr,
  );

  group('ChatSelectionPolicy — Fenced Code Invariants', () {
    test(
      'Desktop policy specifies interactive top header without bottom bar',
      () {
        const desktop = ChatSelectionPolicy.desktop();
        expect(desktop.hasInteractiveCodeHeader, isTrue);
        expect(desktop.hasBottomCodeCopyBar, isFalse);
      },
    );

    test(
      'Mobile policy specifies non-interactive top header with bottom copy bar',
      () {
        const mobile = ChatSelectionPolicy.mobile();
        expect(mobile.hasInteractiveCodeHeader, isFalse);
        expect(mobile.hasBottomCodeCopyBar, isTrue);
        expect(ChatSelectionPolicy.mobileCodeCopyBarThreshold, 75);
      },
    );
  });

  group('ChatCodeBlockPainter — Desktop Policy', () {
    test('measures header and offsets selectionOrigin without bottom bar', () {
      final painter = ChatCodeBlockPainter(
        text: sampleDartCode,
        language: 'dart',
        theme: defaultTheme,
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(painter.dispose);

      expect(painter.hasHeader, isTrue);
      expect(painter.headerHeight, ChatCodeBlockPainter.desktopHeaderHeight);
      expect(painter.hasBottomBar, isFalse);
      expect(painter.bottomBarHeight, 0.0);

      // selectionOrigin must offset by padding.dx and headerHeight + padding.dy
      expect(
        painter.selectionOrigin,
        const Offset(
          ChatCodeBlockPainter.padding,
          ChatCodeBlockPainter.desktopHeaderHeight +
              ChatCodeBlockPainter.padding,
        ),
      );
      expect(painter.selectionHighlightAboveCachedContent, isTrue);

      final size = painter.layout(400);
      expect(size.width, 400.0);
      expect(
        size.height,
        ChatCodeBlockPainter.desktopHeaderHeight +
            ChatCodeBlockPainter.padding +
            painter.painter.height +
            ChatCodeBlockPainter.padding,
      );
    });

    test(
      'isLinkAtLocal returns true over top header and false over code body',
      () {
        final painter = ChatCodeBlockPainter(
          text: sampleDartCode,
          language: 'dart',
          theme: defaultTheme,
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(painter.dispose);

        painter.layout(400);

        // Over top header
        expect(painter.isLinkAtLocal(const Offset(50, 10)), isTrue);
        expect(painter.isLinkAtLocal(const Offset(350, 20)), isTrue);

        // Over code body
        final bodyY = painter.headerHeight + ChatCodeBlockPainter.padding + 10;
        expect(painter.isLinkAtLocal(Offset(50, bodyY)), isFalse);

        // Outside bounds
        expect(painter.isLinkAtLocal(const Offset(50, -5)), isFalse);
        expect(
          painter.isLinkAtLocal(Offset(50, painter.size.height + 10)),
          isFalse,
        );
      },
    );

    test('caret and boxes are shifted by selectionOrigin', () {
      final painter = ChatCodeBlockPainter(
        text: sampleDartCode,
        language: 'dart',
        theme: defaultTheme,
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(painter.dispose);

      painter.layout(400);

      final caret = painter.caretRectFor(0, TextAffinity.downstream);
      expect(
        caret.top,
        closeTo(
          ChatCodeBlockPainter.desktopHeaderHeight + ChatCodeBlockPainter.padding,
          0.5,
        ),
      );

      final boxes = painter.boxesForRange(0, sampleDartCode.length);
      expect(boxes, isNotEmpty);
      expect(
        boxes.first.top,
        greaterThanOrEqualTo(
          ChatCodeBlockPainter.desktopHeaderHeight + ChatCodeBlockPainter.padding,
        ),
      );

      // Position lookup subtracts selectionOrigin
      final (offset, _) = painter.positionAndAffinityForLocal(
        const Offset(
          ChatCodeBlockPainter.padding,
          ChatCodeBlockPainter.desktopHeaderHeight +
              ChatCodeBlockPainter.padding,
        ),
      );
      expect(offset, 0);
    });
  });

  group('ChatCodeBlockPainter — Mobile Policy', () {
    test(
      'short snippet (< 75 chars) has informative header and no bottom bar',
      () {
        final painter = ChatCodeBlockPainter(
          text: sampleDartCode, // < 75 chars
          language: 'dart',
          theme: defaultTheme,
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(painter.dispose);

        expect(painter.hasHeader, isTrue);
        expect(painter.headerHeight, ChatCodeBlockPainter.mobileHeaderHeight);
        expect(painter.hasBottomBar, isFalse);
        expect(painter.bottomBarHeight, 0.0);

        painter.layout(400);

        // Top header is informative (non-tappable) on mobile
        expect(painter.isLinkAtLocal(const Offset(50, 10)), isFalse);

        // Code body is false
        final bodyY = painter.headerHeight + ChatCodeBlockPainter.padding + 10;
        expect(painter.isLinkAtLocal(Offset(50, bodyY)), isFalse);
      },
    );

    test('long snippet (>= 75 chars) renders bottom COPY CODE bar', () {
      expect(sampleLongCode.length, greaterThanOrEqualTo(75));

      final painter = ChatCodeBlockPainter(
        text: sampleLongCode,
        language: 'dart',
        theme: defaultTheme,
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(painter.dispose);

      expect(painter.hasHeader, isTrue);
      expect(painter.hasBottomBar, isTrue);
      expect(
        painter.bottomBarHeight,
        ChatCodeBlockPainter.mobileBottomBarHeight,
      );

      // selectionOrigin remains header + padding (not affected by bottom bar)
      expect(
        painter.selectionOrigin,
        const Offset(
          ChatCodeBlockPainter.padding,
          ChatCodeBlockPainter.mobileHeaderHeight +
              ChatCodeBlockPainter.padding,
        ),
      );

      final size = painter.layout(400);
      expect(
        size.height,
        ChatCodeBlockPainter.mobileHeaderHeight +
            ChatCodeBlockPainter.padding +
            painter.painter.height +
            ChatCodeBlockPainter.padding +
            ChatCodeBlockPainter.mobileBottomBarHeight,
      );

      // Top header is informative on mobile
      expect(painter.isLinkAtLocal(const Offset(50, 10)), isFalse);

      // Code body is false
      final bodyY = painter.headerHeight + ChatCodeBlockPainter.padding + 10;
      expect(painter.isLinkAtLocal(Offset(50, bodyY)), isFalse);

      // Bottom bar is interactive
      final bottomBarY =
          size.height - ChatCodeBlockPainter.mobileBottomBarHeight / 2;
      expect(painter.isLinkAtLocal(Offset(50, bottomBarY)), isTrue);
    });

    test('snippet without language renders no top header on mobile', () {
      final painter = ChatCodeBlockPainter(
        text: sampleDartCode,
        language: null,
        theme: defaultTheme,
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(painter.dispose);

      expect(painter.hasHeader, isFalse);
      expect(painter.headerHeight, 0.0);
      expect(
        painter.selectionOrigin,
        const Offset(
          ChatCodeBlockPainter.padding,
          ChatCodeBlockPainter.padding,
        ),
      );
    });
  });

  group('ChatTextSelection — Fenced Code Inline Hit Separation', () {
    test(
      'inlineHitAt returns ChatInlineHit.code on header/bottomBar and null on body',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        final md = Markdown.fromString(
          'Header paragraph with `inline mono` snippet\n\n'
          '```dart\nvoid main() {}\n```\n\n'
          'Trailing text',
        );
        selection.putBody(1, md);

        // Block 0: Paragraph with inline mono span
        final monoHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 0,
          offset: 25,
        );
        expect(monoHit, isA<ChatInlineHit$Code>());
        expect((monoHit! as ChatInlineHit$Code).code, 'inline mono');

        // Block 2: Fenced code block (void main() {})
        // Inside code body (isHeader: false, isBottomBar: false)
        final bodyHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 2,
          offset: 3,
        );
        expect(
          bodyHit,
          isNull,
          reason: 'Code body taps must not trigger inline hit',
        );

      // Top header tap (isHeader: true)
      final headerHit = selection.inlineHitAt(
        messageId: 1,
        blockIndex: 2,
        offset: 0,
        isHeader: true,
      );
      expect(headerHit, isA<ChatInlineHit$Code>());
      final headerCode = headerHit! as ChatInlineHit$Code;
      expect(headerCode.code, 'void main() {}');
      expect(headerCode.language, 'dart');

      // Bottom bar tap (isBottomBar: true)
      final bottomHit = selection.inlineHitAt(
        messageId: 1,
        blockIndex: 2,
        offset: 0,
        isBottomBar: true,
      );
      expect(bottomHit, isA<ChatInlineHit$Code>());
      final bottomCode = bottomHit! as ChatInlineHit$Code;
      expect(bottomCode.code, 'void main() {}');
      expect(bottomCode.language, 'dart');
    });
  });

  group('ChatCodeBlockPainter — Harness & Widget Seam', () {
    testWidgets('desktop hover cursor shows click over header and text over body',
        (tester) async {
      final controller = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(controller.dispose);

      final md = Markdown.fromString('```dart\nvoid main() {\n  runApp();\n}\n```');
      controller.putBody(1, md);
      controller.enterTextSelection(1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: ChatMarkdownBody(
                  controller: controller,
                  messageId: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final markdownOrigin = tester.getTopLeft(find.byType(MarkdownWidget));

      // Hover over header (y = 15 dp, inside 32 dp header)
      await gesture.moveTo(markdownOrigin + const Offset(100, 15));
      await tester.pumpAndSettle();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
        reason: 'Desktop code header must present click hand cursor',
      );

      // Hover over code body (y = 55 dp, inside body text)
      await gesture.moveTo(markdownOrigin + const Offset(100, 55));
      await tester.pumpAndSettle();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.text,
        reason: 'Code body text must present text I-beam cursor',
      );
    });

    testWidgets('desktop clicking header triggers onCodeTap without activating text selection',
        (tester) async {
      String? tappedCode;
      final controller = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
        onCodeTap: (msgId, code) {
          tappedCode = code;
        },
      );
      addTearDown(controller.dispose);

      final md = Markdown.fromString('```dart\nvoid main() {}\n```');
      controller.putBody(1, md);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: ChatMarkdownBody(
                  controller: controller,
                  messageId: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markdownOrigin = tester.getTopLeft(find.byType(MarkdownWidget));

      // Click top header (y = 15)
      final headerPoint = markdownOrigin + const Offset(100, 15);
      final inlineHit = controller.resolveInlineHit(1, headerPoint);
      expect(inlineHit, isA<ChatInlineHit$Code>());
      expect((inlineHit! as ChatInlineHit$Code).code, 'void main() {}');

      controller.handleInlineHit(inlineHit);
      expect(tappedCode, 'void main() {}');
      expect(controller.isTextSelectionActive, isFalse);
    });

    testWidgets('mobile tapping bottom copy bar triggers onCodeTap, top header does not',
        (tester) async {
      String? tappedCode;
      final controller = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
        onCodeTap: (msgId, code) {
          tappedCode = code;
        },
      );
      addTearDown(controller.dispose);

      // Snippet >= 75 chars
      final md = Markdown.fromString('```dart\n$sampleLongCode\n```');
      controller.putBody(1, md);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: ChatMarkdownBody(
                  controller: controller,
                  messageId: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markdownOrigin = tester.getTopLeft(find.byType(MarkdownWidget));
      final markdownSize = tester.getSize(find.byType(MarkdownWidget));

      // 1. Tapping informative top header (y = 12) must NOT return inline hit
      final headerPoint = markdownOrigin + const Offset(100, 12);
      final headerHit = controller.resolveInlineHit(1, headerPoint);
      expect(headerHit, isNull, reason: 'Mobile top header is informative only');

      // 2. Tapping bottom copy bar (near bottom edge) MUST return code inline hit
      final bottomBarPoint = markdownOrigin + Offset(100, markdownSize.height - 12);
      final bottomHit = controller.resolveInlineHit(1, bottomBarPoint);
      expect(bottomHit, isA<ChatInlineHit$Code>());
      expect((bottomHit! as ChatInlineHit$Code).code.trim(), sampleLongCode.trim());

      controller.handleInlineHit(bottomHit);
      expect(tappedCode?.trim(), sampleLongCode.trim());
    });

    testWidgets('padding hit zones do not misclassify as header or bottom bar',
        (tester) async {
      final controller = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(controller.dispose);

      final md = Markdown.fromString('```dart\nvoid main() {}\n```');
      controller.putBody(1, md);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: ChatMarkdownBody(
                  controller: controller,
                  messageId: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markdownOrigin = tester.getTopLeft(find.byType(MarkdownWidget));

      // Header is dy in [0, 32).
      // Padding is dy in [32, 40).
      // Tapping at dy = 35 (in top padding) must return null, NOT click-to-copy!
      final paddingPoint = markdownOrigin + const Offset(100, 35);
      final paddingHit = controller.resolveInlineHit(1, paddingPoint);
      expect(
        paddingHit,
        isNull,
        reason: 'Taps in top padding must not trigger header copy',
      );
    });

    testWidgets(
        'code body interactions support word selection and range selection',
        (tester) async {
      final controller = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(controller.dispose);

      final md = Markdown.fromString('```dart\nvoid main() {}\n```');
      controller.putBody(1, md);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: ChatMarkdownBody(
                  controller: controller,
                  messageId: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markdownOrigin = tester.getTopLeft(find.byType(MarkdownWidget));

      // Code body text starts at dy = 32 (header) + 8 (padding) = 40.
      // Point at 'main': x ~= 50, y ~= 48.
      final codeBodyPoint = markdownOrigin + const Offset(50, 48);

      // Verify inline hit is null on code body
      final inlineHit = controller.resolveInlineHit(1, codeBodyPoint);
      expect(inlineHit, isNull, reason: 'Code body taps must not trigger inline hit');

      // Enter text selection at code body point (triggers word selection)
      expect(controller.enterTextSelection(1, globalOffset: codeBodyPoint), isTrue);
      expect(controller.isTextSelectionActive, isTrue);

      await tester.pump();
      await tester.pump();

      // Text selection should be active and non-collapsed (word at caret)
      expect(controller.textSelection, isNotNull);
      expect(controller.textSelection!.isCollapsed, isFalse);
      expect(controller.textSelection!.base.documentId, 1);
    });
  });
}
