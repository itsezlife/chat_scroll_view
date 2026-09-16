import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: messages.length - 1,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatSpanFeedbackPainter? painterOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(ChatTapHighlight),
        matching: find.byType(CustomPaint),
      ),
    );
    return switch (paint.foregroundPainter) {
      final ChatSpanFeedbackPainter painter => painter,
      _ => null,
    };
  }

  group('ChatTapHighlight — press-lifecycle seam', () {
    test('inkColorFromLabel dilutes label alpha without changing RGB', () {
      const label = Color(0xFFE53935);
      final ink = ChatTapHighlight.inkColorFromLabel(label);
      expect(ink.r, label.r);
      expect(ink.g, label.g);
      expect(ink.b, label.b);
      expect(ink.a, closeTo(ChatTapHighlight.labelInkAlpha, 1e-6));
      expect(ink, isNot(label));
    });

    testWidgets('padding does not inflate layout size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatTapHighlight(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 40, height: 12, child: Text('X')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final highlightSize = tester.getSize(find.byType(ChatTapHighlight));
      expect(highlightSize, const Size(40, 12));
    });

    testWidgets(
      'pointer down arms ink; up releases after min hold; then clears',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ChatTapHighlight(
                  color: const Color(0xFF2481CC),
                  onTap: () => taps++,
                  child: const Text('Alice'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Alice')),
        );
        await tester.pump();

        final armed = painterOf(tester);
        expect(armed, isNotNull, reason: 'ink must arm on pointer down');
        expect(armed!.feedback, isNotNull);
        expect(
          armed.feedback!.color!.a,
          closeTo(ChatTapHighlight.labelInkAlpha, 1e-6),
          reason: 'ink must be diluted label alpha, not opaque label',
        );
        expect(armed.feedback!.baseOpacity, 1.0);
        expect(armed.feedback!.rippleOpacity, 1.0);
        expect(armed.feedback!.releaseT, 1.0);
        expect(armed.feedback!.isReleasing, isFalse);

        await tester.pump(const Duration(milliseconds: 30));
        expect(painterOf(tester)?.feedback, isNotNull);
        expect(painterOf(tester)!.feedback!.releaseT, 1.0);

        await gesture.up();
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 40));
        expect(painterOf(tester)?.feedback, isNotNull);
        expect(painterOf(tester)!.feedback!.pressT, 1.0);

        await tester.pump(const Duration(milliseconds: 60));
        expect(painterOf(tester)?.feedback, isNotNull);
        expect(painterOf(tester)!.feedback!.releaseT, lessThan(1.0));

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(
          painterOf(tester)?.feedback,
          isNull,
          reason: 'feedback must clear when release completes',
        );
        expect(taps, 1);
      },
    );

    testWidgets('enabled false skips ink and onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatTapHighlight(
                enabled: false,
                onTap: () => taps++,
                child: const Text('Bob'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ChatTapHighlight));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(painterOf(tester)?.feedback, isNull);
      expect(taps, 0);
    });

    testWidgets(
      'canPerformActions false skips ink and onTap under selection scope',
      (tester) async {
        var taps = 0;
        const chrome = ChatSelectionChromeState(
          id: 1,
          modeProgress: 1,
          selectProgress: 1,
          isSelectionMode: true,
          isSelected: true,
          showsCheck: true,
          onTap: _noop,
          onLongPress: _noop,
          canPerformActions: false,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ChatSelectionStateScope(
                  state: chrome,
                  child: ChatTapHighlight(
                    onTap: () => taps++,
                    child: const Text('Dana'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(ChatTapHighlight));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(painterOf(tester)?.feedback, isNull);
        expect(taps, 0);
      },
    );

    testWidgets('pointer cancel aborts ink immediately', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatTapHighlight(onTap: () {}, child: const Text('Carol')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ChatTapHighlight)),
      );
      await tester.pump();
      expect(painterOf(tester)?.feedback, isNotNull);

      await gesture.cancel();
      await tester.pump();
      expect(
        painterOf(tester)?.feedback,
        isNull,
        reason: 'cancel must clear ink without release fade',
      );
    });

    testWidgets('move past touch slop aborts ink (scroll cancel)', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatTapHighlight(
                onTap: () => taps++,
                child: const Text('Eve'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(ChatTapHighlight));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(painterOf(tester)?.feedback, isNotNull);

      await gesture.moveBy(const Offset(0, kTouchSlop + 1));
      await tester.pump();
      expect(
        painterOf(tester)?.feedback,
        isNull,
        reason: 'past-slop must abort immediately (list pan), not fade',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('pointer move after unmount does not throw', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatTapHighlight(onTap: () {}, child: const Text('Fran')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(ChatTapHighlight));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(painterOf(tester)?.feedback, isNotNull);

      // Host remount / recycle while the pointer is still down — Listener can
      // still see moves on a disposed RenderPointerListener.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await gesture.moveBy(const Offset(0, kTouchSlop + 1));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    });
  });

  group('ChatTapHighlight — selection arena', () {
    testWidgets(
      r'mobile: null onLongPress lets long-press enter message selection ($Mobile)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          const count = 8;
          final controller = ChatScrollController()..jumpTo(count - 1);
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.mobile(),
          );
          final dataSource = _LoadedSource([
            for (var i = 0; i < count; i++) _msg(i),
          ]);
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

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
                        SizedBox(
                          height: 72,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ChatTapHighlight(
                                key: ValueKey('name-$id'),
                                onTap: () {},
                                // null onLongPress — Telegram name chrome
                                // passes long-press through to message selection.
                                child: Text('name-$id'),
                              ),
                              Text('body-$id'),
                            ],
                          ),
                        ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          const originId = count - 1;
          await tester.longPress(find.byKey(const ValueKey('name-$originId')));
          await tester.pumpAndSettle();

          expect(selection.isSelectionMode, isTrue);
          expect(selection.isSelected(originId), isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      r'mobile: onLongPress absorbs and does not enter message selection ($Mobile)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          const count = 8;
          var longPresses = 0;
          final controller = ChatScrollController()..jumpTo(count - 1);
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.mobile(),
          );
          final dataSource = _LoadedSource([
            for (var i = 0; i < count; i++) _msg(i),
          ]);
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

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
                        SizedBox(
                          height: 72,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ChatTapHighlight(
                                key: ValueKey('name-$id'),
                                onTap: () {},
                                onLongPress: () => longPresses++,
                                child: Text('name-$id'),
                              ),
                              Text('body-$id'),
                            ],
                          ),
                        ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          const originId = count - 1;
          final center = tester.getCenter(
            find.byKey(const ValueKey('name-$originId')),
          );
          final gesture = await tester.startGesture(center);
          await tester.pump(kLongPressTimeout + kPressTimeout);
          await gesture.up();
          await tester.pumpAndSettle();

          expect(longPresses, 1);
          expect(selection.isSelectionMode, isFalse);
          expect(selection.selectedIds, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      r'desktop: press-then-pan on highlight does not drag-select ($Desktop)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          const count = 8;
          final controller = ChatScrollController()..jumpTo(count - 1);
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.desktop(),
          );
          final dataSource = _LoadedSource([
            for (var i = 0; i < count; i++) _msg(i),
          ]);
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
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
                          height: 72,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ChatTapHighlight(
                                key: ValueKey('name-$id'),
                                onTap: () {},
                                child: Text('name-$id'),
                              ),
                              Text('body-$id'),
                            ],
                          ),
                        ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          const originId = count - 1;
          final nameCenter = tester.getCenter(
            find.byKey(const ValueKey('name-$originId')),
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: nameCenter);
          await tester.pump();

          // Hold (desktop “long-press”), then pan across rows — must not
          // contribute pointer updates to viewport message drag-select.
          await mouse.down(nameCenter);
          await tester.pump(const Duration(milliseconds: 600));
          await mouse.moveBy(const Offset(0, -160));
          await tester.pump();

          expect(
            selection.hasDragSelection,
            isFalse,
            reason: 'highlight press must absorb desktop message pan',
          );
          expect(selection.isSelectionMode, isFalse);
          expect(selection.selectedIds, isEmpty);

          await mouse.up();
          await tester.pump();
          expect(selection.selectedIds, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}

void _noop() {}
