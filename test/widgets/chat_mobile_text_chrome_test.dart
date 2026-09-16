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
    'mobile toolbar stays when onSecondaryMessageTap is wired',
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
                  // Same wiring as the example host — must not kill mobile
                  // text selection chrome.
                  onSecondaryMessageTap: (_) {},
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

        selection.startSelection(1);
        await tester.pumpAndSettle();

        final mdCenter = tester.getCenter(find.byType(MarkdownWidget));
        final gesture = await tester.startGesture(mdCenter);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await tester.pump();
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        final scope = tester.state<MarkdownSelectionScopeState>(
          find.byType(MarkdownSelectionScope),
        );
        expect(scope.toolbarIsVisible, isTrue);
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
    'mobile retarget long-press on another selected body must drag-extend',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
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
        selection.putBody(
          2,
          Markdown.fromString('Second selectable body with many words here'),
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
                        key: ValueKey('container-$id'),
                        height: 100,
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

        selection
          ..startSelection(1)
          ..toggle(2);
        await tester.pumpAndSettle();

        // Enter text on message 1 (continuous path).
        final md1 = find.byKey(const ValueKey('md-1'));
        final start1 = tester.getTopLeft(md1) + const Offset(24, 16);
        final gesture1 = await tester.startGesture(start1);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await tester.pump();
        await gesture1.up();
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.selectedIds, <int>{1, 2});

        // Retarget: long-press on message 2 body, then drag-extend.
        final md2 = find.byKey(const ValueKey('md-2'));
        final start2 = tester.getTopLeft(md2) + const Offset(24, 16);
        final end2 = start2 + const Offset(180, 0);
        expect(selection.shouldRouteLongPressToText(2, start2), isTrue);
        expect(selection.containsGlobal(2, start2), isTrue);

        final gesture2 = await tester.startGesture(start2);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await tester.pump();
        await gesture2.moveTo(end2);
        await tester.pump();
        await gesture2.up();
        await tester.pumpAndSettle();

        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 2);
        final text = selection.markdownSelection.getText();
        expect(text, isNotEmpty);
        expect(
          text.length,
          greaterThan(8),
          reason:
              'retarget long-press must stay live for drag-extend, not '
              'one-shot enterTextSelection and drop the gesture',
        );
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'handle drag past subject into sibling body keeps selection on subject',
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

        selection.putBody(
          1,
          Markdown.fromString('Hello selectable world and more'),
        );
        selection.putBody(
          2,
          Markdown.fromString('Second selectable body text here'),
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
                        key: ValueKey('container-$id'),
                        height: 100,
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

        selection
          ..startSelection(1)
          ..toggle(2);
        await tester.pumpAndSettle();

        final md1 = find.byKey(const ValueKey('md-1'));
        final start1 = tester.getTopLeft(md1) + const Offset(24, 16);
        expect(
          selection.enterTextSelection(1, globalOffset: start1),
          isTrue,
        );
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.textSelection!.isCollapsed, isFalse);
        final before = selection.markdownSelection.getText();
        expect(before, isNotEmpty);

        // Drag the end handle into message 2's body — must not clear text
        // (sibling registry must not create a cross-message range that the
        // facade collapses).
        final md2 = find.byKey(const ValueKey('md-2'));
        final intoSibling = tester.getTopLeft(md2) + const Offset(24, 16);
        selection.markdownSelection.moveSelectionEdgeToGlobal(
          intoSibling,
          isStart: false,
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          selection.isTextSelectionActive,
          isTrue,
          reason:
              'handle drag into a sibling body must not collapse text '
              'selection',
        );
        expect(selection.textSelectionSubject, 1);
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(selection.textSelection!.base.documentId, 1);
        expect(selection.textSelection!.extent.documentId, 1);
        expect(selection.markdownSelection.getText(), isNotEmpty);
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'retarget clears prior toolbar before the new subject settles chrome',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
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
        selection.putBody(
          2,
          Markdown.fromString('Second selectable body with many words here'),
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
                        key: ValueKey('container-$id'),
                        height: 100,
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

        selection
          ..startSelection(1)
          ..toggle(2);
        await tester.pumpAndSettle();

        final md1 = find.byKey(const ValueKey('md-1'));
        final start1 = tester.getTopLeft(md1) + const Offset(24, 16);
        final gesture1 = await tester.startGesture(start1);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await tester.pump();
        await gesture1.up();
        await tester.pumpAndSettle();

        expect(selection.textSelectionSubject, 1);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);

        // Retarget long-press on message 2: prior toolbar must not linger
        // while the new subject's range is still settling.
        final md2 = find.byKey(const ValueKey('md-2'));
        final start2 = tester.getTopLeft(md2) + const Offset(24, 16);
        final gesture2 = await tester.startGesture(start2);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await tester.pump();

        expect(selection.textSelectionSubject, 2);
        expect(
          find.byType(AdaptiveTextSelectionToolbar),
          findsNothing,
          reason:
              'prior subject toolbar must clear as soon as retarget selects '
              'the new subject; toolbar returns after the new gesture settles',
        );

        await gesture2.up();
        await tester.pumpAndSettle();

        expect(selection.textSelectionSubject, 2);
        expect(selection.isTextSelectionActive, isTrue);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
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

        MarkdownSelectionScopeState subjectScope() {
          // Prefer the subject body's scope when several mounts share the
          // controller (message 2 stays enabled under mobile multi-select).
          final scopes = find.byType(MarkdownSelectionScope);
          for (var i = 0; i < scopes.evaluate().length; i++) {
            final state = tester.state<MarkdownSelectionScopeState>(scopes.at(i));
            if (state.selectionHandleLeadersAttached || state.toolbarIsVisible) {
              return state;
            }
          }
          return tester.state<MarkdownSelectionScopeState>(scopes.first);
        }

        // Simulate handle-driven range update (user's "next selection update").
        final tl = tester.getTopLeft(find.byType(MarkdownWidget).first);
        selection.markdownSelection.moveSelectionEdgeToGlobal(
          tl + const Offset(120, 12),
          isStart: false,
        );
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(
          find.byType(CompositedTransformFollower),
          findsNWidgets(2),
          reason:
              'text selection chrome handles must survive range updates under '
              'multi-message membership',
        );
        var scope = subjectScope();
        expect(scope.toolbarIsVisible, isTrue);
        expect(
          scope.selectionHandleLeadersAttached,
          isTrue,
          reason: 'handle leaders must stay linked after the first settle',
        );

        selection.markdownSelection.moveSelectionEdgeToGlobal(
          tl + const Offset(80, 12),
          isStart: false,
        );
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
        scope = subjectScope();
        expect(
          scope.selectionHandleLeadersAttached,
          isTrue,
          reason:
              'text selection chrome leaders must survive a second non-collapsed '
              'range settle',
        );
        expect(scope.toolbarIsVisible, isTrue);

        selection.clearTextSelection();
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isFalse);
        expect(find.byType(CompositedTransformFollower), findsNothing);
        expect(
          tester
              .state<MarkdownSelectionScopeState>(
                find.byType(MarkdownSelectionScope).first,
              )
              .selectionHandleLeadersAttached,
          isFalse,
          reason: 'disarmed text must clear handle leaders (no zombie chrome)',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'toolbar and handles re-anchor when the subject scrolls (viewport reposition)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final dataSource = _LoadedSource([
          for (var i = 1; i <= 20; i++) _msg(i),
        ]);
        final controller = ChatScrollController()..jumpTo(10);
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(10, Markdown.fromString('Hello selectable world'));

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
                        child: id == 10
                            ? ChatMarkdownBody(
                                controller: selection,
                                messageId: id,
                              )
                            : Text('row $id'),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        selection.startSelection(10);
        await tester.pumpAndSettle();

        final global = tester.getCenter(find.byType(MarkdownWidget));
        expect(
          selection.enterTextSelection(10, globalOffset: global),
          isTrue,
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        final scope = tester.state<MarkdownSelectionScopeState>(
          find.byType(MarkdownSelectionScope),
        );
        expect(scope.toolbarIsVisible, isTrue);
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));

        final toolbarFinder = find.byType(AdaptiveTextSelectionToolbar);
        expect(toolbarFinder, findsOneWidget);
        final before = tester
            .widget<AdaptiveTextSelectionToolbar>(toolbarFinder)
            .anchors
            .primaryAnchor;
        final subjectBefore = tester.getCenter(find.byType(MarkdownWidget));

        controller.scrollBy(120);
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(scope.toolbarIsVisible, isTrue);
        expect(toolbarFinder, findsOneWidget);
        final after = tester
            .widget<AdaptiveTextSelectionToolbar>(toolbarFinder)
            .anchors
            .primaryAnchor;
        final subjectAfter = tester.getCenter(find.byType(MarkdownWidget));
        expect(
          subjectAfter.dy,
          isNot(equals(subjectBefore.dy)),
          reason: 'fixture must move the text selection subject on-screen',
        );
        expect(
          after,
          isNot(equals(before)),
          reason:
              'text selection chrome toolbar must re-anchor when the subject '
              'moves via viewport reposition (not only Scrollable notifications)',
        );
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
        expect(
          scope.selectionHandleLeadersAttached,
          isTrue,
          reason: 'handles must track the subject after geometry change',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'mobile Select All with multi-message membership expands subject and keeps chrome',
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

        const body1 = 'First message full body text';
        const body2 = 'Second message full body text';
        selection.putBody(1, Markdown.fromString(body1));
        selection.putBody(2, Markdown.fromString(body2));

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
                        key: ValueKey('container-$id'),
                        height: 100,
                        padding: const EdgeInsets.all(12),
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

        selection
          ..startSelection(1)
          ..toggle(2);
        await tester.pumpAndSettle();
        expect(selection.selectedIds, <int>{1, 2});

        // Partial word entry first so Select All must expand (not no-op).
        final surface = selection.surfaceFor(1);
        expect(surface, isNotNull);
        final boxes = surface!.localBoxesForRange(0, 0, 1);
        expect(boxes, isNotEmpty);
        final global = (surface as RenderBox).localToGlobal(boxes.first.center);
        expect(
          selection.enterTextSelection(1, globalOffset: global),
          isTrue,
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.textSelection!.isCollapsed, isFalse);
        final before = selection.markdownSelection.getText();
        expect(before, isNotEmpty);
        expect(before.length, lessThan(body1.length));
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);

        expect(selection.selectAllText(), isTrue);
        // Assert before pump: sibling mounts may putDocument and briefly
        // re-expand the registry; Select All already pruned at call time.
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.textSelection, isNotNull);
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(selection.textSelection!.base.documentId, 1);
        expect(selection.textSelection!.extent.documentId, 1);
        expect(selection.markdownSelection.getText(), body1);
        expect(
          selection.markdownSelection.documents.map((d) => d.id),
          <Object>[1],
        );

        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.markdownSelection.getText(), body1);
        expect(selection.exposesSelectionSurface(2), isTrue);
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
        expect(
          tester
              .state<MarkdownSelectionScopeState>(
                find.byType(MarkdownSelectionScope).first,
              )
              .toolbarIsVisible,
          isTrue,
        );

        selection.clearTextSelection();
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1, 2});
        expect(find.byType(CompositedTransformFollower), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'toolbar re-anchors when reserved bottom inset shifts the band',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final dataSource = _LoadedSource([
          for (var i = 1; i <= 12; i++) _msg(i),
        ]);
        final controller = ChatScrollController()..jumpTo(6);
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        final bottomPad = ValueNotifier<double>(0);
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);
        addTearDown(bottomPad.dispose);

        selection.putBody(6, Markdown.fromString('Hello selectable world'));

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
                  bottomPadding: bottomPad,
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        child: id == 6
                            ? ChatMarkdownBody(
                                controller: selection,
                                messageId: id,
                              )
                            : Text('row $id'),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        selection.startSelection(6);
        await tester.pumpAndSettle();

        final global = tester.getCenter(find.byType(MarkdownWidget));
        expect(
          selection.enterTextSelection(6, globalOffset: global),
          isTrue,
        );
        await tester.pump();
        await tester.pumpAndSettle();

        final scope = tester.state<MarkdownSelectionScopeState>(
          find.byType(MarkdownSelectionScope),
        );
        expect(scope.toolbarIsVisible, isTrue);

        final toolbarFinder = find.byType(AdaptiveTextSelectionToolbar);
        final before = tester
            .widget<AdaptiveTextSelectionToolbar>(toolbarFinder)
            .anchors
            .primaryAnchor;
        final subjectBefore = tester.getCenter(find.byType(MarkdownWidget));

        bottomPad.value = 120;
        await tester.pumpAndSettle();

        expect(scope.toolbarIsVisible, isTrue);
        final after = tester
            .widget<AdaptiveTextSelectionToolbar>(toolbarFinder)
            .anchors
            .primaryAnchor;
        final subjectAfter = tester.getCenter(find.byType(MarkdownWidget));
        expect(
          subjectAfter.dy,
          isNot(equals(subjectBefore.dy)),
          reason: 'reserved inset must shift on-screen subject geometry',
        );
        expect(
          after,
          isNot(equals(before)),
          reason:
              'text selection chrome must re-anchor when reserved inset '
              'shifts the scroll band',
        );
        expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
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
