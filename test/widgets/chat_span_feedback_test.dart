import 'dart:ui' as ui;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_text_selection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatSpanFeedback — Lifecycle and Timing Invariants', () {
    test(
      'press expands on pressController; release fades only on releaseController',
      () {
        final press = AnimationController(
          vsync: const TestVSync(),
          duration: ChatSpanFeedback.pressDuration,
        );
        final release = AnimationController(
          vsync: const TestVSync(),
          duration: ChatSpanFeedback.releaseDuration,
        );

        final contour = Path()..addRect(const Rect.fromLTWH(10, 10, 100, 20));
        const origin = Offset(25, 20);

        final feedback = ChatSpanFeedback(
          messageId: 42,
          contourPath: contour,
          touchOrigin: origin,
          pressController: press,
          releaseController: release,
        );

        expect(feedback.messageId, 42);
        expect(feedback.contourPath, contour);
        expect(feedback.touchOrigin, origin);

        // Unstarted: expanding/held opacity
        expect(feedback.pressT, 0.0);
        expect(feedback.releaseT, 1.0);
        expect(feedback.isHeld, isFalse);
        expect(feedback.isReleasing, isFalse);

        // Mid expand: still full opacity (held phase of release clock)
        press.value = 0.5;
        expect(feedback.pressT, greaterThan(0.0));
        expect(feedback.pressT, lessThan(1.0));
        expect(feedback.releaseT, 1.0);

        // Expand complete: held
        press.value = 1.0;
        expect(feedback.pressT, 1.0);
        expect(feedback.releaseT, 1.0);
        expect(feedback.isHeld, isTrue);

        // Mid release fade
        release.value = 0.5;
        expect(feedback.pressT, 1.0);
        expect(feedback.releaseT, lessThan(1.0));
        expect(feedback.releaseT, greaterThan(0.0));
        expect(feedback.isHeld, isFalse);
        expect(feedback.isReleasing, isTrue);

        // Release complete
        release.value = 1.0;
        expect(feedback.releaseT, 0.0);

        press.dispose();
        release.dispose();
      },
    );
  });

  group('ChatSpanFeedbackPainter — Canvas Paint Protocol', () {
    test(
      'paints base contour plate and expanding ripple clipped to contour',
      () {
        final press = AnimationController(
          vsync: const TestVSync(),
          duration: ChatSpanFeedback.pressDuration,
        );
        final release = AnimationController(
          vsync: const TestVSync(),
          duration: ChatSpanFeedback.releaseDuration,
        );

        final contour = Path()..addRect(const Rect.fromLTWH(0, 0, 100, 30));
        const origin = Offset(20, 15);

        final feedback = ChatSpanFeedback(
          messageId: 1,
          contourPath: contour,
          touchOrigin: origin,
          pressController: press,
          releaseController: release,
          color: const Color(0xFF2481CC),
        );

        final painter = ChatSpanFeedbackPainter(
          feedback: feedback,
          repaint: feedback.listenable,
        );

        expect(
          painter.shouldRepaint(ChatSpanFeedbackPainter(feedback: feedback)),
          isFalse,
        );

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        painter.paint(canvas, const Size(200, 100));

        press.value = 0.5;
        painter.paint(canvas, const Size(200, 100));

        press.value = 1.0;
        release.value = 1.0;
        painter.paint(canvas, const Size(200, 100));

        recorder.endRecording().dispose();
        press.dispose();
        release.dispose();
      },
    );
  });

  group('ChatTextSelection — Span Box Query & Contour Resolution', () {
    testWidgets(
      'resolveInlineHit populates contourPath and touchOrigin for links and code',
      (tester) async {
        final text = ChatTextSelection(
          policy: const ChatSelectionPolicy.desktop(),
        );
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );

        const markdownText =
            'Visit [Flutter](https://flutter.dev) or run `dart analyze`.';
        final model = Markdown.fromString(markdownText);
        text.putBody(1, model);
        controller.registerBody(1, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 1,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find the link span text "Flutter"
        final linkFinder = find.byType(ChatMarkdownBody);
        expect(linkFinder, findsOneWidget);

        final box = tester.renderObject<RenderBox>(linkFinder);
        final topLeft = box.localToGlobal(Offset.zero);

        // Tap on the link "Flutter" (approximate offset inside 300px width)
        // Query position for global
        final surface = controller.markdownSelection.mountedSurfaces.first;
        final boxes = surface.localBoxesForRange(
          0,
          'Visit '.length,
          'Visit Flutter'.length,
        );
        expect(
          boxes,
          isNotEmpty,
          reason: 'localBoxesForRange must return boxes for link span',
        );

        final linkCenter = topLeft + boxes.first.center;
        final hit = controller.resolveInlineHit(1, linkCenter);
        expect(hit, isA<ChatInlineHit$Link>());
        expect(
          hit!.contourPath,
          isNotNull,
          reason: 'contourPath must be non-null on resolved link hit',
        );
        expect(
          hit.touchOrigin,
          isNotNull,
          reason: 'touchOrigin must be non-null on resolved link hit',
        );
        expect(hit.touchOrigin!.dx, closeTo(boxes.first.center.dx, 1.0));
        expect(hit.touchOrigin!.dy, closeTo(boxes.first.center.dy, 1.0));

        // Test inline code span `dart analyze`
        const renderedText = 'Visit Flutter or run dart analyze.';
        final codeStart = renderedText.indexOf('dart analyze');
        final codeEnd = codeStart + 'dart analyze'.length;
        final codeBoxes = surface.localBoxesForRange(0, codeStart, codeEnd);
        expect(
          codeBoxes,
          isNotEmpty,
          reason: 'localBoxesForRange must return boxes for code span',
        );

        final codeCenter = topLeft + codeBoxes.first.center;
        final codeHit = controller.resolveInlineHit(1, codeCenter);
        expect(codeHit, isA<ChatInlineHit$Code>());
        expect(codeHit!.contourPath, isNotNull);
        expect(codeHit.touchOrigin, isNotNull);

        controller.dispose();
        text.dispose();
      },
    );

    testWidgets(
      'fenced copy chrome hits have no tap-highlight contour',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );

        final model = Markdown.fromString('```dart\nvoid main() {}\n```');
        controller.registerBody(1, model);

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
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final codeBlockIndex = model.blocks.indexWhere((b) => b is MD$Code);
        final boxes = surface.localBoxesForRange(codeBlockIndex, 0, 4);
        expect(boxes, isNotEmpty);

        // Desktop header: above code body
        final headerGlobal = renderBox.localToGlobal(
          Offset(boxes.first.center.dx, boxes.first.top - 16),
        );
        final headerHit = controller.resolveInlineHit(1, headerGlobal);
        expect(headerHit, isA<ChatInlineHit$Code>());
        expect(
          headerHit!.contourPath,
          isNull,
          reason: 'Copy chrome must not arm text-contour tap highlight',
        );
        expect(headerHit.touchOrigin, isNull);

        // Press on header must not begin span feedback
        final gesture = await tester.startGesture(headerGlobal);
        await tester.pump();
        expect(controller.spanFeedback, isNull);
        await gesture.up();
        await tester.pump();

        controller.dispose();
      },
    );
  });

  group('ChatMarkdownBody — Dynamic Cursor Resolution', () {
    testWidgets(
      'resolves click over desktop code header, inline code, and links; text over body',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );

        const markdownText = '''
Here is [a link](https://example.com) and `inline code`.

```dart
void main() {
  print("hello");
}
```
''';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(1, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 1,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;

        // 1. Over link: SystemMouseCursors.click
        final linkBoxes = surface.localBoxesForRange(
          0,
          'Here is '.length,
          'Here is a link'.length,
        );
        expect(linkBoxes, isNotEmpty);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.removePointer);

        await gesture.addPointer(
          location: Offset.zero,
        );
        await gesture.moveTo(renderBox.localToGlobal(linkBoxes.first.center));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );

        // 2. Over inline code: SystemMouseCursors.click
        // In rendered text: "Here is a link and inline code."
        const renderedCodeStart = 'Here is a link and '.length;
        final codeBoxes = surface.localBoxesForRange(
          0,
          renderedCodeStart,
          renderedCodeStart + 'inline code'.length,
        );
        expect(codeBoxes, isNotEmpty);
        await gesture.moveTo(renderBox.localToGlobal(codeBoxes.first.center));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );

        // 3. Over desktop code block header: SystemMouseCursors.click
        final codeBlockIndex = model.blocks.indexWhere((b) => b is MD$Code);
        expect(codeBlockIndex, isNot(-1));
        final codeBlockBoxes = surface.localBoxesForRange(
          codeBlockIndex,
          0,
          'void main()'.length,
        );
        expect(codeBlockBoxes, isNotEmpty);
        // Header is above code body text: dy < codeTop - padding
        final headerPoint = Offset(
          codeBlockBoxes.first.center.dx,
          codeBlockBoxes.first.top - 16.0,
        );
        await gesture.moveTo(renderBox.localToGlobal(headerPoint));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );

        // 4. Over code body text: SystemMouseCursors.text
        await gesture.moveTo(
          renderBox.localToGlobal(codeBlockBoxes.first.center),
        );
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.text,
        );

        // 5. Empty max-width gutter past code body glyphs: not I-beam
        await gesture.moveTo(
          renderBox.localToGlobal(
            Offset(
              codeBlockBoxes.first.right + 80,
              codeBlockBoxes.first.center.dy,
            ),
          ),
        );
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          isNot(SystemMouseCursors.text),
          reason: 'horizontal gutter past short lines must not look selectable',
        );

        controller.dispose();
      },
    );

    testWidgets(
      'mobile policy: basic over code header, click over bottom COPY CODE bar (>= 75 chars)',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );

        final longCode = List.generate(
          10,
          (i) => 'line $i of long code snippet;',
        ).join('\n');
        expect(longCode.length, greaterThanOrEqualTo(75));

        final markdownText = '```dart\n$longCode\n```';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(2, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 2,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;

        final codeBoxes = surface.localBoxesForRange(0, 0, 20);
        expect(codeBoxes, isNotEmpty);

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(gesture.removePointer);

        // Over mobile top header: SystemMouseCursors.basic (non-clickable)
        final headerPoint = Offset(
          codeBoxes.first.center.dx,
          codeBoxes.first.top - 12.0,
        );
        await gesture.addPointer(
          location: Offset.zero,
        );
        await gesture.moveTo(renderBox.localToGlobal(headerPoint));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.basic,
        );

        // Over bottom COPY CODE bar: SystemMouseCursors.click
        final lastBox = surface.localBoxesForRange(
          0,
          longCode.length - 10,
          longCode.length,
        );
        final bottomBarPoint = Offset(
          lastBox.first.center.dx,
          lastBox.last.bottom + 20.0,
        );
        await gesture.moveTo(renderBox.localToGlobal(bottomBarPoint));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );

        controller.dispose();
      },
    );
  });

  group('Harness Seam — Press-Lifecycle Span Feedback', () {
    testWidgets(
      'pointer down on link begins feedback; up releases after min hold',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );

        const markdownText = 'Tap [this link](https://flutter.dev) now.';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(3, model);

        ChatSpanFeedback? feedbackSnapshot;
        controller.addSpanFeedbackListener((fb) {
          if (fb != null) feedbackSnapshot = fb;
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 3,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final linkBoxes = surface.localBoxesForRange(
          0,
          'Tap '.length,
          'Tap this link'.length,
        );
        expect(linkBoxes, isNotEmpty);

        final tapPoint = renderBox.localToGlobal(linkBoxes.first.center);

        // Full tap: down arms ink, up starts release (after expand).
        await tester.tapAt(tapPoint);
        await tester.pump();

        expect(
          controller.spanFeedback,
          isNotNull,
          reason: 'spanFeedback must be active after press',
        );
        expect(feedbackSnapshot, isNotNull);
        expect(controller.spanFeedback!.messageId, 3);
        expect(
          controller.spanFeedback!.touchOrigin.dx,
          closeTo(linkBoxes.first.center.dx, 1.0),
        );
        expect(
          controller.spanFeedback!.touchOrigin.dy,
          closeTo(linkBoxes.first.center.dy, 1.0),
        );

        // Still within expand / min-hold window (release waits for expand)
        await tester.pump(const Duration(milliseconds: 30));
        expect(controller.spanFeedback, isNotNull);
        expect(
          controller.spanFeedback!.releaseT,
          1.0,
          reason: 'Minimum 60 ms hold must preserve full opacity',
        );

        // Finish expand; release fade starts after press completes
        await tester.pump(const Duration(milliseconds: 40));
        expect(controller.spanFeedback, isNotNull);
        expect(controller.spanFeedback!.pressT, 1.0);

        // Into release fade
        await tester.pump(const Duration(milliseconds: 60));
        expect(controller.spanFeedback, isNotNull);
        expect(controller.spanFeedback!.releaseT, lessThan(1.0));

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(
          controller.spanFeedback,
          isNull,
          reason: 'Feedback must clear on completion',
        );

        controller.dispose();
      },
    );

    testWidgets(
      'press holds while pointer stays down; abort clears immediately',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );

        const markdownText = 'Hold [this link](https://flutter.dev) please.';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(4, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 4,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final linkBoxes = surface.localBoxesForRange(
          0,
          'Hold '.length,
          'Hold this link'.length,
        );
        final downPoint = renderBox.localToGlobal(linkBoxes.first.center);

        final gesture = await tester.startGesture(downPoint);
        await tester.pump();
        expect(controller.spanFeedback, isNotNull);

        // Expand completes; still held (no release yet)
        await tester.pump(const Duration(milliseconds: 80));
        expect(controller.spanFeedback, isNotNull);
        expect(controller.spanFeedback!.pressT, 1.0);
        expect(controller.spanFeedback!.releaseT, 1.0);
        expect(controller.spanFeedback!.isHeld, isTrue);

        // Abort (selection yield) clears without waiting for fade
        controller.abortSpanFeedback();
        await tester.pump();
        expect(controller.spanFeedback, isNull);

        await gesture.up();
        await tester.pump();
        controller.dispose();
      },
    );

    testWidgets(
      'pointer cancel aborts armed tap highlight immediately',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );

        const markdownText = 'Cancel [this link](https://flutter.dev) press.';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(6, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 6,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final linkBoxes = surface.localBoxesForRange(
          0,
          'Cancel '.length,
          'Cancel this link'.length,
        );
        final downPoint = renderBox.localToGlobal(linkBoxes.first.center);

        final gesture = await tester.startGesture(downPoint);
        await tester.pump();
        expect(controller.spanFeedback, isNotNull);

        await gesture.cancel();
        await tester.pump();
        expect(
          controller.spanFeedback,
          isNull,
          reason: 'Pointer cancel must abort ink, not leave a held press',
        );

        controller.dispose();
      },
    );

    testWidgets(
      'move past touch slop aborts ink (list / table pan)',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );

        const markdownText = 'Pan [this link](https://flutter.dev) away.';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(7, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 7,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final linkBoxes = surface.localBoxesForRange(
          0,
          'Pan '.length,
          'Pan this link'.length,
        );
        final downPoint = renderBox.localToGlobal(linkBoxes.first.center);

        final gesture = await tester.startGesture(downPoint);
        await tester.pump();
        expect(controller.spanFeedback, isNotNull);

        // Horizontal travel past slop (table pan) — same as vertical list pan.
        await gesture.moveBy(Offset(kTouchSlop + 1, 0));
        await tester.pump();
        expect(
          controller.spanFeedback,
          isNull,
          reason: 'past-slop must abort immediately, not release-fade',
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(controller.spanFeedback, isNull);

        controller.dispose();
      },
    );

    testWidgets(
      'mobile: no tap highlight while message selection is active',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );

        const markdownText = 'Select [this link](https://flutter.dev) now.';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(10, model);
        controller.replaceSelectedIds(<int>{10});
        expect(controller.isSelectionMode, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 10,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final linkBoxes = surface.localBoxesForRange(
          0,
          'Select '.length,
          'Select this link'.length,
        );
        final downPoint = renderBox.localToGlobal(linkBoxes.first.center);

        final gesture = await tester.startGesture(downPoint);
        await tester.pump();
        expect(controller.spanFeedback, isNull);
        expect(controller.allowsInlineTapHighlight, isFalse);

        await gesture.up();
        await tester.pump();
        controller.dispose();
      },
    );

    testWidgets(
      'mobile: no tap highlight while text selection is active',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );

        const markdownText = 'Text [link here](https://flutter.dev) ok.';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(11, model);
        controller.replaceSelectedIds(<int>{11});
        expect(controller.enterTextSelection(11), isTrue);
        expect(controller.isTextSelectionActive, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 11,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final linkBoxes = surface.localBoxesForRange(
          0,
          'Text '.length,
          'Text link here'.length,
        );
        final downPoint = renderBox.localToGlobal(linkBoxes.first.center);

        final gesture = await tester.startGesture(downPoint);
        await tester.pump();
        expect(controller.spanFeedback, isNull);

        await gesture.up();
        await tester.pump();
        controller.dispose();
      },
    );

    testWidgets(
      'desktop: tap highlight still allowed during message selection',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );

        const markdownText = 'Desk [link here](https://flutter.dev) ok.';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(12, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 12,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Desktop scope unmounts while message-selected; assert the gate
        // itself stays open, then arm via facade (bodies listen while mounted).
        controller.replaceSelectedIds(<int>{12});
        expect(controller.isSelectionMode, isTrue);
        expect(controller.allowsInlineTapHighlight, isTrue);

        controller.replaceSelectedIds(const <int>{});
        expect(controller.isSelectionMode, isFalse);

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final linkBoxes = surface.localBoxesForRange(
          0,
          'Desk '.length,
          'Desk link here'.length,
        );
        final downPoint = renderBox.localToGlobal(linkBoxes.first.center);

        final gesture = await tester.startGesture(downPoint);
        await tester.pump();
        expect(controller.spanFeedback, isNotNull);

        await gesture.up();
        await tester.pumpAndSettle();
        controller.dispose();
      },
    );

    testWidgets(
      'long-press on link with host handler keeps a single feedback instance',
      (tester) async {
        var longPressCount = 0;
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
          onInteraction: (i) {
            if (i case ChatLinkActivated(gesture: ChatInlineGesture.longPress)) {
              longPressCount++;
            }
          },
        );

        const markdownText = 'Press [held](https://example.com) link.';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(5, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 5,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final linkBoxes = surface.localBoxesForRange(
          0,
          'Press '.length,
          'Press held'.length,
        );
        final point = renderBox.localToGlobal(linkBoxes.first.center);

        final gesture = await tester.startGesture(point);
        await tester.pump();
        final first = controller.spanFeedback;
        expect(first, isNotNull);

        // Long-press timeout (~500ms default)
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          identical(controller.spanFeedback, first),
          isTrue,
          reason: 'Must not spawn a second feedback on long-press',
        );
        expect(controller.spanFeedback!.isHeld, isTrue);

        // Host long-press is delivered by the viewport pointer layer; simulate
        // the same claim path the viewport uses.
        final hit = controller.resolveInlineHit(5, point);
        expect(hit, isNotNull);
        expect(controller.handleInlineHitLongPress(hit!), isTrue);
        expect(longPressCount, 1);
        expect(
          identical(controller.spanFeedback, first),
          isTrue,
          reason: 'Long-press action must not replace press ink',
        );

        await gesture.up();
        await tester.pump();
        await tester.pump(ChatSpanFeedback.totalDuration);
        await tester.pumpAndSettle();
        expect(controller.spanFeedback, isNull);

        controller.dispose();
      },
    );

    testWidgets(
      'long-press on inline code hold-to-copy aborts press feedback',
      (tester) async {
        final codeTaps = <(int, String)>[];
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
          onInteraction: (i) {
            if (i case ChatCopied(
              :final text,
              origin: ChatCopyOrigin.codeTap,
              :final messageId?,
            )) {
              codeTaps.add((messageId, text));
            }
          },
        );

        const markdownText = 'Run `main()` please.';
        final model = Markdown.fromString(markdownText);
        controller.registerBody(6, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: ChatMarkdownBody(
                    controller: controller,
                    messageId: 6,
                    markdown: model,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final surface = controller.markdownSelection.mountedSurfaces.first;
        final renderBox = surface as RenderBox;
        final codeBoxes = surface.localBoxesForRange(
          0,
          'Run '.length,
          'Run main()'.length,
        );
        final point = renderBox.localToGlobal(codeBoxes.first.center);

        final gesture = await tester.startGesture(point);
        await tester.pump();
        expect(controller.spanFeedback, isNotNull);

        await tester.pump(const Duration(milliseconds: 600));
        expect(controller.spanFeedback, isNotNull);
        expect(controller.spanFeedback!.isHeld, isTrue);

        final hit = controller.resolveInlineHit(6, point);
        expect(hit, isA<ChatInlineHit$Code>());
        expect(controller.handleInlineHitLongPress(hit!), isTrue);
        expect(codeTaps, <(int, String)>[(6, 'main()')]);
        expect(
          controller.spanFeedback,
          isNull,
          reason: 'hold-to-copy must drop press ink immediately',
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(controller.spanFeedback, isNull);

        controller.dispose();
      },
    );
  });
}
