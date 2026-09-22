import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int id, {String content = 'content'}) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: content,
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

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ChatSelectionController? selection,
  ChatMessageMenuRequestCallback? onIdleMessageTap,
  ChatMessageMenuRequestCallback? onSecondaryMessageTap,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 400,
      height: 600,
      child: ChatScrollView(
        dataSource: dataSource,
        controller: controller,
        selectionController: selection,
        onIdleMessageTap: onIdleMessageTap,
        onSecondaryMessageTap: onSecondaryMessageTap,
        messageBuilder: (context, id, message, status, runLayout) =>
            SizedBox(height: 60, child: Text('msg-$id')),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(r'ChatScrollView message menu request ($Mobile idle)', () {
    testWidgets(
      'idle tap emits request with id, slot containing tap, and no overlap flags',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        final requests = <ChatMessageMenuRequest>[];
        await tester.pumpWidget(
          _harness(
            dataSource: dataSource,
            controller: controller,
            selection: selection,
            onIdleMessageTap: requests.add,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('msg-1'));
        await tester.pump();

        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.messageId, 1);
        expect(request.slotGlobal.isEmpty, isFalse);
        expect(request.slotGlobal.contains(request.tapGlobal), isTrue);
        expect(request.membership, ChatMessageMenuMembership.idle);
        expect(request.overSelection, isFalse);
        // Text-only harness has no registered body → Outside.
        expect(request.pointState, ChatMessageMenuPointState.outside);
        expect(request.inlineHit, isNull);
        expect(request.overlapsTextSelection, isFalse);
        expect(request.selectedTextSnapshot, isNull);
        expect(selection.selectedIds, isEmpty);
        expect(selection.isTextSelectionActive, isFalse);
      },
    );

    testWidgets('gap tap does not invent a nearest-neighbor request', (
      tester,
    ) async {
      final dataSource = _LoadedSource([_msg(1)]);
      final controller = ChatScrollController();
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      final requests = <ChatMessageMenuRequest>[];
      await tester.pumpWidget(
        _harness(
          dataSource: dataSource,
          controller: controller,
          selection: selection,
          onIdleMessageTap: requests.add,
          onSecondaryMessageTap: requests.add,
        ),
      );
      await tester.pumpAndSettle();

      final view = tester.getRect(find.byType(ChatScrollView));
      await tester.tapAt(Offset(view.left + 8, view.bottom - 8));
      await tester.pump();

      expect(requests, isEmpty);
    });
  });

  group(r'ChatScrollView message menu request ($Desktop secondary)', () {
    testWidgets('secondary tap emits request with id / slot / tap while idle', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        final requests = <ChatMessageMenuRequest>[];
        await tester.pumpWidget(
          _harness(
            dataSource: dataSource,
            controller: controller,
            selection: selection,
            onSecondaryMessageTap: requests.add,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('msg-1'), buttons: kSecondaryMouseButton);
        await tester.pump();

        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.messageId, 1);
        expect(request.slotGlobal.contains(request.tapGlobal), isTrue);
        expect(request.membership, ChatMessageMenuMembership.idle);
        expect(request.overSelection, isFalse);
        expect(request.pointState, ChatMessageMenuPointState.outside);
        expect(request.overlapsTextSelection, isFalse);
        expect(request.selectedTextSnapshot, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'secondary on a selected message reports uponSelected without clearing',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final dataSource = _LoadedSource([_msg(1), _msg(2)]);
          final controller = ChatScrollController();
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.desktop(),
          );
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

          selection
            ..startSelection(1)
            ..toggle(2);

          final requests = <ChatMessageMenuRequest>[];
          await tester.pumpWidget(
            _harness(
              dataSource: dataSource,
              controller: controller,
              selection: selection,
              onSecondaryMessageTap: requests.add,
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(
            find.text('msg-2'),
            buttons: kSecondaryMouseButton,
            warnIfMissed: false,
          );
          await tester.pump();

          expect(requests, hasLength(1));
          expect(requests.single.messageId, 2);
          expect(
            requests.single.membership,
            ChatMessageMenuMembership.uponSelected,
          );
          expect(requests.single.overSelection, isTrue);
          expect(selection.selectedIds, <int>{1, 2});
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'secondary on unselected message while selection active reports elsewhere',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final dataSource = _LoadedSource([_msg(1), _msg(2)]);
          final controller = ChatScrollController();
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.desktop(),
          );
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

          selection.startSelection(1);

          final requests = <ChatMessageMenuRequest>[];
          await tester.pumpWidget(
            _harness(
              dataSource: dataSource,
              controller: controller,
              selection: selection,
              onSecondaryMessageTap: requests.add,
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(
            find.text('msg-2'),
            buttons: kSecondaryMouseButton,
            warnIfMissed: false,
          );
          await tester.pump();

          expect(requests, hasLength(1));
          expect(requests.single.messageId, 2);
          expect(
            requests.single.membership,
            ChatMessageMenuMembership.elsewhere,
          );
          expect(requests.single.overSelection, isFalse);
          expect(requests.single.canSelectUpTo, isTrue);
          expect(requests.single.selectUpToIds, isNotNull);
          expect(requests.single.selectUpToIds, contains(2));
          expect(selection.selectedIds, <int>{1});
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('secondary on selected glyphs reports overlap; miss does not', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final dataSource = _LoadedSource([
          _msg(1, content: 'Copy selected phrase here'),
        ]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Copy selected phrase here'));

        final requests = <ChatMessageMenuRequest>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: dataSource,
                  controller: controller,
                  selectionController: selection,
                  onSecondaryMessageTap: requests.add,
                  messageBuilder: (context, id, message, status, runLayout) =>
                      ChatMessageSurfaceBounds(
                        controller: selection,
                        messageId: id,
                        child: SizedBox(
                          height: 120,
                          width: 280,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(
                                key: Key('menu-hit-header'),
                                height: 24,
                                child: Text('header'),
                              ),
                              Expanded(
                                child: ChatMarkdownBody(
                                  controller: selection,
                                  messageId: id,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final md = find.byType(MarkdownWidget);
        expect(md, findsOneWidget);
        final wordPos = tester.getTopLeft(md) + const Offset(40, 8);
        expect(selection.enterTextSelection(1, globalOffset: wordPos), isTrue);
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isTrue);
        final expectedText = selection.markdownSelection.getText();
        expect(expectedText, isNotEmpty);

        // Upon selected glyphs → overlap.
        await tester.tapAt(wordPos, buttons: kSecondaryMouseButton);
        await tester.pump();
        expect(requests, hasLength(1));
        expect(requests.single.overlapsTextSelection, isTrue);
        expect(requests.single.hasTextSelection, isTrue);
        expect(requests.single.selectedTextSnapshot, expectedText);
        expect(requests.single.pointState, ChatMessageMenuPointState.inside);
        expect(selection.isTextSelectionActive, isTrue);

        requests.clear();

        // Header chrome is Inside the surface but not upon the highlight.
        final header = tester.getTopLeft(md) + const Offset(20, -12);
        await tester.tapAt(header, buttons: kSecondaryMouseButton);
        await tester.pump();
        expect(requests, hasLength(1));
        expect(requests.single.hasTextSelection, isTrue);
        expect(requests.single.overlapsTextSelection, isFalse);
        expect(requests.single.selectedTextSnapshot, isNull);
        expect(requests.single.pointState, ChatMessageMenuPointState.inside);
        expect(selection.isTextSelectionActive, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'secondary on markdown glyphs fires host callback (full-slot ownership)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final dataSource = _LoadedSource([
            _msg(1, content: 'Hello selectable world'),
          ]);
          final controller = ChatScrollController();
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.desktop(),
          );
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

          selection.putBody(1, Markdown.fromString('Hello selectable world'));

          final requests = <ChatMessageMenuRequest>[];
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 400,
                  height: 600,
                  child: ChatScrollView(
                    dataSource: dataSource,
                    controller: controller,
                    selectionController: selection,
                    onSecondaryMessageTap: requests.add,
                    messageBuilder: (context, id, message, status, runLayout) =>
                        SizedBox(
                          height: 120,
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

          final md = find.byType(MarkdownWidget);
          expect(md, findsOneWidget);
          await tester.tap(md, buttons: kSecondaryMouseButton);
          await tester.pumpAndSettle();

          expect(requests, hasLength(1));
          expect(requests.single.messageId, 1);
          expect(requests.single.pointState, ChatMessageMenuPointState.inside);
          expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'secondary on bubble stays Inside after scroll (live surface bounds)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          // Tall rows so a drag moves a still-mounted bubble without rebuild.
          final dataSource = _LoadedSource([
            for (var i = 1; i <= 20; i++) _msg(i, content: 'row-$i'),
          ]);
          final controller = ChatScrollController()..jumpTo(20);
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.desktop(),
          );
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

          final requests = <ChatMessageMenuRequest>[];
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 400,
                  height: 360,
                  child: ChatScrollView(
                    dataSource: dataSource,
                    controller: controller,
                    selectionController: selection,
                    onSecondaryMessageTap: requests.add,
                    messageBuilder: (context, id, message, status, runLayout) =>
                        SizedBox(
                          height: 80,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ChatMessageSurfaceBounds(
                              controller: selection,
                              messageId: id,
                              child: Container(
                                key: ValueKey('surface-$id'),
                                width: 220,
                                height: 56,
                                color: const Color(0xFF224466),
                                alignment: Alignment.centerLeft,
                                child: Text('bubble-$id'),
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final target = find.byKey(const ValueKey('surface-18'));
          expect(target, findsOneWidget);
          final before = tester.getCenter(target);
          expect(
            selection.containsMessageSurface(18, before),
            isTrue,
            reason: 'pre-scroll surface must contain the bubble center',
          );

          // Scroll without rebuilding mounted children — cached global
          // rects go stale if the reporter only updates on build.
          await tester.drag(find.byType(ChatScrollView), const Offset(0, 140));
          await tester.pump();

          final after = tester.getCenter(target);
          expect(after.dy, isNot(before.dy));
          expect(
            selection.containsMessageSurface(18, after),
            isTrue,
            reason:
                'after scroll, hit-test must use live geometry, not a '
                'stale global Rect cached at last build',
          );

          await tester.tapAt(after, buttons: kSecondaryMouseButton);
          await tester.pump();

          expect(requests, hasLength(1));
          expect(requests.single.messageId, 18);
          expect(requests.single.membership, ChatMessageMenuMembership.idle);
          expect(
            requests.single.pointState,
            ChatMessageMenuPointState.inside,
            reason:
                'desktop catalogs treat Outside as Select-only — stale '
                'bounds look like "elsewhere" menus after scroll',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('null secondary keeps Flutter text menu on markdown glyphs', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final dataSource = _LoadedSource([
          _msg(1, content: 'Hello selectable world'),
        ]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: dataSource,
                  controller: controller,
                  selectionController: selection,
                  messageBuilder: (context, id, message, status, runLayout) =>
                      SizedBox(
                        height: 120,
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

        final md = find.byType(MarkdownWidget);
        expect(md, findsOneWidget);
        final tl = tester.getTopLeft(md);
        final wordPos = tl + const Offset(40, 8);

        // Establish a live range so the chat context menu has Copy.
        expect(selection.enterTextSelection(1, globalOffset: wordPos), isTrue);
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isTrue);

        final gesture = await tester.startGesture(
          wordPos,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
        await tester.pumpAndSettle();

        final scope = tester.state<MarkdownSelectionScopeState>(
          find.byType(MarkdownSelectionScope),
        );
        expect(scope.toolbarIsVisible, isTrue);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
