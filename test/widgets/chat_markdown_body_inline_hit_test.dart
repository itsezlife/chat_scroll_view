import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Global point over glyph ink of [messageId] (not empty max-width gutter).
Offset _glyphPointOnBody(
  ChatSelectionController selection,
  int messageId, {
  int endOffset = 1,
}) {
  final surface = selection.surfaceFor(messageId)!;
  final boxes = surface.localBoxesForRange(0, 0, endOffset);
  return (surface as RenderBox).localToGlobal(boxes.first.center);
}

/// Red-capable loop: inline link/code chrome via ChatMarkdownBody (the real
/// host path), not bare MarkdownWidget harnesses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpBody(
    WidgetTester tester, {
    required ChatSelectionController selection,
    required ChatDataSource dataSource,
    required ChatScrollController controller,
    VoidCallback? onIdle,
  }) async {
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
              onIdleMessageTap: onIdle == null
                  ? null
                  : (request) => onIdle(),
              messageBuilder: (context, id, message, status, runLayout) =>
                  Container(
                    // Tall enough for long fenced code + mobile COPY CODE bar.
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
  }

  testWidgets(
    'ChatMarkdownBody idle: tap link activates without idle message tap',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final linkTaps = <(int, String, String)>[];
        final idleTaps = <int>[];
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
          onInteraction: (i) {
            if (i case ChatLinkActivated(
              :final messageId,
              :final title,
              :final url,
              gesture: ChatInlineGesture.tap,
            )) {
              linkTaps.add((messageId, title, url));
            }
          },
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(
          1,
          Markdown.fromString('[Auto Docs](https://auto.com)'),
        );

        await pumpBody(
          tester,
          selection: selection,
          dataSource: dataSource,
          controller: controller,
          onIdle: () => idleTaps.add(1),
        );

        final linkPoint = _glyphPointOnBody(selection, 1, endOffset: 9);
        await tester.tapAt(linkPoint);
        await tester.pumpAndSettle();

        expect(
          linkTaps,
          <(int, String, String)>[(1, 'Auto Docs', 'https://auto.com')],
          reason: 'ChatMarkdownBody must deliver link taps on idle mobile',
        );
        expect(idleTaps, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('ChatMarkdownBody idle: tap mobile code bottom bar copies code', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final dataSource = _LoadedSource([_msg(1)]);
      final controller = ChatScrollController();
      final codeTaps = <(int, String)>[];
      final selection = ChatSelectionController(
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
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      final clipboard = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') clipboard.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      // Longer than mobileCodeCopyBarThreshold (75) so the bottom bar mounts.
      final longCode = 'a' * 80;
      selection.putBody(1, Markdown.fromString('```\n$longCode\n```'));

      await pumpBody(
        tester,
        selection: selection,
        dataSource: dataSource,
        controller: controller,
      );

      final md = find.byType(MarkdownWidget);
      final size = tester.getSize(md);
      final origin = tester.getTopLeft(md);
      // Mid-height of the mobile COPY CODE bar (not a clipped mid-body tap).
      final bottom =
          origin +
          Offset(
            40,
            size.height - ChatCodeBlockPainter.mobileBottomBarHeight / 2,
          );
      expect(
        selection.surfaceFor(1)?.isLinkAtGlobal(bottom),
        isTrue,
        reason: 'tap point must land on painter-owned COPY CODE chrome',
      );
      await tester.tapAt(bottom);
      await tester.pumpAndSettle();

      expect(
        codeTaps,
        isNotEmpty,
        reason: 'ChatMarkdownBody must click-to-copy mobile code bottom bar',
      );
      expect(clipboard, isNotEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'ChatMarkdownBody mobile: COPY CODE suppressed while message is selected',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final codeTaps = <(int, String)>[];
        final selection = ChatSelectionController(
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
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        final longCode = 'b' * 80;
        selection.putBody(1, Markdown.fromString('```\n$longCode\n```'));
        selection.startSelection(1);

        await pumpBody(
          tester,
          selection: selection,
          dataSource: dataSource,
          controller: controller,
        );
        expect(selection.isSelected(1), isTrue);

        final md = find.byType(MarkdownWidget);
        final size = tester.getSize(md);
        final origin = tester.getTopLeft(md);
        final bottom = origin +
            Offset(
              40,
              size.height - ChatCodeBlockPainter.mobileBottomBarHeight / 2,
            );
        expect(
          selection.surfaceFor(1)?.isLinkAtGlobal(bottom),
          isTrue,
          reason: 'tap must land on COPY CODE chrome',
        );
        await tester.tapAt(bottom);
        await tester.pumpAndSettle();

        expect(
          codeTaps,
          isEmpty,
          reason: 'COPY CODE must not fire under mobile message selection',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'ChatMarkdownBody mobile: COPY CODE suppressed while text is selected',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final codeTaps = <(int, String)>[];
        final selection = ChatSelectionController(
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
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        final longCode = 'c' * 80;
        selection.putBody(1, Markdown.fromString('```\n$longCode\n```'));
        selection.startSelection(1);
        expect(selection.enterTextSelection(1), isTrue);

        await pumpBody(
          tester,
          selection: selection,
          dataSource: dataSource,
          controller: controller,
        );
        expect(selection.isTextSelectionActive, isTrue);

        final md = find.byType(MarkdownWidget);
        final size = tester.getSize(md);
        final origin = tester.getTopLeft(md);
        final bottom = origin +
            Offset(
              40,
              size.height - ChatCodeBlockPainter.mobileBottomBarHeight / 2,
            );
        expect(
          selection.surfaceFor(1)?.isLinkAtGlobal(bottom),
          isTrue,
          reason: 'tap must land on COPY CODE chrome',
        );
        final hit = selection.resolveInlineHit(1, bottom);
        expect(hit, isA<ChatInlineHit$Code>());
        expect(
          selection.handleInlineHit(hit!),
          isFalse,
          reason: 'facade must suppress COPY chrome while text selection active',
        );
        expect(codeTaps, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'ChatMarkdownBody mobile: inline code suppressed while message is selected',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final codeTaps = <(int, String)>[];
        final selection = ChatSelectionController(
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
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('before `inline` after'));
        selection.startSelection(1);

        await pumpBody(
          tester,
          selection: selection,
          dataSource: dataSource,
          controller: controller,
        );

        // Mid-body tap lands on the monospace span in this short line.
        final md = find.byType(MarkdownWidget);
        final center = tester.getCenter(md);
        final hit = selection.resolveInlineHit(1, center);
        expect(hit, isA<ChatInlineHit$Code>());
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(
          codeTaps,
          isEmpty,
          reason: 'inline code must not copy under mobile message selection',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('ChatMarkdownBody desktop idle: mouse click on link activates', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final dataSource = _LoadedSource([_msg(1)]);
      final controller = ChatScrollController();
      final linkTaps = <(int, String, String)>[];
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
        onInteraction: (i) {
          if (i case ChatLinkActivated(
            :final messageId,
            :final title,
            :final url,
            gesture: ChatInlineGesture.tap,
          )) {
            linkTaps.add((messageId, title, url));
          }
        },
      );
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      selection.putBody(
        1,
        Markdown.fromString('[Auto Docs](https://auto.com)'),
      );

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
                    Container(
                      height: 120,
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

      final linkPoint = _glyphPointOnBody(selection, 1, endOffset: 9);
      final gesture = await tester.startGesture(
        linkPoint,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(linkTaps, <(int, String, String)>[
        (1, 'Auto Docs', 'https://auto.com'),
      ], reason: 'desktop mouse click on link via ChatMarkdownBody');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'ChatMarkdownBody desktop idle: mouse click on code header copies',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final codeTaps = <(int, String)>[];
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
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
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        final clipboard = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') clipboard.add(call);
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );

        selection.putBody(
          1,
          Markdown.fromString('```dart\nvoid main() {}\n```'),
        );

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
                      Container(
                        height: 160,
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

        final mdTopLeft = tester.getTopLeft(find.byType(MarkdownWidget));
        final gesture = await tester.startGesture(
          mdTopLeft + const Offset(40, 10),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          codeTaps,
          isNotEmpty,
          reason: 'desktop mouse click on code header via ChatMarkdownBody',
        );
        expect(clipboard, isNotEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
