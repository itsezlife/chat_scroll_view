import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kPressTimeout;
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

String _tallBody(int id) => 'Line $id\n' * 40;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'text selection edge drag autoscrolls the anchor viewport toward older',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        const count = 24;
        final dataSource = _LoadedSource([
          for (var i = 0; i < count; i++) _msg(i),
        ]);
        final controller = ChatScrollController()..jumpTo(count - 1);
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        for (var i = 0; i < count; i++) {
          selection.putBody(i, Markdown.fromString(_tallBody(i)));
        }

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

        selection.startSelection(count - 1);
        await tester.pumpAndSettle();

        // Leave room above the subject so the flush gate is not already closed.
        controller.scrollBy(-320);
        await tester.pumpAndSettle();

        final md = find.byKey(const ValueKey('md-${count - 1}'));
        expect(md, findsOneWidget);
        final start = tester.getCenter(md);
        final gesture = await tester.startGesture(start);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await tester.pump();
        await tester.pump();

        expect(selection.isTextSelectionActive, isTrue);

        final view = tester.getRect(find.byType(ChatScrollView));
        final topBand = Offset(view.center.dx, view.top + 1);
        await gesture.moveTo(topBand);
        await tester.pump();

        final originBefore = controller.anchorPixelOffset;
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          controller.anchorPixelOffset,
          isNot(originBefore),
          reason:
              'text selection edge hold must drive ChatScrollController.scrollBy',
        );
        expect(
          controller.anchorPixelOffset,
          greaterThan(originBefore),
          reason: 'top band reveals older content (positive anchor delta)',
        );

        await gesture.up();
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'ChatMarkdownAutoscroll.resolve finds the target under ChatScrollView',
    (tester) async {
      final dataSource = _LoadedSource([_msg(1)]);
      final controller = ChatScrollController();
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      selection.putBody(1, Markdown.fromString('Hello'));

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
                    ChatMarkdownBody(controller: selection, messageId: id),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scopeContext = tester.element(find.byType(MarkdownSelectionScope));
      final target = ChatMarkdownAutoscroll.resolve(
        MarkdownAutoscrollRequest(
          scopeContext: scopeContext,
          globalPosition: tester.getCenter(find.byType(MarkdownWidget)),
          config: ChatMarkdownAutoscroll.config(),
        ),
      );
      expect(target, isA<ChatMarkdownAutoscroll>());
      expect(target!.viewport, isNotNull);
      expect(target.viewport!.isUsable, isTrue);
    },
  );

  test('ChatMarkdownAutoscroll.config uses desktop absolute px/s velocity', () {
    final config = ChatMarkdownAutoscroll.config(
      policy: const ChatSelectionPolicy.desktop(),
      displayRefreshHz: 120,
    );
    expect(
      config.maxVelocity,
      ChatSelectionMetrics.textAutoScrollDesktopMaxVelocity,
    );
    expect(config.edgeZone, ChatSelectionMetrics.textAutoScrollEdgeZoneDesktop);
    expect(config.maxVelocity, lessThan(400));
  });

  test('ChatMarkdownAutoscroll.config uses mobile half-line × Hz velocity', () {
    final at60 = ChatMarkdownAutoscroll.config(
      policy: const ChatSelectionPolicy.mobile(),
      displayRefreshHz: 60,
    );
    final at120 = ChatMarkdownAutoscroll.config(
      policy: const ChatSelectionPolicy.mobile(),
      displayRefreshHz: 120,
    );
    expect(
      at60.maxVelocity,
      ChatSelectionMetrics.textAutoScrollPixelsPerFrame * 60,
    );
    expect(
      at120.maxVelocity,
      ChatSelectionMetrics.textAutoScrollPixelsPerFrame * 120,
    );
    expect(at60.edgeZone, ChatSelectionMetrics.textAutoScrollEdgeZoneMobile);
  });

  test('ChatMarkdownAutoscrollOptions override velocity and edge zone', () {
    final config = ChatMarkdownAutoscroll.config(
      options: const ChatMarkdownAutoscrollOptions(
        maxVelocity: 400,
        edgeZone: 12,
      ),
      policy: const ChatSelectionPolicy.mobile(),
      displayRefreshHz: 60,
    );
    expect(config.maxVelocity, 400);
    expect(config.edgeZone, 12);
    expect(config.enabled, isTrue);
  });

  testWidgets(
    'ChatMarkdownBody.autoscroll disabled reaches MarkdownSelectionScope',
    (tester) async {
      final dataSource = _LoadedSource([_msg(1)]);
      final controller = ChatScrollController();
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      selection.putBody(1, Markdown.fromString('Hello'));

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
                    ChatMarkdownBody(
                      controller: selection,
                      messageId: id,
                      autoscroll: ChatMarkdownAutoscrollOptions.disabled,
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scope = tester.widget<MarkdownSelectionScope>(
        find.byType(MarkdownSelectionScope),
      );
      expect(scope.autoscroll.enabled, isFalse);
    },
  );
}
