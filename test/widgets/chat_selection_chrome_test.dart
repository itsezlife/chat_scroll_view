import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

void main() {
  group('ChatSelectionPolicy presentation properties', () {
    test('mobile policy shifts bubble and puts check at start', () {
      const policy = ChatSelectionPolicy.mobile();
      expect(policy.shiftsBubbleForSelectionGutter, isTrue);
      expect(policy.positionsSelectionCheckAtTrailingEdge, isFalse);
      expect(policy.appliesSelectedColorToBubble, isFalse);
    });

    test(
      'desktop policy leaves bubble stationary and puts check at trailing edge',
      () {
        const policy = ChatSelectionPolicy.desktop();
        expect(policy.shiftsBubbleForSelectionGutter, isFalse);
        expect(policy.positionsSelectionCheckAtTrailingEdge, isTrue);
        expect(policy.appliesSelectedColorToBubble, isTrue);
      },
    );
  });

  group('DefaultSelectionChrome desktop vs mobile presentation', () {
    ChatSelectionChromeState stateAt({
      required double mode,
      ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
      bool isSelected = true,
      bool showsCheck = true,
    }) => ChatSelectionChromeState(
      id: 1,
      modeProgress: mode,
      selectProgress: isSelected ? 1 : 0,
      isSelectionMode: mode > 0,
      isSelected: isSelected,
      showsCheck: showsCheck,
      onTap: () {},
      onLongPress: () {},
      policy: policy,
    );

    Widget buildChrome({
      required ChatSelectionChromeState state,
      required Widget child,
      double width = 400,
      ChatMessageThemeData? messageTheme,
      bool? forceDesktop,
    }) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: ChatScrollTheme(
          data: ChatScrollThemeData(
            message: messageTheme ?? ChatMessageThemeData.fallback,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: 80,
              child: forceDesktop == null
                  ? DefaultSelectionChrome(state: state, child: child)
                  : (forceDesktop
                        ? DefaultSelectionChrome.desktop(
                            state: state,
                            child: child,
                          )
                        : DefaultSelectionChrome.mobile(
                            state: state,
                            child: child,
                          )),
            ),
          ),
        ),
      ),
    );

    double dxOf(WidgetTester tester, String text) {
      final textBox = tester.renderObject<RenderBox>(find.text(text));
      final chrome = tester.renderObject<RenderBox>(
        find.byType(DefaultSelectionChrome),
      );
      return textBox.localToGlobal(Offset.zero).dx -
          chrome.localToGlobal(Offset.zero).dx;
    }

    testWidgets('desktop policy: start-aligned bubble stays stationary', (
      tester,
    ) async {
      const child = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 80, height: 20, child: Text('body')),
      );

      final closedState = stateAt(
        mode: 0,
        policy: const ChatSelectionPolicy.desktop(),
      );
      await tester.pumpWidget(buildChrome(state: closedState, child: child));
      final closedDx = dxOf(tester, 'body');

      final openState = stateAt(
        mode: 1,
        policy: const ChatSelectionPolicy.desktop(),
      );
      await tester.pumpWidget(buildChrome(state: openState, child: child));
      final openDx = dxOf(tester, 'body');

      // Desktop bubble does not translate horizontally when entering selection.
      expect(openDx, equals(closedDx));
      expect(
        find.byKey(const ValueKey<String>('chatSelectionCheck')),
        findsOneWidget,
      );
    });

    testWidgets(
      'desktop policy: check trails nearby the message column, not at window edge',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const child = Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 80, height: 20, child: Text('body')),
        );

        // Wide 1000px viewport, centered column with contentMaxWidth = 600.
        // Column goes from x = 200 to x = 800 (endSlack = 200).
        // Check must sit in the gutter right after the column: x = 800 + 12 = 812.
        const wideWidth = 1000.0;
        const messageTheme = ChatMessageThemeData(
          contentMaxWidth: 600,
          columnPlacement: ChatMessageColumnPlacement.center,
        );

        final openState = stateAt(
          mode: 1,
          policy: const ChatSelectionPolicy.desktop(),
        );
        await tester.pumpWidget(
          buildChrome(
            state: openState,
            child: child,
            width: wideWidth,
            messageTheme: messageTheme,
          ),
        );

        final checkFinder = find.byKey(
          const ValueKey<String>('chatSelectionCheck'),
        );
        expect(checkFinder, findsOneWidget);

        final check = tester.renderObject<RenderBox>(checkFinder);
        final chrome = tester.renderObject<RenderBox>(
          find.byType(DefaultSelectionChrome),
        );

        final checkDx =
            check.localToGlobal(Offset.zero).dx -
            chrome.localToGlobal(Offset.zero).dx;

        // Check is nearby the column at 812, NOT far away at 1000 - 12 - 21 = 967!
        const expectedDx = 800.0 + ChatSelectionMetrics.checkTrailingMargin;
        expect(checkDx, closeTo(expectedDx, 0.5));
      },
    );

    testWidgets('mobile policy: start-aligned bubble shifts by slot width', (
      tester,
    ) async {
      const child = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 80, height: 20, child: Text('body')),
      );

      final closedState = stateAt(
        mode: 0,
        policy: const ChatSelectionPolicy.mobile(),
      );
      await tester.pumpWidget(buildChrome(state: closedState, child: child));
      final closedDx = dxOf(tester, 'body');

      final openState = stateAt(
        mode: 1,
        policy: const ChatSelectionPolicy.mobile(),
      );
      await tester.pumpWidget(buildChrome(state: openState, child: child));
      final openDx = dxOf(tester, 'body');

      // Mobile bubble translates horizontally by slotWidth.
      expect(openDx - closedDx, closeTo(ChatSelectionMetrics.slotWidth, 0.5));
    });

    testWidgets(
      'desktop policy: shows check with opacity fading with modeProgress',
      (tester) async {
        const child = SizedBox(width: 80, height: 20, child: Text('body'));

        final halfState = stateAt(
          mode: 0.5,
          policy: const ChatSelectionPolicy.desktop(),
        );
        await tester.pumpWidget(buildChrome(state: halfState, child: child));

        final opacityFinder = find.descendant(
          of: find.byType(DefaultSelectionChrome),
          matching: find.byType(Opacity),
        );
        expect(opacityFinder, findsOneWidget);
        final opacityWidget = tester.widget<Opacity>(opacityFinder);
        expect(opacityWidget.opacity, closeTo(0.5, 0.01));
      },
    );

    testWidgets('desktop policy: omits check when showsCheck is false', (
      tester,
    ) async {
      const child = SizedBox(width: 80, height: 20, child: Text('body'));

      final state = stateAt(
        mode: 1,
        policy: const ChatSelectionPolicy.desktop(),
        showsCheck: false,
      );
      await tester.pumpWidget(buildChrome(state: state, child: child));

      expect(
        find.byKey(const ValueKey<String>('chatSelectionCheck')),
        findsNothing,
      );
    });

    testWidgets('explicit constructors force variant regardless of policy', (
      tester,
    ) async {
      const child = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 80, height: 20, child: Text('body')),
      );

      // Mobile policy + forceDesktop = true -> stationary bubble
      final mobileState = stateAt(
        mode: 1,
        policy: const ChatSelectionPolicy.mobile(),
      );
      await tester.pumpWidget(
        buildChrome(state: mobileState, child: child, forceDesktop: true),
      );
      expect(dxOf(tester, 'body'), closeTo(0.0, 0.5));

      // Desktop policy + forceDesktop = false -> sliding bubble
      final desktopState = stateAt(
        mode: 1,
        policy: const ChatSelectionPolicy.desktop(),
      );
      await tester.pumpWidget(
        buildChrome(state: desktopState, child: child, forceDesktop: false),
      );
      expect(
        dxOf(tester, 'body'),
        closeTo(ChatSelectionMetrics.slotWidth, 0.5),
      );
    });

    testWidgets('mobile paints row tint; desktop omits full-width row tint', (
      tester,
    ) async {
      const child = SizedBox(width: 80, height: 20, child: Text('body'));

      // Mobile: draws full-width tint
      final mobileState = stateAt(
        mode: 1,
        policy: const ChatSelectionPolicy.mobile(),
        isSelected: true,
      );
      await tester.pumpWidget(buildChrome(state: mobileState, child: child));
      expect(
        find.byKey(const ValueKey<String>('chatSelectionTint')),
        findsOneWidget,
      );

      // Desktop: leaves row background clean (bubble container paints itself)
      final desktopState = stateAt(
        mode: 1,
        policy: const ChatSelectionPolicy.desktop(),
        isSelected: true,
      );
      await tester.pumpWidget(buildChrome(state: desktopState, child: child));
      expect(
        find.byKey(const ValueKey<String>('chatSelectionTint')),
        findsNothing,
      );
    });
  });

  group('SelectableMessage and ChatSelectionStateScope', () {
    testWidgets(
      'SelectableMessage provides ChatSelectionStateScope to children',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);

        ChatSelectionChromeState? capturedFromScope;

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.ltr,
              child: ChatScrollTheme(
                data: const ChatScrollThemeData(),
                child: SelectableMessage(
                  id: 42,
                  allowed: ChatSelectionAllowed.all,
                  controller: controller,
                  child: Builder(
                    builder: (context) {
                      capturedFromScope = ChatSelectionStateScope.maybeOf(
                        context,
                      );
                      return const SizedBox(width: 100, height: 40);
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        expect(capturedFromScope, isNotNull);
        expect(capturedFromScope!.id, equals(42));
        expect(capturedFromScope!.policy, isA<ChatSelectionPolicy$Desktop>());
        expect(capturedFromScope!.isSelected, isFalse);

        controller.startSelection(42);
        await tester.pump();
        expect(capturedFromScope!.isSelected, isTrue);
      },
    );

    testWidgets(
      'ChatMessageChangeTransition paints selectedColor when selected in scope',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);

        const normalColor = Color(0xFF2A2A2C);
        const selectedColor = Color(0xFF2B5278);

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.ltr,
              child: ChatScrollTheme(
                data: const ChatScrollThemeData(),
                child: SelectableMessage(
                  id: 10,
                  allowed: ChatSelectionAllowed.all,
                  controller: controller,
                  child: ChatMessageChangeTransition(
                    contentIdentity: 'hello',
                    outgoing: false,
                    color: normalColor,
                    selectedColor: selectedColor,
                    borderRadius: BorderRadius.circular(16),
                    content: const Text('hello'),
                    metaBuilder: (context, opacity) => const SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        );

        RenderChatMessageChangeTransition getRenderBox() =>
            tester.renderObject<RenderChatMessageChangeTransition>(
              find.byType(ChatMessageChangeTransition),
            );

        expect(getRenderBox().color, equals(normalColor));

        controller.startSelection(10);
        await tester.pump();
        expect(getRenderBox().color, equals(selectedColor));
      },
    );

    testWidgets(
      'ChatMessageChangeTransition does not paint selectedColor when selected under mobile policy',
      (tester) async {
        final controller = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);

        const normalColor = Color(0xFF2A2A2C);
        const selectedColor = Color(0xFF2B5278);

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.ltr,
              child: ChatScrollTheme(
                data: const ChatScrollThemeData(),
                child: SelectableMessage(
                  id: 10,
                  allowed: ChatSelectionAllowed.all,
                  controller: controller,
                  child: ChatMessageChangeTransition(
                    contentIdentity: 'hello',
                    outgoing: false,
                    color: normalColor,
                    selectedColor: selectedColor,
                    borderRadius: BorderRadius.circular(16),
                    content: const Text('hello'),
                    metaBuilder: (context, opacity) => const SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        );

        RenderChatMessageChangeTransition getRenderBox() =>
            tester.renderObject<RenderChatMessageChangeTransition>(
              find.byType(ChatMessageChangeTransition),
            );

        expect(getRenderBox().color, equals(normalColor));

        controller.startSelection(10);
        await tester.pump();
        expect(getRenderBox().color, equals(normalColor));
      },
    );
  });

  group('Desktop pointer drag vs scroll wheel', () {
    testWidgets('mouse drag down does not scroll viewport, wheel scrolls', (
      tester,
    ) async {
      final messages = List.generate(30, _msg);
      final ds = _LoadedSource(messages);
      final scrollController = ChatScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ChatScrollView(
                dataSource: ds,
                controller: scrollController,
                messageBuilder: (context, id, msg, status, run) =>
                    SizedBox(height: 50, child: Text('Message #$id')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialOffset = scrollController.anchorPixelOffset;
      final initialId = scrollController.anchorMessageId;

      // 1. Mouse drag down: MUST NOT SCROLL on desktop
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.down(const Offset(200, 200)));
      await tester.sendEventToBinding(mouse.move(const Offset(200, 350)));
      await tester.pump();
      await tester.sendEventToBinding(mouse.up());
      await tester.pump();

      // Anchor and offset remain unchanged after mouse drag
      expect(scrollController.anchorPixelOffset, equals(initialOffset));
      expect(scrollController.anchorMessageId, equals(initialId));

      // 2. Mouse wheel scroll: MUST SCROLL
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Anchor offset changes on wheel scroll
      expect(scrollController.anchorPixelOffset, isNot(equals(initialOffset)));
    });

    testWidgets('touch drag down scrolls viewport normally', (tester) async {
      final messages = List.generate(30, _msg);
      final ds = _LoadedSource(messages);
      final scrollController = ChatScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: ChatScrollView(
                dataSource: ds,
                controller: scrollController,
                messageBuilder: (context, id, msg, status, run) =>
                    SizedBox(height: 50, child: Text('Message #$id')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialOffset = scrollController.anchorPixelOffset;

      // Touch drag down: MUST SCROLL
      await tester.drag(find.byType(ChatScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();

      expect(scrollController.anchorPixelOffset, isNot(equals(initialOffset)));
    });
  });

  group('Desktop pan selection and Escape dismissal', () {
    testWidgets('desktop pan selects single message when panning on it', (
      tester,
    ) async {
      final messages = List.generate(10, _msg);
      final ds = _LoadedSource(messages);
      final scrollController = ChatScrollController();
      final selectionController = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(() {
        scrollController.dispose();
        selectionController.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: ChatScrollView(
                dataSource: ds,
                controller: scrollController,
                selectionController: selectionController,
                messageBuilder: (context, id, msg, status, run) =>
                    SizedBox(height: 50, child: Text('Message #$id')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      // Pan 20px down within Message #0 (which is 50px tall, from y=0 to y=50)
      await tester.sendEventToBinding(mouse.down(const Offset(100, 10)));
      await tester.sendEventToBinding(mouse.move(const Offset(100, 30)));
      await tester.pump();

      // Pan has started on Message #0; exactly 1 message should be preview-selected!
      expect(selectionController.count, equals(1));
      expect(selectionController.isSelected(0), isTrue);

      await tester.sendEventToBinding(mouse.up());
      await tester.pump();

      // After release, Message #0 is committed into selection
      expect(selectionController.selectedIds, equals({0}));
      expect(selectionController.count, equals(1));
    });

    testWidgets('desktop pan to second message and back adjusts selection', (
      tester,
    ) async {
      final messages = List.generate(10, _msg);
      final ds = _LoadedSource(messages);
      final scrollController = ChatScrollController();
      final selectionController = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(() {
        scrollController.dispose();
        selectionController.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: ChatScrollView(
                dataSource: ds,
                controller: scrollController,
                selectionController: selectionController,
                messageBuilder: (context, id, msg, status, run) =>
                    SizedBox(height: 50, child: Text('Message #$id')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      // Down on Message #0
      await tester.sendEventToBinding(mouse.down(const Offset(100, 10)));
      // Move 20px within Message #0
      await tester.sendEventToBinding(mouse.move(const Offset(100, 30)));
      await tester.pump();
      expect(selectionController.count, equals(1));
      expect(selectionController.isSelected(0), isTrue);

      // Move into Message #1 (y = 70)
      await tester.sendEventToBinding(mouse.move(const Offset(100, 70)));
      await tester.pump();
      expect(selectionController.count, equals(2));
      expect(selectionController.isSelected(0), isTrue);
      expect(selectionController.isSelected(1), isTrue);

      // Move back into Message #0 (y = 35)
      await tester.sendEventToBinding(mouse.move(const Offset(100, 35)));
      await tester.pump();
      expect(selectionController.count, equals(1));
      expect(selectionController.isSelected(0), isTrue);
      expect(selectionController.isSelected(1), isFalse);

      // Move back to start within slop (y = 12)
      await tester.sendEventToBinding(mouse.move(const Offset(100, 12)));
      await tester.pump();
      expect(selectionController.count, equals(0));

      // Move back down past slop (y = 30)
      await tester.sendEventToBinding(mouse.move(const Offset(100, 30)));
      await tester.pump();
      expect(selectionController.count, equals(1));
      expect(selectionController.isSelected(0), isTrue);

      await tester.sendEventToBinding(mouse.up());
      await tester.pump();
      expect(selectionController.selectedIds, equals({0}));
    });

    testWidgets(
      'desktop pan over 1 of 2 selected messages deselects it distinctly',
      (tester) async {
        final messages = List.generate(10, _msg);
        final ds = _LoadedSource(messages);
        final scrollController = ChatScrollController();
        final selectionController = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(() {
          scrollController.dispose();
          selectionController.dispose();
        });

        // Initially messages 0 and 1 are selected
        selectionController.replaceSelectedIds({0, 1});

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500,
                height: 500,
                child: ChatScrollView(
                  dataSource: ds,
                  controller: scrollController,
                  selectionController: selectionController,
                  messageBuilder: (context, id, msg, status, run) =>
                      SizedBox(height: 50, child: Text('Message #$id')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(selectionController.count, equals(2));

        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        // Pan starts on Message #1 (y = 60, height 50 from 50 to 100)
        await tester.sendEventToBinding(mouse.down(const Offset(100, 60)));
        await tester.sendEventToBinding(mouse.move(const Offset(100, 80)));
        await tester.pump();

        // Message #1 should preview-deselect! Message #0 remains selected!
        expect(selectionController.isSelected(1), isFalse);
        expect(selectionController.isSelected(0), isTrue);
        expect(selectionController.count, equals(1));

        // Move up into Message #0 (y = 30) -> both are preview-deselected
        await tester.sendEventToBinding(mouse.move(const Offset(100, 30)));
        await tester.pump();
        expect(selectionController.isSelected(1), isFalse);
        expect(selectionController.isSelected(0), isFalse);
        expect(selectionController.count, equals(0));

        // Move back down into Message #1 (y = 80) -> Message #0 restored to selected!
        await tester.sendEventToBinding(mouse.move(const Offset(100, 80)));
        await tester.pump();
        expect(selectionController.isSelected(1), isFalse);
        expect(selectionController.isSelected(0), isTrue);
        expect(selectionController.count, equals(1));

        // Release -> Message #1 is deselected, Message #0 stays selected
        await tester.sendEventToBinding(mouse.up());
        await tester.pump();
        expect(selectionController.selectedIds, equals({0}));
      },
    );

    testWidgets(
      'desktop pan deselects 2 messages and panning back re-selects both even with horizontal mouse drift',
      (tester) async {
        final messages = List.generate(10, _msg);
        final ds = _LoadedSource(messages);
        final scrollController = ChatScrollController();
        final selectionController = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(() {
          scrollController.dispose();
          selectionController.dispose();
        });

        // Initially messages 0 and 1 are selected
        selectionController.replaceSelectedIds({0, 1});

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500,
                height: 500,
                child: ChatScrollView(
                  dataSource: ds,
                  controller: scrollController,
                  selectionController: selectionController,
                  messageBuilder: (context, id, msg, status, run) =>
                      SizedBox(height: 50, child: Text('Message #$id')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(selectionController.count, equals(2));

        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        // Press on Message #0 at (100, 20)
        await tester.sendEventToBinding(mouse.down(const Offset(100, 20)));
        // Pan down to Message #1 with horizontal drift (120, 70)
        await tester.sendEventToBinding(mouse.move(const Offset(120, 70)));
        await tester.pump();

        // Both messages should be preview-deselected
        expect(selectionController.isSelected(0), isFalse);
        expect(selectionController.isSelected(1), isFalse);
        expect(selectionController.count, equals(0));

        // Pan back to Message #0 with horizontal drift (120, 20)
        await tester.sendEventToBinding(mouse.move(const Offset(120, 20)));
        await tester.pump();

        // Both messages should be re-selected!
        expect(selectionController.isSelected(0), isTrue);
        expect(selectionController.isSelected(1), isTrue);
        expect(selectionController.count, equals(2));

        // Release -> both remain selected
        await tester.sendEventToBinding(mouse.up());
        await tester.pump();
        expect(selectionController.selectedIds, equals({0, 1}));
      },
    );

    testWidgets(
      'Escape key cancels selection via ChatKeyboardShortcuts even when composer has focus',
      (tester) async {
        final messages = List.generate(10, _msg);
        final ds = _LoadedSource(messages);
        final scrollController = ChatScrollController();
        final selectionController = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        final composerFocus = FocusNode();
        addTearDown(() {
          scrollController.dispose();
          selectionController.dispose();
          composerFocus.dispose();
        });

        selectionController.replaceSelectedIds({0, 1});

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: ChatKeyboardShortcuts(
                      controller: scrollController,
                      selectionController: selectionController,
                      preserveExternalFocus: true,
                      child: ChatScrollView(
                        dataSource: ds,
                        controller: scrollController,
                        selectionController: selectionController,
                        messageBuilder: (context, id, msg, status, run) =>
                            SizedBox(height: 50, child: Text('Message #$id')),
                      ),
                    ),
                  ),
                  TextField(focusNode: composerFocus, autofocus: true),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(selectionController.isSelectionMode, isTrue);
        expect(composerFocus.hasFocus, isTrue);

        // Send Escape key
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        // Selection must be cancelled!
        expect(selectionController.isSelectionMode, isFalse);
        expect(selectionController.selectedIds, isEmpty);
      },
    );
  });
}
