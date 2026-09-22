import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        PointerDeviceKind,
        kLongPressTimeout,
        kPressTimeout,
        kSecondaryMouseButton;
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

/// Global point over the first glyph box of [messageId]'s body (not the
/// empty max-width gutter of a wide MarkdownWidget).
Offset _glyphPointOnBody(
  ChatSelectionController selection,
  int messageId, {
  int endOffset = 1,
}) {
  final surface = selection.surfaceFor(messageId);
  assert(surface != null, 'expected mounted surface for $messageId');
  final boxes = surface!.localBoxesForRange(0, 0, endOffset);
  assert(boxes.isNotEmpty, 'expected glyph boxes for $messageId');
  return (surface as RenderBox).localToGlobal(boxes.first.center);
}

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group(r'Seam S — $Mobile policy wiring', () {
    test('enter sets subject, range, and preserves membership', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(selection.dispose);

      expect(selection.selectionPolicy, isA<ChatSelectionPolicy$Mobile>());

      selection.putBody(1, Markdown.fromString('Hello selectable world'));
      selection
        ..startSelection(1)
        ..toggle(2);

      expect(selection.selectedIds, <int>{1, 2});
      expect(selection.enterTextSelection(1), isTrue);
      expect(selection.isTextSelectionActive, isTrue);
      expect(selection.textSelectionSubject, 1);
      final range = selection.textSelection;
      expect(range, isNotNull);
      expect(range!.isCollapsed, isFalse);
      expect(range.base.documentId, 1);
      expect(range.extent.documentId, 1);
      expect(selection.selectedIds, <int>{1, 2});
    });

    test('mobile entry requires message to be selected first per policy', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(selection.dispose);

      selection.putBody(1, Markdown.fromString('Hello selectable world'));

      // Not selected yet -> enterTextSelection must fail
      expect(selection.enterTextSelection(1), isFalse);
      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelectionSubject, isNull);
      expect(selection.textSelection, isNull);

      // Now select -> enterTextSelection succeeds
      selection.startSelection(1);
      expect(selection.enterTextSelection(1), isTrue);
      expect(selection.isTextSelectionActive, isTrue);
      expect(selection.textSelectionSubject, 1);
    });

    test('mobile entry preserves multi-message selection membership', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(selection.dispose);

      selection.putBody(2, Markdown.fromString('Target subject message'));
      selection
        ..startSelection(1)
        ..toggle(2)
        ..toggle(3);

      expect(selection.selectedIds, <int>{1, 2, 3});
      expect(selection.enterTextSelection(2), isTrue);
      expect(selection.textSelectionSubject, 2);
      expect(selection.selectedIds, <int>{1, 2, 3});
    });

    test(
      'retargeting text selection across selected messages moves subject and preserves membership',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('First message body'));
        selection.putBody(2, Markdown.fromString('Second message body'));

        selection
          ..startSelection(1)
          ..toggle(2);

        expect(selection.selectedIds, <int>{1, 2});

        // Enter on 1
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.selectedIds, <int>{1, 2});

        // Retarget to 2 (also selected)
        expect(selection.enterTextSelection(2), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 2);
        expect(selection.selectedIds, <int>{1, 2});

        // Dismiss keeps both messages selected
        selection.clearTextSelection();
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1, 2});
      },
    );

    test(
      'selectAllText under multi-message membership expands only the subject body',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        const body1 = 'First message full body text';
        const body2 = 'Second message full body text';
        selection.putBody(1, Markdown.fromString(body1));
        selection.putBody(2, Markdown.fromString(body2));

        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.textSelectionSubject, 1);

        // Sibling mounts call putDocument and can re-expand the registry after
        // adopt collapses to the subject — Select All must still stay on-body.
        selection.markdownSelection.putDocument(
          2,
          Markdown.fromString(body2),
          order: 1,
        );

        expect(selection.selectAllText(), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(selection.textSelection!.base.documentId, 1);
        expect(selection.textSelection!.extent.documentId, 1);
        expect(selection.markdownSelection.getText(), body1);
        expect(selection.markdownSelection.documents.map((d) => d.id), <Object>[
          1,
        ]);
      },
    );

    test(
      'starting selection on an unselected message dismisses active text selection',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('First message body'));
        selection.putBody(2, Markdown.fromString('Second message body'));

        selection
          ..startSelection(1)
          ..toggle(2);

        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        // Long-press or tap unselected message 3 starts message selection and dismisses text
        selection.startSelection(3);
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1, 2, 3});
      },
    );

    test(
      'dismiss text via clearTextSelection clears range and keeps subject in message selection',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.enterTextSelection(1), isTrue);

        selection.clearTextSelection();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);
      },
    );

    test(
      'dismiss text via clearing markdown selection clears range and keeps subject in message selection',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.enterTextSelection(1), isTrue);

        // Simulate range clear (e.g. tap dismiss on markdown surface)
        selection.markdownSelection.clear();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);
      },
    );

    test(
      'dismiss text via collapsed markdown selection range clears range and keeps subject in message selection',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.enterTextSelection(1), isTrue);

        // Simulate a tap or handle collapse on markdown surface
        selection.markdownSelection.selection = const MarkdownSelection(
          base: MarkdownPosition(documentId: 1, blockIndex: 0, offset: 3),
          extent: MarkdownPosition(documentId: 1, blockIndex: 0, offset: 3),
        );

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);
      },
    );

    testWidgets(
      'word selection miss cleans up text selection and leaves message selection intact',
      (tester) async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        final model = Markdown.fromString('Hello selectable world');
        selection.putBody(1, model);
        selection.startSelection(1);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkdownWidget(
                markdown: model,
                documentId: 1,
                controller: selection.markdownSelection,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Enter text selection with globalOffset pointing far outside the widget
        final result = selection.enterTextSelection(
          1,
          globalOffset: const Offset(9999, 9999),
        );
        expect(result, isTrue);

        await tester.pumpAndSettle();

        // Word selection missed: text selection must be disarmed cleanly
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, <int>{1});
        expect(selection.isSelectionMode, isTrue);
      },
    );

    test('clearing message selection via clear() clears text selection', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(selection.dispose);

      selection.putBody(1, Markdown.fromString('Hello selectable world'));
      selection.startSelection(1);
      expect(selection.enterTextSelection(1), isTrue);

      selection.clear();

      expect(selection.isSelectionMode, isFalse);
      expect(selection.selectedIds, isEmpty);
      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelectionSubject, isNull);
      expect(selection.textSelection, isNull);
    });

    test('emptying message selection via toggle() clears text selection', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(selection.dispose);

      selection.putBody(1, Markdown.fromString('Hello selectable world'));
      selection.startSelection(1);
      expect(selection.enterTextSelection(1), isTrue);

      selection.toggle(1);

      expect(selection.isSelectionMode, isFalse);
      expect(selection.selectedIds, isEmpty);
      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelectionSubject, isNull);
      expect(selection.textSelection, isNull);
    });

    test('replacing selected ids without subject clears text selection', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(selection.dispose);

      selection.putBody(1, Markdown.fromString('Hello selectable world'));
      selection.startSelection(1);
      expect(selection.enterTextSelection(1), isTrue);

      selection.replaceSelectedIds(<int>{2});

      expect(selection.selectedIds, <int>{2});
      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelectionSubject, isNull);
    });

    test(
      'reapplying selection-allowed that drops subject clears text selection',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        selection.startSelection(1);
        expect(selection.enterTextSelection(1), isTrue);

        selection.selectionAllowed = (id) =>
            id == 1 ? ChatSelectionAllowed.none : ChatSelectionAllowed.full;

        expect(selection.selectedIds, isEmpty);
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
      },
    );

    testWidgets(
      'engine-internal routing: selected body text routes to text selection',
      (tester) async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        selection.startSelection(1);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: selection,
                builder: (context, _) => Center(
                  child: MarkdownWidget(
                    markdown: selection.bodyOf(1)!,
                    documentId: selection.exposesSelectionSurface(1) ? 1 : null,
                    controller: selection.exposesSelectionSurface(1)
                        ? selection.markdownSelection
                        : null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final global = tester.getCenter(find.byType(MarkdownWidget));
        expect(selection.shouldRouteLongPressToText(1, global), isTrue);
        expect(selection.routeLongPressToTextSelection(1, global), isTrue);

        // Yield predicate only — programmatic enter remains for hosts/tests.
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.enterTextSelection(1, globalOffset: global), isTrue);

        await tester.pump();
        await tester.pump();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        final range = selection.textSelection;
        expect(range, isNotNull);
        expect(range!.isCollapsed, isFalse);
        expect(range.base.documentId, 1);
        expect(selection.selectedIds, <int>{1});
      },
    );

    testWidgets(
      'engine-internal routing: retargets to another selected message body and keeps membership',
      (tester) async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('First message content'));
        selection.putBody(2, Markdown.fromString('Second message content'));
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.selectedIds, <int>{1, 2});

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: selection,
                builder: (context, _) => Column(
                  children: [
                    MarkdownWidget(
                      key: const ValueKey('md-1'),
                      markdown: selection.bodyOf(1)!,
                      documentId: selection.exposesSelectionSurface(1)
                          ? 1
                          : null,
                      controller: selection.exposesSelectionSurface(1)
                          ? selection.markdownSelection
                          : null,
                    ),
                    MarkdownWidget(
                      key: const ValueKey('md-2'),
                      markdown: selection.bodyOf(2)!,
                      documentId: selection.exposesSelectionSurface(2)
                          ? 2
                          : null,
                      controller: selection.exposesSelectionSurface(2)
                          ? selection.markdownSelection
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Yield predicate + programmatic enter (gesture adopt is issue 04).
        final global1 = tester.getCenter(find.byKey(const ValueKey('md-1')));
        expect(selection.shouldRouteLongPressToText(1, global1), isTrue);
        expect(selection.enterTextSelection(1, globalOffset: global1), isTrue);
        await tester.pump();
        await tester.pump();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.selectedIds, <int>{1, 2});
        // Selected sibling mounts a surface so continuous retarget can yield.
        expect(selection.exposesSelectionSurface(2), isTrue);

        // Sibling body hit yields for continuous retarget (ADR 015).
        // Programmatic enterTextSelection remains for hosts / tests.
        final global2 = tester.getCenter(find.byKey(const ValueKey('md-2')));
        expect(selection.shouldRouteLongPressToText(2, global2), isTrue);
        expect(selection.enterTextSelection(2, globalOffset: global2), isTrue);
        await tester.pump();
        await tester.pump();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 2);
        expect(selection.selectedIds, <int>{1, 2});

        // Dismiss keeps both selected
        selection.clearTextSelection();
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1, 2});
      },
    );

    testWidgets(
      'engine-internal routing: unselected message body does not route to text',
      (tester) async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        expect(selection.selectedIds, isEmpty);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: selection,
                builder: (context, _) => Center(
                  child: MarkdownWidget(
                    markdown: selection.bodyOf(1)!,
                    documentId: selection.exposesSelectionSurface(1) ? 1 : null,
                    controller: selection.exposesSelectionSurface(1)
                        ? selection.markdownSelection
                        : null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final global = tester.getCenter(find.byType(MarkdownWidget));
        expect(selection.shouldRouteLongPressToText(1, global), isFalse);
        expect(selection.routeLongPressToTextSelection(1, global), isFalse);
        expect(selection.isTextSelectionActive, isFalse);
      },
    );

    testWidgets(
      'engine-internal routing: selected message padding does not route to text',
      (tester) async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        selection.startSelection(1);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: selection,
                builder: (context, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: MarkdownWidget(
                      markdown: selection.bodyOf(1)!,
                      documentId: selection.exposesSelectionSurface(1)
                          ? 1
                          : null,
                      controller: selection.exposesSelectionSurface(1)
                          ? selection.markdownSelection
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final mdRect = tester.getRect(find.byType(MarkdownWidget));
        final paddingPoint = mdRect.topLeft - const Offset(20, 20);

        expect(selection.shouldRouteLongPressToText(1, paddingPoint), isFalse);
        expect(
          selection.routeLongPressToTextSelection(1, paddingPoint),
          isFalse,
        );
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1});
      },
    );

    testWidgets(
      'span gesture starts when long-press is not text entry (idle unselected row)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Body 1'));
        selection.putBody(2, Markdown.fromString('Body 2'));

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
                      SizedBox(height: 60, child: Text('msg-$id')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // First long press on unselected message 1: must start message selection, not text
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('msg-1')),
        );
        await tester.pump(kLongPressTimeout + kPressTimeout);

        expect(selection.selectedIds, <int>{1});
        expect(selection.isTextSelectionActive, isFalse);

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets(
      'span gesture vs text entry: padding starts span, body text enters text',
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
          selection.startSelection(1);

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
                          height: 120,
                          padding: const EdgeInsets.all(40),
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

          // Case A: Long-press on padding of selected message (top-left padding area)
          final containerRect = tester.getRect(
            find.byKey(const ValueKey('container-1')),
          );
          final paddingPoint = containerRect.topLeft + const Offset(10, 10);

          final paddingGesture = await tester.startGesture(paddingPoint);
          await tester.pump(kLongPressTimeout + kPressTimeout);

          // Long press on padding does not route to text — it unselects / starts span gesture!
          expect(selection.isTextSelectionActive, isFalse);
          expect(selection.selectedIds, isEmpty);

          await paddingGesture.up();
          await tester.pump();

          // Case B: Re-select message 1, then long-press on body text
          selection.startSelection(1);
          await tester.pumpAndSettle();
          expect(selection.isSelected(1), isTrue);

          final md = find.byType(MarkdownWidget);
          final textPoint = tester.getTopLeft(md) + const Offset(24, 16);
          expect(selection.shouldRouteLongPressToText(1, textPoint), isTrue);

          final textGesture = await tester.startGesture(textPoint);
          await tester.pump(kLongPressTimeout + kPressTimeout);
          await tester.pump();
          await tester.pump();

          // Long press on text: viewport yields; per-body scope owns continuous entry.
          expect(selection.isTextSelectionActive, isTrue);
          expect(selection.textSelectionSubject, 1);
          expect(selection.textSelection, isNotNull);
          expect(selection.selectedIds, <int>{1});

          await textGesture.up();
          await tester.pump();
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    test('Copy success notifies and clears text plus message mode', () async {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
        onInteraction: (i) {
          if (i case ChatCopied(:final text)) {
            expect(text, 'Hello selectable world');
          }
        },
      );
      addTearDown(selection.dispose);

      final copied = <String>[];
      selection.addInteractionListener((i) {
        if (i case ChatCopied(:final text)) {
          copied.add(text);
        }
      });

      selection.putBody(1, Markdown.fromString('Hello selectable world'));
      selection.startSelection(1);
      expect(selection.enterTextSelection(1), isTrue);

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

      expect(await selection.copyTextSelection(), isTrue);
      expect(clipboard, isNotEmpty);
      expect(clipboard.first.arguments['text'], 'Hello selectable world');
      expect(copied, <String>['Hello selectable world']);
      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelection, isNull);
      expect(selection.textSelectionSubject, isNull);
      expect(selection.selectedIds, isEmpty);
    });

    testWidgets(
      r'idle tap dismisses text selection and keeps message selection membership intact without firing message menu ($Mobile)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Hello message 1'));
        selection.putBody(2, Markdown.fromString('Hello message 2'));

        final taps = <int>[];

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
                  onIdleMessageTap: (request) => taps.add(request.messageId),
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        key: ValueKey('container-$id'),
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Enter message selection on 1 and 2
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.selectedIds, <int>{1, 2});

        // 2. Enter text selection on message 1
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.selectedIds, <int>{1, 2});

        // 3. Idle tap on message 1 while text selection is active
        await tester.tap(find.byKey(const ValueKey('container-1')));
        await tester.pumpAndSettle();

        // Must dismiss text selection, keep both messages in message selection,
        // and NOT fire onIdleMessageTap
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelection, isNull);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);
        expect(taps, isEmpty);
      },
    );

    testWidgets(
      r'idle tap on unselected message or empty space dismisses text and preserves selected set ($Mobile)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Hello message 1'));
        selection.putBody(2, Markdown.fromString('Hello message 2'));

        final taps = <int>[];

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
                  onIdleMessageTap: (request) => taps.add(request.messageId),
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        key: ValueKey('container-$id'),
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Message 1 selected, message 2 unselected
        selection.startSelection(1);
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        // Tap unselected message 2 -> dismisses text, keeps message 1 selected, does not select 2
        await tester.tap(find.byKey(const ValueKey('container-2')));
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1});
        expect(taps, isEmpty);

        // Re-enter text selection on 1
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        // Tap empty space below messages (y=500 in 600px tall viewport)
        await tester.tapAt(const Offset(200, 500));
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1});
        expect(taps, isEmpty);
      },
    );

    testWidgets(
      r'long-press on another selected message body retargets text selection and preserves membership ($Mobile)',
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
            Markdown.fromString('First message body content'),
          );
          selection.putBody(
            2,
            Markdown.fromString('Second message body content'),
          );

          final taps = <int>[];

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
                    onIdleMessageTap: (request) => taps.add(request.messageId),
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

          // 1. Both messages selected
          selection
            ..startSelection(1)
            ..toggle(2);
          await tester.pumpAndSettle();
          expect(selection.selectedIds, <int>{1, 2});

          // 2. Enter text selection on message 1
          final md1 = find.byKey(const ValueKey('md-1'));
          final start1 = tester.getTopLeft(md1) + const Offset(24, 16);
          final gesture1 = await tester.startGesture(start1);
          await tester.pump(kLongPressTimeout + kPressTimeout);
          await tester.pump();
          await tester.pump();

          expect(selection.isTextSelectionActive, isTrue);
          expect(selection.textSelectionSubject, 1);
          expect(selection.selectedIds, <int>{1, 2});

          await gesture1.up();
          await tester.pumpAndSettle();

          // 3. Long-press on message 2 body → viewport yields; scope retargets
          // with continuous press; membership unchanged.
          final md2 = find.byKey(const ValueKey('md-2'));
          final start2 = tester.getTopLeft(md2) + const Offset(24, 16);
          expect(selection.shouldRouteLongPressToText(2, start2), isTrue);
          expect(selection.containsGlobal(2, start2), isTrue);
          final gesture2 = await tester.startGesture(start2);
          await tester.pump(kLongPressTimeout + kPressTimeout);
          await tester.pump();
          await tester.pump();

          expect(selection.isTextSelectionActive, isTrue);
          expect(selection.textSelectionSubject, 2);
          expect(selection.selectedIds, <int>{1, 2});
          expect(taps, isEmpty);

          await gesture2.up();
          await tester.pumpAndSettle();
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      r'long-press on unselected message while text is active clears text and starts message selection ($Mobile)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('First message body content'));
        selection.putBody(
          2,
          Markdown.fromString('Second message body content'),
        );

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
                      Container(
                        key: ValueKey('container-$id'),
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Message 1 selected, text active on 1; message 2 unselected
        selection.startSelection(1);
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.selectedIds, <int>{1});

        // Long-press unselected message 2
        final center2 = tester.getCenter(find.byKey(const ValueKey('md-2')));
        final gesture2 = await tester.startGesture(center2);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await gesture2.up();
        await tester.pumpAndSettle();

        // Text selection cleared, message 2 added to message selection
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.selectedIds, <int>{1, 2});
      },
    );

    testWidgets(
      r'long-press outside body text (padding) of selected message clears text and starts unselect span ($Mobile)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('First message body content'));
        selection.putBody(
          2,
          Markdown.fromString('Second message body content'),
        );

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
                      Container(
                        key: ValueKey('container-$id'),
                        height: 100,
                        padding: const EdgeInsets.all(30),
                        color: Colors.white,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Both messages selected; text active on 1
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        // Long press on padding of message 2 (top-left of container-2 + (5, 5))
        final container2 = tester.getRect(
          find.byKey(const ValueKey('container-2')),
        );
        final paddingPoint = container2.topLeft + const Offset(5, 5);
        final gesture = await tester.startGesture(paddingPoint);
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await gesture.up();
        await tester.pumpAndSettle();

        // Text selection cleared on 1, message 2 unselected
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1});
      },
    );

    testWidgets(
      r'message menu is mutually exclusive with message selection and nested text ($Mobile)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Message 1'));
        selection.putBody(2, Markdown.fromString('Message 2'));

        final taps = <int>[];

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
                  onIdleMessageTap: (request) => taps.add(request.messageId),
                  messageBuilder: (context, id, message, status, runLayout) =>
                      SizedBox(height: 60, child: Text('msg-$id')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Idle state: tap fires onIdleMessageTap (message menu)
        await tester.tap(find.text('msg-1'));
        await tester.pumpAndSettle();
        expect(taps, <int>[1]);
        taps.clear();

        // 2. Message selection mode: tap toggles message, does NOT fire onIdleMessageTap
        selection.startSelection(1);
        await tester.tap(find.text('msg-2'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(selection.selectedIds, <int>{1, 2});
        expect(taps, isEmpty);

        // 3. Text selection active: tap dismisses text, does NOT fire onIdleMessageTap
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        await tester.tap(find.text('msg-1'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1, 2});
        expect(taps, isEmpty);
      },
    );
  });

  group(r'Seam S — $Desktop policy wiring', () {
    test('enter without membership sets subject and range', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(selection.dispose);

      expect(selection.selectionPolicy, isA<ChatSelectionPolicy$Desktop>());

      selection.putBody(7, Markdown.fromString('Desktop range text'));
      expect(selection.enterTextSelection(7), isTrue);
      expect(selection.isTextSelectionActive, isTrue);
      expect(selection.textSelectionSubject, 7);
      expect(selection.textSelection, isNotNull);
      expect(selection.textSelection!.isCollapsed, isFalse);
      expect(selection.selectedIds, isEmpty);
    });

    testWidgets(
      'enter with globalOffset schedules word selection without membership',
      (tester) async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        expect(selection.selectionPolicy, isA<ChatSelectionPolicy$Desktop>());

        final model = Markdown.fromString('Desktop word text');
        selection.putBody(1, model);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: MarkdownWidget(
                  markdown: model,
                  documentId: 1,
                  controller: selection.markdownSelection,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final target = tester.getCenter(find.byType(MarkdownWidget));
        expect(selection.enterTextSelection(1, globalOffset: target), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.selectedIds, isEmpty);

        await tester.pump();
        await tester.pump();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelection, isNotNull);
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(selection.selectedIds, isEmpty);
      },
    );

    test('exposesSelectionSurface follows desktop exclusive policy', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(selection.dispose);

      selection.putBody(1, Markdown.fromString('Message 1'));
      selection.putBody(2, Markdown.fromString('Message 2'));

      // 1. Inactive with empty message selection: all registered bodies expose surface
      expect(selection.exposesSelectionSurface(1), isTrue);
      expect(selection.exposesSelectionSurface(2), isTrue);
      expect(selection.exposesSelectionSurface(3), isFalse); // not registered

      // 2. Active text selection on message 1: only subject 1 exposes surface
      expect(selection.enterTextSelection(1), isTrue);
      expect(selection.exposesSelectionSurface(1), isTrue);
      expect(selection.exposesSelectionSurface(2), isFalse);

      // 3. Clear text, enter message selection: surfaces stay mounted so
      // inline link/code/chrome hits remain resolvable (desktop/web).
      selection.clearTextSelection();
      selection.startSelection(1);
      expect(selection.exposesSelectionSurface(1), isTrue);
      expect(selection.exposesSelectionSurface(2), isTrue);
    });

    test('enter while messages are selected clears membership (exclusive)', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(selection.dispose);

      expect(selection.selectionPolicy, isA<ChatSelectionPolicy$Desktop>());

      selection.putBody(3, Markdown.fromString('Exclusive text'));
      selection
        ..startSelection(1)
        ..toggle(2);
      expect(selection.selectedIds, <int>{1, 2});
      expect(selection.isSelectionMode, isTrue);

      expect(selection.enterTextSelection(3), isTrue);
      expect(selection.isTextSelectionActive, isTrue);
      expect(selection.textSelectionSubject, 3);
      expect(selection.selectedIds, isEmpty);
      expect(selection.isSelectionMode, isFalse);
    });

    testWidgets(
      'enter with globalOffset while messages are selected clears membership upon word hit',
      (tester) async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        final model = Markdown.fromString('Word target body');
        selection.putBody(5, model);
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.selectedIds, <int>{1, 2});

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: MarkdownWidget(
                  markdown: model,
                  documentId: 5,
                  controller: selection.markdownSelection,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final target = tester.getCenter(find.byType(MarkdownWidget));
        expect(selection.enterTextSelection(5, globalOffset: target), isTrue);

        await tester.pump();
        await tester.pump();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 5);
        expect(selection.textSelection, isNotNull);
        expect(selection.selectedIds, isEmpty);
        expect(selection.isSelectionMode, isFalse);
      },
    );

    testWidgets(
      r'word selection hit miss rolls back cleanly and preserves message selection on $Desktop',
      (tester) async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        final model = Markdown.fromString('Word target body');
        selection.putBody(5, model);
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.selectedIds, <int>{1, 2});

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: MarkdownWidget(
                  markdown: model,
                  documentId: 5,
                  controller: selection.markdownSelection,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Point far outside the markdown widget
        expect(
          selection.enterTextSelection(
            5,
            globalOffset: const Offset(9999, 9999),
          ),
          isTrue,
        );

        await tester.pump();
        await tester.pump();

        // Word miss disarmed text without clearing pre-existing message selection
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);
      },
    );

    test(
      'starting message selection while text is active clears text selection (exclusive)',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Text body'));
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);

        selection.startSelection(2);
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, <int>{2});
        expect(selection.isSelectionMode, isTrue);
      },
    );

    test(
      'toggling message selection while text is active clears text selection (exclusive)',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Text body'));
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        selection.toggle(2);
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.selectedIds, <int>{2});
      },
    );

    test(
      'replacing selected ids while text is active clears text selection (exclusive)',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Text body'));
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        selection.replaceSelectedIds(<int>{3, 4});
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.selectedIds, <int>{3, 4});
      },
    );

    test(
      r'enter failure rolls back cleanly without altering membership on $Desktop',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection
          ..startSelection(1)
          ..toggle(2);

        // Body 999 has not been registered.
        expect(selection.enterTextSelection(999), isFalse);
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.selectedIds, <int>{1, 2});
      },
    );

    test('long-press does not route under desktop policy', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(selection.dispose);

      expect(selection.selectionPolicy.routesLongPressToTextSelection, isFalse);

      selection.putBody(1, Markdown.fromString('Hello selectable world'));
      expect(selection.shouldRouteLongPressToText(1, Offset.zero), isFalse);
      expect(selection.routeLongPressToTextSelection(1, Offset.zero), isFalse);
      expect(selection.isTextSelectionActive, isFalse);
    });

    test(
      'Copy success writes clipboard, keeps text range active, and notifies observers',
      () async {
        final copiedFromCallback = <String>[];
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
          onInteraction: (i) {
            if (i case ChatCopied(:final text)) {
              copiedFromCallback.add(text);
            }
          },
        );
        addTearDown(selection.dispose);

        final copiedFromListener = <String>[];
        selection.addInteractionListener((i) {
          if (i case ChatCopied(:final text)) {
            copiedFromListener.add(text);
          }
        });

        selection.putBody(1, Markdown.fromString('Hello desktop world'));
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        final rangeBeforeCopy = selection.textSelection;
        expect(rangeBeforeCopy, isNotNull);

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

        expect(await selection.copyTextSelection(), isTrue);

        // 1. Clipboard data was written
        expect(clipboard, isNotEmpty);
        expect(clipboard.first.arguments['text'], 'Hello desktop world');

        // 2. Observers were notified
        expect(copiedFromCallback, <String>['Hello desktop world']);
        expect(copiedFromListener, <String>['Hello desktop world']);

        // 3. Desktop policy: text selection and range are KEPT (not cleared)
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.textSelection, equals(rangeBeforeCopy));

        // 4. Message selection remains empty
        expect(selection.selectedIds, isEmpty);
        expect(selection.isSelectionMode, isFalse);
      },
    );

    test(
      'dismiss text via clearTextSelection clears range and leaves message set empty',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        selection.clearTextSelection();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, isEmpty);
        expect(selection.isSelectionMode, isFalse);
      },
    );

    test(
      'dismiss text via clearing markdown selection clears range and leaves message set empty',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        expect(selection.enterTextSelection(1), isTrue);

        selection.markdownSelection.clear();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, isEmpty);
      },
    );

    test(
      'dismiss text via collapsed markdown selection clears range and leaves message set empty',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));
        expect(selection.enterTextSelection(1), isTrue);

        selection.markdownSelection.selection = const MarkdownSelection(
          base: MarkdownPosition(documentId: 1, blockIndex: 0, offset: 2),
          extent: MarkdownPosition(documentId: 1, blockIndex: 0, offset: 2),
        );

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, isEmpty);
      },
    );

    test('cancelSelection clears text selection when text is active', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(selection.dispose);

      selection.putBody(1, Markdown.fromString('Hello selectable world'));
      expect(selection.enterTextSelection(1), isTrue);
      expect(selection.isTextSelectionActive, isTrue);

      expect(selection.cancelSelection(), isTrue);

      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelectionSubject, isNull);
      expect(selection.textSelection, isNull);
      expect(selection.selectedIds, isEmpty);
    });

    test(
      'cancelSelection clears message selection when message mode is active and text inactive',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);
        expect(selection.isTextSelectionActive, isFalse);

        expect(selection.cancelSelection(), isTrue);

        expect(selection.selectedIds, isEmpty);
        expect(selection.isSelectionMode, isFalse);
        expect(selection.isTextSelectionActive, isFalse);
      },
    );

    test(
      'cancelSelection returns false when neither text nor message selection is active',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.isSelectionMode, isFalse);

        expect(selection.cancelSelection(), isFalse);
      },
    );

    test(
      r'cancelSelection under $Mobile clears text selection first while preserving message selection',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Mobile message'));
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.selectedIds, <int>{1, 2});

        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        // Dismiss clears text selection first
        expect(selection.cancelSelection(), isTrue);
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);

        // Second dismiss clears message selection
        expect(selection.cancelSelection(), isTrue);
        expect(selection.selectedIds, isEmpty);
        expect(selection.isSelectionMode, isFalse);

        // Third dismiss is a no-op
        expect(selection.cancelSelection(), isFalse);
      },
    );

    test(
      'ranges remain single-message: armed document contains only subject',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Message 1'));
        selection.putBody(2, Markdown.fromString('Message 2'));

        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.textSelectionSubject, 1);

        // MarkdownSelectionController only contains the armed subject ref
        final docs = selection.markdownSelection.documents;
        expect(docs.length, 1);
        expect(docs.first.id, 1);
      },
    );

    test(
      'retargeting text selection to another message moves subject and clears prior range',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Message 1'));
        selection.putBody(2, Markdown.fromString('Message 2'));

        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.markdownSelection.documents.first.id, 1);

        // Direct entry on message 2 retargets subject
        expect(selection.enterTextSelection(2), isTrue);
        expect(selection.textSelectionSubject, 2);
        expect(selection.markdownSelection.documents.first.id, 2);
        expect(selection.selectedIds, isEmpty);
      },
    );

    test('facade notifies listeners on text selection entry and exit', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
      );
      addTearDown(selection.dispose);

      selection.putBody(10, Markdown.fromString('Range observe'));
      var notifyCount = 0;
      selection.addListener(() => notifyCount++);

      expect(selection.enterTextSelection(10), isTrue);
      expect(notifyCount, greaterThan(0));

      final countAfterEnter = notifyCount;
      selection.clearTextSelection();
      expect(notifyCount, greaterThan(countAfterEnter));
      expect(selection.isTextSelectionActive, isFalse);
    });

    testWidgets(
      'ChatKeyboardShortcuts: Escape key triggers cancelSelection when selection is active',
      (tester) async {
        final scrollController = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(scrollController.dispose);
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Hello keyboard test'));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatKeyboardShortcuts(
                controller: scrollController,
                selectionController: selection,
                autofocus: true,
                child: const SizedBox(width: 400, height: 400),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Enter text selection
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        // Press Escape -> text selection cancelled
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, isEmpty);

        // 2. Enter message selection
        selection.startSelection(1);
        expect(selection.isSelectionMode, isTrue);

        // Press Escape -> message selection cancelled
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(selection.isSelectionMode, isFalse);
        expect(selection.selectedIds, isEmpty);
      },
    );

    testWidgets(
      r'idle tap dismisses text selection and leaves message selection empty without firing message menu ($Desktop)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Desktop msg 1'));
        selection.putBody(2, Markdown.fromString('Desktop msg 2'));

        final taps = <int>[];

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
                  onIdleMessageTap: (request) => taps.add(request.messageId),
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        key: ValueKey('container-$id'),
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Enter text selection on message 1 directly (no prior message selection)
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.selectedIds, isEmpty);

        // 2. Idle tap on message 1 -> dismisses text selection, selectedIds remains empty, no message menu
        await tester.tap(find.byKey(const ValueKey('container-1')));
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelection, isNull);
        expect(selection.selectedIds, isEmpty);
        expect(taps, isEmpty);

        // 3. Re-enter text selection on 1, tap on empty space (bottom of viewport)
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        await tester.tapAt(const Offset(200, 500));
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, isEmpty);
        expect(taps, isEmpty);
      },
    );

    testWidgets(
      r'desktop: pan on body surface arms text; padding pan selects message ($Desktop)',
      (tester) async {
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

          selection.putBody(1, Markdown.fromString('Hi'));

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
                          key: ValueKey('container-$id'),
                          height: 120,
                          padding: const EdgeInsets.all(40),
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

          final surface = selection.surfaceFor(1);
          expect(surface, isNotNull);
          final boxes = surface!.localBoxesForRange(0, 0, 2);
          expect(boxes, isNotEmpty);
          final glyph = boxes.first;
          final gutterLocal = Offset(glyph.right + 40, glyph.center.dy);
          final gutterGlobal = (surface as RenderBox).localToGlobal(
            gutterLocal,
          );
          expect(
            selection.containsGlobal(1, gutterGlobal),
            isTrue,
            reason: 'empty gutter is still bubble Inside',
          );

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: gutterGlobal);
          await tester.pump();
          await mouse.down(gutterGlobal);
          await mouse.moveBy(const Offset(0, 24));
          await tester.pump();

          expect(
            selection.hasDragSelection,
            isFalse,
            reason: 'gutter pan must not start message drag-select',
          );
          expect(
            selection.isTextSelectionActive,
            isTrue,
            reason: 'surface press arms text (tdesktop Selecting)',
          );

          await mouse.up();
          await tester.pump();
          selection.clear();
          selection.clearTextSelection();
          await tester.pump();

          final containerRect = tester.getRect(
            find.byKey(const ValueKey('container-1')),
          );
          final paddingPoint = containerRect.topLeft + const Offset(10, 10);
          expect(selection.containsGlobal(1, paddingPoint), isFalse);

          await mouse.down(paddingPoint);
          await mouse.moveBy(const Offset(0, 24));
          await tester.pump();

          expect(
            selection.hasDragSelection || selection.isSelected(1),
            isTrue,
            reason: 'outside body surface → message PrepareSelect pan',
          );

          await mouse.up();
          await tester.pump();
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      r'desktop: click non-text padding with active text range dismisses text ($Desktop)',
      (tester) async {
        // Match real desktop: no mobile toolbarWanted / context menu barrier
        // that would absorb padding taps in widget tests (defaultTargetPlatform
        // is often Android under the test binding).
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

          selection.putBody(1, Markdown.fromString('Hello selectable world'));

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
                          key: ValueKey('container-$id'),
                          height: 120,
                          padding: const EdgeInsets.all(40),
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

          expect(selection.enterTextSelection(1), isTrue);
          selection.markdownSelection.selection = const MarkdownSelection(
            base: MarkdownPosition(documentId: 1, blockIndex: 0, offset: 0),
            extent: MarkdownPosition(documentId: 1, blockIndex: 0, offset: 5),
          );
          await tester.pump();
          expect(selection.isTextSelectionActive, isTrue);
          expect(selection.textSelection, isNotNull);
          expect(selection.textSelection!.isCollapsed, isFalse);
          expect(
            selection.markdownSelection.toolbarWanted,
            isFalse,
            reason: 'desktop must not pin a mobile context menu over the row',
          );

          final containerRect = tester.getRect(
            find.byKey(const ValueKey('container-1')),
          );
          final paddingPoint = containerRect.topLeft + const Offset(10, 10);
          expect(
            selection.containsGlobal(1, paddingPoint),
            isFalse,
            reason: 'padding must be outside the markdown surface',
          );

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(mouse.removePointer);
          await mouse.down(paddingPoint);
          await mouse.up();
          await tester.pumpAndSettle();

          expect(
            selection.isTextSelectionActive,
            isFalse,
            reason: 'mouse click on non-text must dismiss text',
          );
          expect(selection.textSelection, isNull);
          expect(
            selection.selectedIds,
            isEmpty,
            reason: 'dismiss text must not promote to message selection',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      r'message menu is mutually exclusive with direct text selection and message selection ($Desktop)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Desktop msg 1'));
        selection.putBody(2, Markdown.fromString('Desktop msg 2'));

        final taps = <int>[];
        final secondaryTaps = <int>[];

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
                  onIdleMessageTap: (request) => taps.add(request.messageId),
                  onSecondaryMessageTap: (request) =>
                      secondaryTaps.add(request.messageId),
                  messageBuilder: (context, id, message, status, runLayout) =>
                      SizedBox(height: 60, child: Text('msg-$id')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Idle state on $Desktop: primary tap does NOT fire onIdleMessageTap (message menu)
        await tester.tap(find.text('msg-1'));
        await tester.pumpAndSettle();
        expect(taps, isEmpty);

        // Right-click (secondary tap) on $Desktop fires onSecondaryMessageTap
        await tester.tap(find.text('msg-1'), buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        expect(secondaryTaps, <int>[1]);
        secondaryTaps.clear();

        // 2. Direct text selection: tap dismisses text, does NOT fire onIdleMessageTap
        expect(selection.enterTextSelection(1), isTrue);
        await tester.tap(find.text('msg-1'));
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isFalse);
        expect(taps, isEmpty);

        // 3. Message selection: tap toggles message, does NOT fire onIdleMessageTap
        selection.startSelection(1);
        await tester.tap(find.text('msg-2'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(selection.selectedIds, <int>{1, 2});
        expect(taps, isEmpty);

        // Right-click (secondary tap) in message selection mode still fires onSecondaryMessageTap
        await tester.tap(
          find.text('msg-2'),
          buttons: kSecondaryMouseButton,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(secondaryTaps, <int>[2]);
      },
    );

    testWidgets(
      r'desktop does not use timer-based long-press: stationary hold acts as tap, not message selection ($Desktop)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Desktop msg 1'));
        selection.putBody(2, Markdown.fromString('Desktop msg 2'));

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
                      SizedBox(height: 60, child: Text('msg-$id')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Text selection active on 1
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.selectedIds, isEmpty);

        // On $Desktop, interactions are drag-distance driven without timer-based long-press.
        // Holding stationary on message 2 for 500ms does NOT enter message selection.
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('msg-2')),
        );
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await gesture.up();
        await tester.pumpAndSettle();

        // Tap on message 2 dismisses text selection, but does NOT enter message selection.
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
        expect(selection.selectedIds, isEmpty);
      },
    );

    testWidgets(
      r'dragging across messages triggers bidirectional drag multiselect preview and commits on release ($Desktop)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Desktop msg 1'));
        selection.putBody(2, Markdown.fromString('Desktop msg 2'));

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
                      SizedBox(height: 60, child: Text('msg-$id')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Direct text selection active on msg-1
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.selectedIds, isEmpty);
        expect(selection.hasDragSelection, isFalse);

        // 1. Drag from msg-1 down into msg-2
        final origin = tester.getCenter(find.text('msg-1'));
        final target = tester.getCenter(find.text('msg-2'));

        final gesture = await tester.startGesture(origin);
        await tester.pump();

        // Move to target message
        await gesture.moveTo(target);
        await tester.pump();

        // Preview multiselect is now live: messages 1 and 2 previewed
        expect(selection.hasDragSelection, isTrue);
        expect(selection.dragSelectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);
        expect(selection.isSelected(1), isTrue);
        expect(selection.isSelected(2), isTrue);
        // Direct text selection is preserved underneath the preview
        expect(selection.isTextSelectionActive, isTrue);

        // 2. Drag back into origin (msg-1) during the same continuous hold
        await gesture.moveTo(origin);
        await tester.pump();

        // Preview depromoted: drag selection cleared, text selection restored
        expect(selection.hasDragSelection, isFalse);
        expect(selection.dragSelectedIds, isNull);
        expect(selection.isSelectionMode, isFalse);
        expect(selection.selectedIds, isEmpty);
        expect(selection.isTextSelectionActive, isTrue);

        // 3. Move back out to msg-2 and release outside origin bubble
        await gesture.moveTo(target);
        await tester.pump();
        expect(selection.hasDragSelection, isTrue);

        await gesture.up();
        await tester.pumpAndSettle();

        // Committed: drag preview applied to selectedIds, text selection cleared
        expect(selection.hasDragSelection, isFalse);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);
        expect(selection.isTextSelectionActive, isFalse);
      },
    );

    test(
      r'drag multiselect preview: updateDragSelection, clearDragSelection, applyDragSelection ($Desktop)',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(selection.dispose);

        selection.putBody(1, Markdown.fromString('Msg 1 text'));
        selection.putBody(2, Markdown.fromString('Msg 2 text'));

        // 1. Enter text selection in Msg 1
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);
        expect(selection.selectedIds, isEmpty);
        expect(selection.isSelectionMode, isFalse);
        expect(selection.hasDragSelection, isFalse);

        // 2. Drag cursor moves onto Msg 2: updateDragSelection({1, 2})
        var notified = false;
        selection.addListener(() => notified = true);
        selection.updateDragSelection({1, 2});
        expect(notified, isTrue);
        expect(selection.hasDragSelection, isTrue);
        expect(selection.dragSelectedIds, <int>{1, 2});
        expect(selection.isSelected(1), isTrue);
        expect(selection.isSelected(2), isTrue);
        expect(selection.isSelectionMode, isTrue);
        // Text selection in Msg 1 is still technically armed and not discarded
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);

        // 3. Move cursor back to Msg 1: clearDragSelection()
        notified = false;
        selection.clearDragSelection();
        expect(notified, isTrue);
        expect(selection.hasDragSelection, isFalse);
        expect(selection.dragSelectedIds, isNull);
        expect(selection.isSelected(1), isFalse);
        expect(selection.isSelected(2), isFalse);
        expect(selection.isSelectionMode, isFalse);
        // Text selection in Msg 1 is still active!
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelectionSubject, 1);

        // 4. Move cursor again to Msg 2 and release (applyDragSelection())
        selection.updateDragSelection({1, 2});
        notified = false;
        selection.applyDragSelection();
        expect(notified, isTrue);
        expect(selection.hasDragSelection, isFalse);
        expect(selection.dragSelectedIds, isNull);
        // Now permanently committed in selectedIds!
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isSelectionMode, isTrue);
        // Committing to message selection clears active text selection
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.textSelectionSubject, isNull);
      },
    );

    test(
      'inlineHitAt resolves links, monospace spans, code blocks, and plain text',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        final md = Markdown.fromString(
          'Visit [Auto Docs](https://auto.com) now\n\n'
          'Run `flutter test` here\n\n'
          '```dart\nvoid main() {}\n```\n\n'
          'Just plain text',
        );
        selection.putBody(1, md);

        // Block 0: 'Visit [Auto Docs](https://auto.com) now'
        expect(
          selection.inlineHitAt(messageId: 1, blockIndex: 0, offset: 2),
          isNull,
        );
        final linkHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 0,
          offset: 8,
        );
        expect(linkHit, isA<ChatInlineHit$Link>());
        final link = linkHit! as ChatInlineHit$Link;
        expect(link.messageId, 1);
        expect(link.title, 'Auto Docs');
        expect(link.url, 'https://auto.com');
        expect(
          selection.inlineHitAt(messageId: 1, blockIndex: 0, offset: 16),
          isNull,
        );

        // Block 1: Spacer
        expect(
          selection.inlineHitAt(messageId: 1, blockIndex: 1, offset: 0),
          isNull,
        );

        // Block 2: 'Run `flutter test` here'
        expect(
          selection.inlineHitAt(messageId: 1, blockIndex: 2, offset: 1),
          isNull,
        );
        final monoHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 2,
          offset: 6,
        );
        expect(monoHit, isA<ChatInlineHit$Code>());
        final mono = monoHit! as ChatInlineHit$Code;
        expect(mono.messageId, 1);
        expect(mono.code, 'flutter test');
        expect(mono.language, isNull);
        expect(
          selection.inlineHitAt(messageId: 1, blockIndex: 2, offset: 18),
          isNull,
        );

        // Block 4: MD$Code — body hit returns null (delegating to text selection)
        final codeBlockBodyHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 4,
          offset: 3,
        );
        expect(codeBlockBodyHit, isNull);

        // Block 4: MD$Code — header tap returns code hit
        final codeBlockHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 4,
          offset: 3,
          isHeader: true,
        );
        expect(codeBlockHit, isA<ChatInlineHit$Code>());
        final codeBlock = codeBlockHit! as ChatInlineHit$Code;
        expect(codeBlock.messageId, 1);
        expect(codeBlock.code, 'void main() {}');
        expect(codeBlock.language, 'dart');

        // Block 6: Plain text
        expect(
          selection.inlineHitAt(messageId: 1, blockIndex: 6, offset: 4),
          isNull,
        );

        // Unregistered message
        expect(
          selection.inlineHitAt(messageId: 99, blockIndex: 0, offset: 0),
          isNull,
        );
      },
    );

    test(
      'inlineHitAt resolves links and code within headings, quotes, lists, and tables',
      () {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        final md = Markdown.fromString(
          '# Heading [HLink](https://h.com)\n\n'
          '> Quote with `qcode`\n\n'
          '- List item [LLink](https://l.com)\n\n'
          '| Col 1 |\n|---|\n| [TLink](https://t.com) |',
        );
        selection.putBody(1, md);

        // Block 0: Heading
        final hHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 0,
          offset: 10,
        );
        expect(hHit, isA<ChatInlineHit$Link>());
        expect((hHit! as ChatInlineHit$Link).url, 'https://h.com');

        // Block 2: Quote
        final qHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 2,
          offset: 12,
        );
        expect(qHit, isA<ChatInlineHit$Code>());
        expect((qHit! as ChatInlineHit$Code).code, 'qcode');

        // Block 4: List
        final lHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 4,
          offset: 12,
        );
        expect(lHit, isA<ChatInlineHit$Link>());
        expect((lHit! as ChatInlineHit$Link).url, 'https://l.com');

        // Block 6: Table
        expect(
          selection.inlineHitAt(messageId: 1, blockIndex: 6, offset: 2),
          isNull,
        );
        final tHit = selection.inlineHitAt(
          messageId: 1,
          blockIndex: 6,
          offset: 8,
        );
        expect(tHit, isA<ChatInlineHit$Link>());
        expect((tHit! as ChatInlineHit$Link).url, 'https://t.com');
      },
    );

    test(
      'handleInlineHit matrix: idle fires; mobile message/text suppress all; desktop message keeps live',
      () {
        // Locked matrix (mobile): idle → link+code fire; message selected OR
        // text selected → link+code+COPY chrome all suppress. Desktop message
        // selection keeps link+code live. One table so we stop flip-flopping
        // “fix copy” vs “suppress code”.
        final mobile = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(mobile.dispose);

        final desktop = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(desktop.dispose);

        const linkHit1 = ChatInlineHit.link(
          messageId: 1,
          title: 'Title',
          url: 'https://example.com',
        );
        const codeHit1 = ChatInlineHit.code(
          messageId: 1,
          code: 'print(1)',
          language: 'dart',
        );
        // Fenced COPY chrome is the same ChatInlineHit$Code variant without
        // contour — suppression must not special-case chrome vs inline code.
        const copyChromeHit1 = ChatInlineHit.code(
          messageId: 1,
          code:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          language: null,
        );

        final mobileTaps = <(int, String, String)>[];
        final mobileCodeTaps = <(int, String)>[];
        mobile.addInteractionListener((i) {
          switch (i) {
            case ChatLinkActivated(
              :final messageId,
              :final title,
              :final url,
              gesture: ChatInlineGesture.tap,
            ):
              mobileTaps.add((messageId, title, url));
            case ChatCopied(
              :final text,
              origin: ChatCopyOrigin.codeTap,
              :final messageId?,
            ):
              mobileCodeTaps.add((messageId, text));
            case _:
              break;
          }
        });

        final desktopTaps = <(int, String, String)>[];
        final desktopCodeTaps = <(int, String)>[];
        desktop.addInteractionListener((i) {
          switch (i) {
            case ChatLinkActivated(
              :final messageId,
              :final title,
              :final url,
              gesture: ChatInlineGesture.tap,
            ):
              desktopTaps.add((messageId, title, url));
            case ChatCopied(
              :final text,
              origin: ChatCopyOrigin.codeTap,
              :final messageId?,
            ):
              desktopCodeTaps.add((messageId, text));
            case _:
              break;
          }
        });

        void expectMobileAllFire() {
          expect(mobile.handleInlineHit(linkHit1), isTrue);
          expect(mobile.handleInlineHit(codeHit1), isTrue);
          expect(mobile.handleInlineHit(copyChromeHit1), isTrue);
        }

        void expectMobileAllSuppressed() {
          final linksBefore = mobileTaps.length;
          final codesBefore = mobileCodeTaps.length;
          expect(mobile.handleInlineHit(linkHit1), isFalse);
          expect(mobile.handleInlineHit(codeHit1), isFalse);
          expect(mobile.handleInlineHit(copyChromeHit1), isFalse);
          expect(mobileTaps, hasLength(linksBefore));
          expect(mobileCodeTaps, hasLength(codesBefore));
        }

        // 1. Mobile idle
        expectMobileAllFire();
        expect(mobileTaps, hasLength(1));
        expect(mobileCodeTaps, hasLength(2));

        // 2. Mobile message multiselect, no text selection
        mobile.startSelection(1);
        mobile.toggle(2);
        expect(mobile.isSelectionMode, isTrue);
        expect(mobile.isTextSelectionActive, isFalse);
        expectMobileAllSuppressed();

        // 3. Mobile text selection active on subject 1
        mobile.putBody(1, Markdown.fromString('Hello `code` link'));
        expect(mobile.enterTextSelection(1), isTrue);
        expect(mobile.isTextSelectionActive, isTrue);
        expect(mobile.textSelectionSubject, 1);
        expectMobileAllSuppressed();

        // 4. Desktop message selection keeps link+code live
        desktop.startSelection(1);
        desktop.toggle(2);
        expect(desktop.isSelectionMode, isTrue);
        expect(desktop.handleInlineHit(linkHit1), isTrue);
        expect(desktopTaps, hasLength(1));
        expect(desktop.handleInlineHit(codeHit1), isTrue);
        expect(desktopCodeTaps, hasLength(1));

        // 5. Desktop arm-for-entry (no live range) must not suppress —
        // otherwise idle mouse clicks on links/COPY die after pointer-down arm.
        desktop.clear();
        desktop.putBody(1, Markdown.fromString('Hello'));
        expect(desktop.armTextSelection(1), isTrue);
        expect(desktop.isTextSelectionActive, isTrue);
        expect(desktop.textSelection, isNull);
        expect(desktop.handleInlineHit(linkHit1), isTrue);
        expect(desktopTaps, hasLength(2));
      },
    );

    test(
      'handleInlineHit code click-to-copy writes to clipboard and emits ChatCopied codeTap',
      () async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

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

        final interactions = <ChatSelectionInteraction>[];
        selection.addInteractionListener(interactions.add);

        const codeHit = ChatInlineHit.code(
          messageId: 42,
          code: 'flutter run',
          language: 'bash',
        );

        expect(selection.handleInlineHit(codeHit), isTrue);
        expect(interactions, [
          const ChatSelectionInteraction.copied(
            text: 'flutter run',
            origin: ChatCopyOrigin.codeTap,
            messageId: 42,
            gesture: ChatInlineGesture.tap,
          ),
        ]);
        expect(clipboard, isNotEmpty);
        expect(clipboard.last.arguments['text'], 'flutter run');

        // Test copyCodeOnClick: false
        final noCopySelection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
          copyCodeOnClick: false,
        );
        addTearDown(noCopySelection.dispose);

        final noCopyInteractions = <ChatSelectionInteraction>[];
        noCopySelection.addInteractionListener(noCopyInteractions.add);

        clipboard.clear();
        expect(noCopySelection.handleInlineHit(codeHit), isTrue);
        expect(noCopyInteractions, [
          const ChatSelectionInteraction.codeActivated(
            messageId: 42,
            code: 'flutter run',
            gesture: ChatInlineGesture.tap,
          ),
        ]);
        expect(clipboard, isEmpty);
      },
    );

    test(
      'handleInlineHitLongPress code reuses click-to-copy and yields under suppression',
      () async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

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

        final interactions = <ChatSelectionInteraction>[];
        selection.addInteractionListener(interactions.add);

        const codeHit = ChatInlineHit.code(
          messageId: 42,
          code: 'flutter run',
          language: 'bash',
        );

        expect(selection.handleInlineHitLongPress(codeHit), isTrue);
        expect(interactions, [
          const ChatSelectionInteraction.copied(
            text: 'flutter run',
            origin: ChatCopyOrigin.codeTap,
            messageId: 42,
            gesture: ChatInlineGesture.longPress,
          ),
        ]);
        expect(clipboard, isNotEmpty);
        expect(clipboard.last.arguments['text'], 'flutter run');

        selection.startSelection(7);
        interactions.clear();
        clipboard.clear();
        expect(
          selection.handleInlineHitLongPress(codeHit),
          isFalse,
          reason: 'mobile message selection must suppress hold-to-copy',
        );
        expect(interactions, isEmpty);
        expect(clipboard, isEmpty);
      },
    );

    test('listener removal cleanly unregisters interaction observers', () {
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(selection.dispose);

      var linkCalls = 0;
      var codeCalls = 0;
      void interactionListener(ChatSelectionInteraction i) {
        switch (i) {
          case ChatLinkActivated(gesture: ChatInlineGesture.tap):
            linkCalls++;
          case ChatCopied(origin: ChatCopyOrigin.codeTap):
            codeCalls++;
          case _:
            break;
        }
      }

      selection.addInteractionListener(interactionListener);

      const linkHit = ChatInlineHit.link(messageId: 1, title: 'T', url: 'U');
      const codeHit = ChatInlineHit.code(messageId: 1, code: 'C');

      expect(selection.handleInlineHit(linkHit), isTrue);
      expect(selection.handleInlineHit(codeHit), isTrue);
      expect(linkCalls, 1);
      expect(codeCalls, 1);

      selection.removeInteractionListener(interactionListener);

      expect(selection.handleInlineHit(linkHit), isTrue);
      expect(selection.handleInlineHit(codeHit), isTrue);
      expect(linkCalls, 1);
      expect(codeCalls, 1);
    });

    testWidgets(
      'harness: tap on link with live text selection is suppressed (keeps or dismisses per idle-tap)',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final linkTaps = <(int, String, String)>[];
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
                      Container(
                        key: ValueKey('container-$id'),
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        selection.startSelection(1);
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        await tester.tapAt(_glyphPointOnBody(selection, 1, endOffset: 9));
        await tester.pumpAndSettle();

        // Live character-range suppresses inline activation (ADR 012).
        expect(linkTaps, isEmpty);
        expect(selection.selectedIds, <int>{1});
      },
    );

    testWidgets('harness: tap on code with live text selection is suppressed', (
      tester,
    ) async {
      final dataSource = _LoadedSource([_msg(1)]);
      final controller = ChatScrollController();
      final interactions = <ChatSelectionInteraction>[];
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
        onInteraction: interactions.add,
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

      selection.putBody(1, Markdown.fromString('```dart\nvoid main() {}\n```'));

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

      expect(selection.enterTextSelection(1), isTrue);
      expect(selection.isTextSelectionActive, isTrue);

      final mdTopLeft = tester.getTopLeft(find.byKey(const ValueKey('md-1')));
      await tester.tapAt(mdTopLeft + const Offset(50, 10));
      await tester.pumpAndSettle();

      // Live character-range suppresses fenced COPY chrome (ADR 012).
      expect(interactions, isEmpty);
      expect(clipboard, isEmpty);
    });

    testWidgets(
      'harness: tap on non-inline chrome with active text selection dismisses text',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final linkTaps = <(int, String, String)>[];
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
                      Container(
                        key: ValueKey('container-$id'),
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Enter text selection on message 1
        selection.startSelection(1);
        expect(selection.enterTextSelection(1), isTrue);
        expect(selection.isTextSelectionActive, isTrue);

        // 2. Tap on padding (non-inline chrome)
        final containerRect = tester.getRect(
          find.byKey(const ValueKey('container-1')),
        );
        final paddingPoint = containerRect.topLeft + const Offset(4, 4);
        await tester.tapAt(paddingPoint);
        await tester.pumpAndSettle();

        // 3. Text selection dismissed, link not tapped, message stays selected
        expect(linkTaps, isEmpty);
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1});
      },
    );

    testWidgets(
      'harness: tap on link in mobile message multiselect toggles message',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final linkTaps = <(int, String, String)>[];
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
        selection.putBody(2, Markdown.fromString('Normal message'));

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
                      Container(
                        key: ValueKey('container-$id'),
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Enter message selection on messages 1 and 2 (no text selection)
        selection
          ..startSelection(1)
          ..toggle(2);
        expect(selection.selectedIds, <int>{1, 2});
        expect(selection.isTextSelectionActive, isFalse);

        // 2. Tap on link in message 1
        await tester.tap(find.byKey(const ValueKey('md-1')));
        await tester.pumpAndSettle();

        // 3. Link was suppressed; tap toggled message 1 off!
        expect(linkTaps, isEmpty);
        expect(selection.selectedIds, <int>{2});
      },
    );

    testWidgets(
      'harness: desktop message selection keeps link and code clicks without clearing membership',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final linkTaps = <(int, String, String)>[];
        final codeTaps = <(int, String)>[];
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
          onInteraction: (i) {
            switch (i) {
              case ChatLinkActivated(
                :final messageId,
                :final title,
                :final url,
                gesture: ChatInlineGesture.tap,
              ):
                linkTaps.add((messageId, title, url));
              case ChatCopied(
                :final text,
                origin: ChatCopyOrigin.codeTap,
                :final messageId?,
              ):
                codeTaps.add((messageId, text));
              case _:
                break;
            }
          },
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(
          1,
          Markdown.fromString('See [docs](https://flutter.dev) and `inline`.'),
        );

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

        selection.startSelection(1);
        await tester.pumpAndSettle();
        expect(selection.selectedIds, <int>{1});
        expect(selection.exposesSelectionSurface(1), isTrue);
        expect(selection.markdownSelection.mountedSurfaces, isNotEmpty);

        final surface = selection.markdownSelection.mountedSurfaces.first;
        final box = surface as RenderBox;

        final linkBoxes = surface.localBoxesForRange(
          0,
          'See '.length,
          'See docs'.length,
        );
        expect(linkBoxes, isNotEmpty);
        await tester.tapAt(box.localToGlobal(linkBoxes.first.center));
        await tester.pumpAndSettle();

        expect(linkTaps, hasLength(1));
        expect(linkTaps.last.$3, 'https://flutter.dev');
        expect(selection.selectedIds, <int>{1});

        final codeBoxes = surface.localBoxesForRange(
          0,
          'See docs and '.length,
          'See docs and inline'.length,
        );
        expect(codeBoxes, isNotEmpty);
        await tester.tapAt(box.localToGlobal(codeBoxes.first.center));
        await tester.pumpAndSettle();

        expect(codeTaps, hasLength(1));
        expect(codeTaps.last.$2, 'inline');
        expect(selection.selectedIds, <int>{1});
      },
    );

    testWidgets(
      'harness: desktop message selection blocks starting text selection',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.desktop(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(
          1,
          Markdown.fromString('Hello selectable desktop body'),
        );

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
        expect(selection.selectedIds, <int>{1});
        expect(selection.exposesSelectionSurface(1), isTrue);
        expect(selection.armTextSelection(1), isFalse);

        final scope = tester.widget<MarkdownSelectionScope>(
          find.byType(MarkdownSelectionScope),
        );
        expect(
          scope.enabled,
          isFalse,
          reason:
              'Settled desktop message selection must disable text-selection '
              'gestures while surfaces stay mounted for inline hits',
        );
        expect(selection.isTextSelectionActive, isFalse);
        expect(selection.selectedIds, <int>{1});
      },
    );

    testWidgets(
      'harness: tap on link in idle message activates link without triggering onIdleMessageTap',
      (tester) async {
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
                  onIdleMessageTap: (request) =>
                      idleTaps.add(request.messageId),
                  messageBuilder: (context, id, message, status, runLayout) =>
                      Container(
                        key: ValueKey('container-$id'),
                        height: 80,
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Idle state
        expect(selection.isSelectionMode, isFalse);
        expect(selection.isTextSelectionActive, isFalse);

        // 2. Tap link glyphs
        await tester.tapAt(_glyphPointOnBody(selection, 1, endOffset: 9));
        await tester.pumpAndSettle();

        // 3. Link tap fired, idle message tap did NOT fire!
        expect(linkTaps, hasLength(1));
        expect(linkTaps.first, (1, 'Auto Docs', 'https://auto.com'));
        expect(idleTaps, isEmpty);
      },
    );

    testWidgets(
      'harness: long-press on link triggers link long-press and suppresses message selection entry',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final linkLongPresses = <(int, String, String)>[];
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
          onInteraction: (i) {
            if (i case ChatLinkActivated(
              :final messageId,
              :final title,
              :final url,
              gesture: ChatInlineGesture.longPress,
            )) {
              linkLongPresses.add((messageId, title, url));
            }
          },
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(
          1,
          Markdown.fromString('[Preview Link](https://auto.com/spec)'),
        );

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
                        height: 60,
                        child: ListenableBuilder(
                          listenable: selection,
                          builder: (context, _) {
                            final model = selection.bodyOf(id);
                            if (model == null) return const SizedBox.shrink();
                            return MarkdownWidget(
                              key: ValueKey('md-$id'),
                              markdown: model,
                              documentId: selection.exposesSelectionSurface(id)
                                  ? id
                                  : null,
                              controller: selection.exposesSelectionSurface(id)
                                  ? selection.markdownSelection
                                  : null,
                            );
                          },
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(selection.isSelectionMode, isFalse);

        // Long press the link glyphs
        await tester.longPressAt(_glyphPointOnBody(selection, 1, endOffset: 9));
        await tester.pumpAndSettle();

        // Link long-press fired; message selection was suppressed!
        expect(linkLongPresses, hasLength(1));
        expect(linkLongPresses.first, (
          1,
          'Preview Link',
          'https://auto.com/spec',
        ));
        expect(selection.isSelectionMode, isFalse);
      },
    );

    testWidgets(
      'harness: child GestureDetector tap in selection mode toggles row instead of firing child callback',
      (tester) async {
        final dataSource = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        final childTaps = <int>[];

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
                        height: 60,
                        child: Row(
                          children: [
                            GestureDetector(
                              key: ValueKey('avatar-$id'),
                              onTap: () => childTaps.add(id),
                              child: Text('avatar-$id'),
                            ),
                            Text('msg-$id'),
                          ],
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Idle state: tapping avatar fires child tap
        await tester.tap(find.byKey(const ValueKey('avatar-1')));
        await tester.pumpAndSettle();
        expect(childTaps, <int>[1]);
        childTaps.clear();

        // 2. Enter selection mode
        selection.startSelection(1);
        await tester.pumpAndSettle();
        expect(selection.isSelectionMode, isTrue);

        // 3. Tapping avatar in message selection mode toggles row 2, does NOT fire child tap!
        await tester.tap(
          find.byKey(const ValueKey('avatar-2')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(childTaps, isEmpty);
        expect(selection.selectedIds, <int>{1, 2});
      },
    );
  });

  testWidgets('chat list is not wrapped in the library selection scope', (
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
                  SizedBox(height: 60, child: Text('msg-$id')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownSelectionScope), findsNothing);
  });

  group('ChatSelectionPolicy.forPlatform', () {
    test('iOS and Android map to mobile', () {
      expect(
        ChatSelectionPolicy.forPlatform(
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        isA<ChatSelectionPolicy$Mobile>(),
      );
      expect(
        ChatSelectionPolicy.forPlatform(
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        isA<ChatSelectionPolicy$Mobile>(),
      );
    });

    test('desktop OSes map to desktop', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          ChatSelectionPolicy.forPlatform(platform: platform, isWeb: false),
          isA<ChatSelectionPolicy$Desktop>(),
          reason: '$platform → desktop',
        );
      }
    });

    test('web maps to desktop regardless of TargetPlatform', () {
      expect(
        ChatSelectionPolicy.forPlatform(
          platform: TargetPlatform.android,
          isWeb: true,
        ),
        isA<ChatSelectionPolicy$Desktop>(),
      );
    });
  });

  group('body lifecycle and remount', () {
    testWidgets(
      'remount same messageId keeps body registered and paints MarkdownWidget',
      (tester) async {
        final selection = ChatSelectionController();
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _RegisteredLifecycleBody(
                key: const ValueKey('a'),
                controller: selection,
                messageId: 1,
                text: 'have the same issue',
              ),
            ),
          ),
        );
        await tester.pump();
        expect(selection.bodyOf(1), isNotNull);
        expect(find.byType(MarkdownWidget), findsOneWidget);

        // Force remount (selection chrome / slot rebuild can remount rows).
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _RegisteredLifecycleBody(
                key: const ValueKey('b'),
                controller: selection,
                messageId: 1,
                text: 'have the same issue',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          selection.bodyOf(1),
          isNotNull,
          reason: 'body lost after remount (dispose raced putBody)',
        );
        expect(
          find.byType(MarkdownWidget),
          findsOneWidget,
          reason: 'empty bubble — ChatMarkdownBody got null model',
        );
      },
    );

    testWidgets('entering message selection keeps MarkdownWidget mounted', (
      tester,
    ) async {
      final selection = ChatSelectionController();
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _RegisteredLifecycleBody(
              controller: selection,
              messageId: 1,
              text: 'have the same issue',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MarkdownWidget), findsOneWidget);

      selection.startSelection(1);
      await tester.pump();
      await tester.pump();

      expect(selection.bodyOf(1), isNotNull);
      expect(find.byType(MarkdownWidget), findsOneWidget);
    });

    testWidgets(
      'edit morph: after twin dispose, live body keeps selection surface and body model',
      (tester) async {
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(selection.dispose);

        const original = 'plain text only';
        const updated = 'see `inline` and [docs](https://example.com)';

        Widget harness(String content) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatMessageChangeTransition(
                contentIdentity: content,
                content: _RegisteredLifecycleBody(
                  controller: selection,
                  messageId: 1,
                  text: content,
                ),
                metaBuilder: (context, editedOpacity) =>
                    const SizedBox(width: 40, height: 12),
                color: const Color(0xFF2B5278),
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.all(8),
                outgoing: false,
              ),
            ),
          ),
        );

        await tester.pumpWidget(harness(original));
        await tester.pumpAndSettle();
        expect(selection.bodyOf(1)?.toString(), original);
        expect(selection.surfaceFor(1), isNotNull);

        await tester.pumpWidget(harness(updated));
        // Mid-morph: outgoing twin is mounted under registers:false.
        await tester.pump();
        expect(selection.bodyOf(1)?.toString(), updated);

        await tester.pump(kChatMessageChangeDuration);
        await tester.pumpAndSettle();

        expect(
          selection.bodyOf(1)?.toString(),
          updated,
          reason: 'live body model must stay on the edited text after morph',
        );
        expect(
          selection.surfaceFor(1),
          isNotNull,
          reason:
              'outgoing twin detach must not orphan the live selection surface',
        );

        // Inline hit needs laid-out glyphs on the live surface.
        final surface = selection.surfaceFor(1)!;
        final boxes = surface.localBoxesForRange(
          0,
          'see '.length,
          'see `inline`'.length,
        );
        expect(boxes, isNotEmpty);
        final global = (surface as RenderBox).localToGlobal(boxes.first.center);
        final hit = selection.resolveInlineHit(1, global);
        expect(hit, isA<ChatInlineHit$Code>());
      },
    );

    testWidgets(
      'edit morph: disposing outgoing twin must not wipe the live body',
      (tester) async {
        final selection = ChatSelectionController();
        addTearDown(selection.dispose);

        Widget harness({required bool withOutgoing}) => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                _RegisteredLifecycleBody(
                  key: const ValueKey('incoming'),
                  controller: selection,
                  messageId: 1,
                  text: 'updated body',
                ),
                if (withOutgoing)
                  _RegisteredLifecycleBody(
                    key: const ValueKey('outgoing'),
                    controller: selection,
                    messageId: 1,
                    text: 'original body',
                  ),
              ],
            ),
          ),
        );

        await tester.pumpWidget(harness(withOutgoing: true));
        await tester.pump();
        expect(selection.bodyOf(1), isNotNull);

        // Morph completes — outgoing slot cleared; incoming State stays mounted.
        await tester.pumpWidget(harness(withOutgoing: false));
        await tester.pump();

        expect(
          selection.bodyOf(1),
          isNotNull,
          reason: 'outgoing dispose wiped the body after edit morph',
        );
        expect(find.byType(MarkdownWidget), findsOneWidget);
        expect(selection.bodyOf(1)!.toString(), 'updated body');
      },
    );

    testWidgets(
      'putBody during build initState under scope does not throw markNeedsBuild',
      (tester) async {
        final selection = ChatSelectionController();
        addTearDown(selection.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _RegisteredLifecycleBody(
                controller: selection,
                messageId: 1,
                text: 'registered in init',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(selection.bodyOf(1), isNotNull);
        expect(find.byType(MarkdownWidget), findsOneWidget);
      },
    );
  });
}

