import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show kLongPressTimeout, kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
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

/// Red-capable loop for: mobile long-press enters text selection but chrome
/// (handles + AdaptiveTextSelectionToolbar) never appears.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'mobile long-press text entry shows handles and toolbar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: dataSource,
                  controller: controller,
                  selectionController: selection,
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        key: ValueKey('container-$id'),
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ChatMarkdownBody(
                          key: ValueKey('md-$id'),
                          controller: selection,
                          messageId: id,
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Message-then-text: select row, then long-press body.
        selection.startSelection(1);
        await tester.pumpAndSettle();

        final mdCenter = tester.getCenter(find.byType(MarkdownWidget));
        final gesture = await tester.startGesture(mdCenter);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await tester.pump(); // word-at-global post-frame
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        // Range landed (user's "first piece of text").
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelection, isNotNull);
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(selection.markdownSelection.getText(), isNotEmpty);

        // Chrome that is dead on device: handles + toolbar.
        final scope = tester.state<MarkdownSelectionScopeState>(
          find.byType(MarkdownSelectionScope),
        );
        expect(
          find.byType(CompositedTransformFollower),
          findsNWidgets(2),
          reason: 'mobile text selection must paint start+end handles',
        );
        expect(
          scope.toolbarIsVisible,
          isTrue,
          reason: 'mobile text selection must show the adaptive toolbar',
        );
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'programmatic mobile enterTextSelection(word) shows handles and toolbar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
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
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        child: ChatMarkdownBody(
                          controller: selection,
                          messageId: id,
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        selection.startSelection(1);
        await tester.pumpAndSettle();

        final global = tester.getCenter(find.byType(MarkdownWidget));
        expect(
          selection.enterTextSelection(1, globalOffset: global),
          isTrue,
        );
        await tester.pump(); // post-frame word select
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.markdownSelection.getText(), isNotEmpty);

        final scope = tester.state<MarkdownSelectionScopeState>(
          find.byType(MarkdownSelectionScope),
        );
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
        expect(scope.toolbarIsVisible, isTrue);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'mobile long-press on selected body must drag-extend beyond one-shot word',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(
          1,
          Markdown.fromString('Hello selectable world and more words here'),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: dataSource,
                  controller: controller,
                  selectionController: selection,
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        height: 100,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ChatMarkdownBody(
                          controller: selection,
                          messageId: id,
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        selection.startSelection(1);
        await tester.pumpAndSettle();

        final md = find.byType(MarkdownWidget);
        final start = tester.getTopLeft(md) + const Offset(24, 16);
        final end = start + const Offset(180, 0);

        expect(selection.shouldRouteLongPressToText(1, start), isTrue);

        final gesture = await tester.startGesture(start);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await tester.pump();
        // Continuous hold: drag to extend (Telegram TextSelectionHelper path).
        await gesture.moveTo(end);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        // Viewport yielded: membership unchanged (no unselect span).
        expect(selection.selectedIds, <int>{1});
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        final text = selection.markdownSelection.getText();
        expect(text, isNotEmpty);
        // One-shot word entry leaves ~"Hello" / single word. Drag-extend must
        // grow past that (behavior-map E2: arms helper → word/range + drag).
        expect(
          text.length,
          greaterThan(8),
          reason:
              'long-press must remain live for drag-extend, not settle a '
              'one-shot word and drop the gesture',
        );
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'handle edge move keeps both handles after multi-message membership',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        selection.putBody(2, Markdown.fromString('Second message body text'));

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
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        child: ChatMarkdownBody(
                          controller: selection,
                          messageId: id,
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        selection
          ..startSelection(1)
          ..toggle(2);
        await tester.pumpAndSettle();
        expect(selection.selectedIds, <int>{1, 2});

        final global = tester.getCenter(find.byType(MarkdownWidget).first);
        expect(
          selection.enterTextSelection(1, globalOffset: global),
          isTrue,
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));

        // Simulate handle-driven range update (user's "next selection update").
        final tl = tester.getTopLeft(find.byType(MarkdownWidget).first);
        selection.markdownSelection.moveSelectionEdgeToGlobal(
          tl + const Offset(120, 12),
          isStart: false,
        );
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(
          find.byType(CompositedTransformFollower),
          findsNWidgets(2),
          reason: 'handles must survive range updates under multi-message membership',
        );
        final scope = tester.state<MarkdownSelectionScopeState>(
          find.byType(MarkdownSelectionScope).first,
        );
        expect(scope.toolbarIsVisible, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'mobile long-press on link or inline code of a selected body starts text selection',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(
          1,
          Markdown.fromString(
            'See [docs](https://flutter.dev) and `main()` please.',
          ),
        );

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
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        height: 100,
                        padding: const EdgeInsets.all(12),
                        child: ChatMarkdownBody(
                          controller: selection,
                          messageId: id,
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        selection.startSelection(1);
        await tester.pumpAndSettle();

        final surface = selection.markdownSelection.mountedSurfaces.first;
        final box = surface as RenderBox;

        Future<void> longPressAt(Offset local) async {
          final global = box.localToGlobal(local);
          expect(selection.shouldRouteLongPressToText(1, global), isTrue);
          final gesture = await tester.startGesture(global);
          await tester.pump(kLongPressTimeout + kPressTimeout);
          await tester.pump();
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
        }

        // Link span "docs"
        final linkBoxes = surface.localBoxesForRange(
          0,
          'See '.length,
          'See docs'.length,
        );
        expect(linkBoxes, isNotEmpty);
        await longPressAt(linkBoxes.first.center);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(selection.selectedIds, <int>{1});

        selection.clearTextSelection();
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.isSelected(1), isTrue);

        // Inline code `main()`
        final codeBoxes = surface.localBoxesForRange(
          0,
          'See docs and '.length,
          'See docs and main()'.length,
        );
        expect(codeBoxes, isNotEmpty);
        await longPressAt(codeBoxes.first.center);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.textSelection!.isCollapsed, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
