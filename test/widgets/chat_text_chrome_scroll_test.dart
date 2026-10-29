import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
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
  _LoadedSource(int count) {
    upsertMessages([for (var i = 0; i < count; i++) _msg(i)]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (final chunk in chunks.values) {
      chunk.status = ChatMessageStatus.valid;
    }
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Offset _toolbarAnchor(WidgetTester tester) => tester
    .widget<AdaptiveTextSelectionToolbar>(
      find.byType(AdaptiveTextSelectionToolbar),
    )
    .anchors
    .primaryAnchor;

double _selectionTop(ChatSelectionController selection) =>
    selection.markdownSelection.globalSelectionRects().first.top;

/// A point right of every body's text, so a drag there scrolls the list
/// instead of extending the selection.
Offset _emptyMargin(WidgetTester tester) =>
    tester.getTopRight(find.byType(ChatScrollView)) + const Offset(-60, 300);

/// The harness has no `Scaffold`, so no `ScrollNotificationObserver` above the
/// viewport (the viewport's own geometry notification reaches nobody), as in a
/// sheet or dialog route.
///
/// The text selection chrome follows the text when the viewport scrolls: the
/// handles ride their surfaces' layers, and the toolbar's absolute anchors are
/// recomputed per scroll (the viewport is not a `Scrollable`, so it has to
/// tell the scope itself).
void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    group('text selection chrome on scroll ($platform)', () {
      Future<(ChatSelectionController, ChatScrollController)> pumpSelected(
        WidgetTester tester,
      ) async {
        final dataSource = _LoadedSource(30);
        final controller = ChatScrollController()..jumpTo(15);
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.textOnly(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);
        for (var i = 0; i < 30; i++) {
          selection.putBody(
            i,
            Markdown.fromString('Hello selectable world $i'),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Material(
              child: SizedBox(
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

        // A word of the body nearest the viewport centre.
        final center = tester.getCenter(find.byType(ChatScrollView));
        Offset? at;
        var best = double.infinity;
        for (var i = 0; i < 30; i++) {
          final surface = selection.surfaceFor(i);
          if (surface == null) continue;
          final word = (surface as RenderBox).localToGlobal(
            surface.localBoxesForRange(0, 0, 5).first.center,
          );
          if ((word - center).distance < best) {
            best = (word - center).distance;
            at = word;
          }
        }
        await tester.longPressAt(at!);
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isTrue);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
        return (selection, controller);
      }

      testWidgets('the toolbar follows the text while the list scrolls', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final (selection, _) = await pumpSelected(tester);
          final before = _toolbarAnchor(tester);
          final textBefore = _selectionTop(selection);

          await tester.flingFrom(
            _emptyMargin(tester),
            const Offset(0, -100),
            300,
          );
          await tester.pumpAndSettle();

          final moved = _selectionTop(selection) - textBefore;
          expect(moved, lessThan(-40), reason: 'the list scrolled');
          expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
          expect(_toolbarAnchor(tester).dy, closeTo(before.dy + moved, 2));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('the toolbar tracks the text on every frame of a fling', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final (selection, _) = await pumpSelected(tester);
          final offset = _toolbarAnchor(tester).dy - _selectionTop(selection);

          await tester.flingFrom(
            _emptyMargin(tester),
            const Offset(0, -150),
            1200,
          );
          var frames = 0;
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            // Left only while the text is still in the viewport.
            if (find.byType(AdaptiveTextSelectionToolbar).evaluate().isEmpty) {
              break;
            }
            expect(
              _toolbarAnchor(tester).dy - _selectionTop(selection),
              closeTo(offset, 2),
              reason: 'frame $i: the toolbar lags the text it belongs to',
            );
            frames++;
          }
          expect(frames, greaterThan(3));
          await tester.pumpAndSettle();
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('the toolbar hides when the text scrolls out, and returns', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await pumpSelected(tester);

          for (var i = 0; i < 10; i++) {
            if (find.byType(AdaptiveTextSelectionToolbar).evaluate().isEmpty) {
              break;
            }
            await tester.flingFrom(
              _emptyMargin(tester),
              const Offset(0, -400),
              3000,
            );
            await tester.pumpAndSettle();
          }
          expect(
            find.byType(AdaptiveTextSelectionToolbar),
            findsNothing,
            reason: 'the selected text is scrolled out of the viewport',
          );

          for (var i = 0; i < 30; i++) {
            if (find
                .byType(AdaptiveTextSelectionToolbar)
                .evaluate()
                .isNotEmpty) {
              break;
            }
            await tester.dragFrom(_emptyMargin(tester), const Offset(0, 100));
            await tester.pumpAndSettle();
          }
          expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });
  }
}