class _RegisteredLifecycleBody extends StatefulWidget {
  const _RegisteredLifecycleBody({
    required this.controller,
    required this.messageId,
    required this.text,
    super.key,
  });

  final ChatSelectionController controller;
  final int messageId;
  final String text;

  @override
  State<_RegisteredLifecycleBody> createState() =>
      _RegisteredLifecycleBodyState();
}

class _RegisteredLifecycleBodyState extends State<_RegisteredLifecycleBody> {
  Object? _token;

  @override
  void initState() {
    super.initState();
    _put();
  }

  @override
  void didUpdateWidget(covariant _RegisteredLifecycleBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.messageId != widget.messageId) {
      if (_token != null) {
        oldWidget.controller.removeBody(oldWidget.messageId, token: _token);
      }
      _token = null;
      _put();
      return;
    }
    if (oldWidget.text != widget.text) {
      _put();
    }
  }

  void _put() {
    if (!ChatMarkdownBodyRegistration.allows(context)) {
      return;
    }
    _token = widget.controller.putBody(
      widget.messageId,
      Markdown.fromString(widget.text),
      order: widget.messageId,
      token: _token,
    );
  }

  @override
  void dispose() {
    if (_token != null) {
      widget.controller.removeBody(widget.messageId, token: _token);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatMarkdownBody(
    controller: widget.controller,
    messageId: widget.messageId,
    markdown: Markdown.fromString(widget.text),
  );
}
