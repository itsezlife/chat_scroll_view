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

/// Red-capable loops for:
/// 1) press-cancel / leave-highlight still activating inline hits
/// 2) selected-message tap dual-firing unselect + inline activation
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScroll(
    WidgetTester tester, {
    required ChatSelectionController selection,
    required ChatDataSource dataSource,
    required ChatScrollController controller,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
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

  /// Down near the trailing ink edge; up just past that edge (same line).
  /// Travel stays under [kTouchSlop] so TapGestureRecognizer still accepts —
  /// the bug is activation from the *down* hit while release is outside.
  (Offset downOnLink, Offset upOutsideLink) linkEdgeLeavePoints(
    ChatSelectionController selection,
  ) {
    final surface = selection.markdownSelection.mountedSurfaces.first;
    final box = surface as RenderBox;
    // "Prefix [link text](url) tail." — link starts after "Prefix ".
    final linkBoxes = surface.localBoxesForRange(
      0,
      'Prefix '.length,
      'Prefix link text'.length,
    );
    expect(linkBoxes, isNotEmpty);
    final link = linkBoxes.first;
    // Glyph-tight hit is inset from [localBoxesForRange] — binary-search the
    // trailing edge so down is in and up is out within touch slop.
    var lo = link.left;
    var hi = link.right + 24;
    for (var i = 0; i < 40; i++) {
      final mid = (lo + hi) / 2;
      final g = box.localToGlobal(Offset(mid, link.center.dy));
      if (selection.resolveInlineHit(1, g) != null) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final down = box.localToGlobal(Offset(lo - 3, link.center.dy));
    final up = box.localToGlobal(Offset(hi + 3, link.center.dy));
    expect(
      (up - down).distance,
      lessThan(kTouchSlop),
      reason: 'edge-leave fixture must stay inside tap slop',
    );
    expect(
      selection.resolveInlineHit(1, down),
      isNotNull,
      reason: 'down must land on the link',
    );
    expect(
      selection.resolveInlineHit(1, up),
      isNull,
      reason: 'up must be outside the link hit',
    );
    return (down, up);
  }

  Offset linkCenter(ChatSelectionController selection, {int messageId = 1}) {
    final surface = selection.surfaceFor(messageId);
    expect(surface, isNotNull, reason: 'expected surface for $messageId');
    final box = surface! as RenderBox;
    final linkBoxes = surface.localBoxesForRange(
      0,
      'Prefix '.length,
      'Prefix link text'.length,
    );
    expect(linkBoxes, isNotEmpty);
    return box.localToGlobal(linkBoxes.first.center);
  }

  group('inline press leave / cancel must not activate', () {
    testWidgets(
      'release outside link contour (within tap slop) must not activate',
      (tester) async {
        final linkTaps = <String>[];
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
          onInteraction: (i) {
            if (i case ChatLinkActivated(
              :final url,
              gesture: ChatInlineGesture.tap,
            )) {
              linkTaps.add(url);
            }
          },
        );
        final controller = ChatScrollController();
        final dataSource = _LoadedSource([_msg(1)]);
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(
          1,
          Markdown.fromString(
            'Prefix [link text](https://leave.dev) tail here.',
          ),
        );

        await pumpScroll(
          tester,
          selection: selection,
          dataSource: dataSource,
          controller: controller,
        );

        final points = linkEdgeLeavePoints(selection);
        final down = points.$1;
        final up = points.$2;

        final gesture = await tester.startGesture(down);
        await tester.pump();
        expect(
          selection.spanFeedback,
          isNotNull,
          reason: 'ink arms on link down',
        );

        await gesture.moveTo(up);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          linkTaps,
          isEmpty,
          reason:
              'release outside the link must not activate — even when travel '
              'stays within tap slop and TapGestureRecognizer accepts',
        );
        // Ink should already have aborted on contour leave (before up).
        // Checked after up so activation failure is reported first.
        expect(
          selection.spanFeedback,
          isNull,
          reason:
              'leaving the link contour must abort ink (not only past-slop)',
        );
      },
    );

    testWidgets(
      'past-slop VERTICAL (scroll cancel) then up must not activate',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          final linkTaps = <String>[];
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.mobile(),
            onInteraction: (i) {
              if (i case ChatLinkActivated(
                :final url,
                gesture: ChatInlineGesture.tap,
              )) {
                linkTaps.add(url);
              }
            },
          );
          // Tall list so VerticalDragGestureRecognizer can own a real scroll.
          final messages = [for (var i = 0; i < 40; i++) _msg(i)];
          final controller = ChatScrollController()
            ..jumpTo(messages.length - 1);
          final dataSource = _LoadedSource(messages);
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

          for (final m in messages) {
            selection.putBody(
              m.id,
              Markdown.fromString(
                m.id == messages.length - 1
                    ? 'Prefix [link text](https://vertical.dev) tail.'
                    : 'body ${m.id}',
              ),
            );
          }

          await pumpScroll(
            tester,
            selection: selection,
            dataSource: dataSource,
            controller: controller,
          );

          final down = linkCenter(selection, messageId: messages.length - 1);
          final gesture = await tester.startGesture(down);
          await tester.pump();
          expect(selection.spanFeedback, isNotNull);

          // Vertical past slop — same path as list pan / scroll cancel.
          await gesture.moveBy(const Offset(0, -(kTouchSlop + 8)));
          await tester.pump();
          expect(
            selection.spanFeedback,
            isNull,
            reason: 'vertical past-slop must abort ink',
          );

          await gesture.up();
          await tester.pumpAndSettle();

          expect(
            linkTaps,
            isEmpty,
            reason:
                'vertical scroll/cancel past-slop must not activate the link '
                '(got $linkTaps)',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('past-slop HORIZONTAL then up must not activate (control)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final linkTaps = <String>[];
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
          onInteraction: (i) {
            if (i case ChatLinkActivated(
              :final url,
              gesture: ChatInlineGesture.tap,
            )) {
              linkTaps.add(url);
            }
          },
        );
        final messages = [for (var i = 0; i < 40; i++) _msg(i)];
        final controller = ChatScrollController()..jumpTo(messages.length - 1);
        final dataSource = _LoadedSource(messages);
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        for (final m in messages) {
          selection.putBody(
            m.id,
            Markdown.fromString(
              m.id == messages.length - 1
                  ? 'Prefix [link text](https://horizontal.dev) tail.'
                  : 'body ${m.id}',
            ),
          );
        }

        await pumpScroll(
          tester,
          selection: selection,
          dataSource: dataSource,
          controller: controller,
        );

        final down = linkCenter(selection, messageId: messages.length - 1);
        final gesture = await tester.startGesture(down);
        await tester.pump();
        expect(selection.spanFeedback, isNotNull);

        await gesture.moveBy(const Offset(kTouchSlop + 8, 0));
        await tester.pump();
        expect(selection.spanFeedback, isNull);

        await gesture.up();
        await tester.pumpAndSettle();

        expect(linkTaps, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('past-slop abort then pointer-up must not activate', (
      tester,
    ) async {
      final linkTaps = <String>[];
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
        onInteraction: (i) {
          if (i case ChatLinkActivated(
            :final url,
            gesture: ChatInlineGesture.tap,
          )) {
            linkTaps.add(url);
          }
        },
      );
      final controller = ChatScrollController();
      final dataSource = _LoadedSource([_msg(1)]);
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      selection.putBody(
        1,
        Markdown.fromString('Prefix [link text](https://slop.dev) tail.'),
      );

      await pumpScroll(
        tester,
        selection: selection,
        dataSource: dataSource,
        controller: controller,
      );

      final down = linkCenter(selection);

      final gesture = await tester.startGesture(down);
      await tester.pump();
      expect(selection.spanFeedback, isNotNull);

      await gesture.moveBy(const Offset(kTouchSlop + 2, 0));
      await tester.pump();
      expect(
        selection.spanFeedback,
        isNull,
        reason: 'past-slop must abort ink',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        linkTaps,
        isEmpty,
        reason: 'aborted press must not activate on up',
      );
    });

    testWidgets('pointer cancel after armed press must not activate', (
      tester,
    ) async {
      final linkTaps = <String>[];
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
        onInteraction: (i) {
          if (i case ChatLinkActivated(
            :final url,
            gesture: ChatInlineGesture.tap,
          )) {
            linkTaps.add(url);
          }
        },
      );
      final controller = ChatScrollController();
      final dataSource = _LoadedSource([_msg(1)]);
      addTearDown(controller.dispose);
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      selection.putBody(
        1,
        Markdown.fromString('Prefix [link text](https://cancel.dev) tail.'),
      );

      await pumpScroll(
        tester,
        selection: selection,
        dataSource: dataSource,
        controller: controller,
      );

      final down = linkCenter(selection);
      final gesture = await tester.startGesture(down);
      await tester.pump();
      expect(selection.spanFeedback, isNotNull);

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(selection.spanFeedback, isNull);
      expect(linkTaps, isEmpty);
    });
  });

  group('selected message + inline tap exclusivity', () {
    testWidgets(
      r'$Mobile: selected tap on link toggles only — no linkActivated',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          final linkTaps = <String>[];
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.mobile(),
            onInteraction: (i) {
              if (i case ChatLinkActivated(
                :final url,
                gesture: ChatInlineGesture.tap,
              )) {
                linkTaps.add(url);
              }
            },
          );
          final controller = ChatScrollController();
          final dataSource = _LoadedSource([_msg(1), _msg(2)]);
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

          selection.putBody(
            1,
            Markdown.fromString('Prefix [link text](https://mobile.dev) x.'),
          );
          selection.putBody(2, Markdown.fromString('other'));

          await pumpScroll(
            tester,
            selection: selection,
            dataSource: dataSource,
            controller: controller,
          );

          selection
            ..startSelection(1)
            ..toggle(2);
          await tester.pump();
          expect(selection.selectedIds, <int>{1, 2});

          final down = linkCenter(selection);
          await tester.tapAt(down);
          await tester.pumpAndSettle();

          expect(linkTaps, isEmpty);
          expect(selection.selectedIds, <int>{2});
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      r'$Desktop: selected tap on link activates only — membership unchanged',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final linkTaps = <String>[];
          final selection = ChatSelectionController(
            policy: const ChatSelectionPolicy.desktop(),
            onInteraction: (i) {
              if (i case ChatLinkActivated(
                :final url,
                gesture: ChatInlineGesture.tap,
              )) {
                linkTaps.add(url);
              }
            },
          );
          final controller = ChatScrollController();
          final dataSource = _LoadedSource([_msg(1)]);
          addTearDown(controller.dispose);
          addTearDown(selection.dispose);
          addTearDown(dataSource.dispose);

          selection.putBody(
            1,
            Markdown.fromString('Prefix [link text](https://desk.dev) x.'),
          );

          await pumpScroll(
            tester,
            selection: selection,
            dataSource: dataSource,
            controller: controller,
            platform: TargetPlatform.macOS,
          );

          selection.startSelection(1);
          await tester.pumpAndSettle();
          expect(selection.selectedIds, <int>{1});

          final down = linkCenter(selection);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: down);
          await tester.pump();
          await mouse.down(down);
          await tester.pump();
          expect(
            selection.hasDragSelection,
            isFalse,
            reason: 'short click must not arm drag-deselect over an inline hit',
          );
          await mouse.up();
          await tester.pumpAndSettle();

          // Exclusive: either activate XOR unselect — never both.
          final activated = linkTaps.isNotEmpty;
          final stillSelected = selection.isSelected(1);
          expect(
            activated && stillSelected,
            isTrue,
            reason:
                'desktop policy: link activates and membership stays '
                '(got activated=$activated selected=$stillSelected '
                'ids=${selection.selectedIds} taps=$linkTaps)',
          );
          expect(linkTaps, ['https://desk.dev']);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
