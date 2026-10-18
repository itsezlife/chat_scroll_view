import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kPrimaryMouseButton, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter_md/flutter_md.dart' show MD$Paragraph, MarkdownWidget;
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

/// Global point over the glyph boxes of rendered-text [from]..[to] of block 0
/// of [messageId]: the middle of the span the test wants to tap.
Offset _pointOn(
  ChatSelectionController selection,
  int messageId,
  int from,
  int to,
) {
  final surface = selection.surfaceFor(messageId)!;
  final boxes = surface.localBoxesForRange(0, from, to);
  return (surface as RenderBox).localToGlobal(boxes.first.center);
}

/// The inline layer through the real host path: [ChatMarkdownBody] in a
/// [ChatScrollView], taps arbitrated by the viewport's selection pointer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LoadedSource dataSource;
  late ChatScrollController controller;
  late FakeInlineEmbedResolver embeds;
  final interactions = <ChatSelectionInteraction>[];
  final idleTaps = <int>[];
  final secondaryTaps = <int>[];

  // The platform override is a foundation debug variable: it has to be unset
  // before the test body ends, so it cannot live in a tearDown.
  void inlineTest(
    String name,
    Future<void> Function(WidgetTester) body, {
    TargetPlatform platform = TargetPlatform.iOS,
  }) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  setUp(() {
    controller = ChatScrollController();
    embeds = FakeInlineEmbedResolver();
    interactions.clear();
    idleTaps.clear();
    secondaryTaps.clear();
  });
  tearDown(() => controller.dispose());

  ChatSelectionController newSelection({
    bool handlesEmbedHits = false,
    PlaybackClock? spoilerClock,
    ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
  }) {
    final selection = ChatSelectionController(
      policy: policy,
      onInteraction: interactions.add,
      handlesEmbedHits: handlesEmbedHits,
      spoilerClock: spoilerClock,
    );
    addTearDown(selection.dispose);
    return selection;
  }

  Future<void> pump(
    WidgetTester tester,
    ChatSelectionController selection,
    Map<int, String> bodies, {
    InlineEmbedResolver? resolver,
    TextDirection direction = TextDirection.ltr,
    bool secondaryMenu = false,
  }) async {
    dataSource = _LoadedSource([for (final id in bodies.keys) _msg(id)]);
    addTearDown(dataSource.dispose);
    for (final MapEntry(:key, :value) in bodies.entries) {
      selection.putBody(key, Markdown.fromString(value));
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatScrollView(
                dataSource: dataSource,
                controller: controller,
                selectionController: selection,
                onIdleMessageTap: (request) => idleTaps.add(request.messageId),
                onSecondaryMessageTap: secondaryMenu
                    ? (request) => secondaryTaps.add(request.messageId)
                    : null,
                messageBuilder: (context, id, message, status, runLayout) =>
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.white,
                      child: ChatMarkdownBody(
                        key: ValueKey('md-$id'),
                        controller: selection,
                        messageId: id,
                        embedResolver: resolver,
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('embeds', () {
    inlineTest('are resolved and painted in the text', (tester) async {
      final selection = newSelection();

      await pump(tester, selection, {
        1: 'hi ![:wave:](fake:1) there',
      }, resolver: embeds);
      final made = embeds.made.single;
      expect(made.paints, isNotEmpty);
      expect(made.isDisposed, isFalse);
      expect(embeds.asked.single.alt, ':wave:');
    });

    inlineTest('survive the body rebuilding', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, {
        1: 'hi ![:wave:](fake:1) there',
      }, resolver: embeds);

      tester.element(find.byKey(const ValueKey('md-1'))).markNeedsBuild();
      await tester.pump();

      expect(embeds.made, hasLength(1));
      expect(embeds.made.single.isDisposed, isFalse);
    });

    inlineTest('a body with no resolver shows the alt text', (tester) async {
      final selection = newSelection();

      await pump(tester, selection, {1: 'hi ![:wave:](fake:1) there'});

      expect(embeds.made, isEmpty);
      expect(selection.textSelectionPlainText(), isNull);
      expect(selection.bodyOf(1), isNotNull);
    });

    inlineTest('a tap is an embed hit when the host handles them', (
      tester,
    ) async {
      final selection = newSelection(handlesEmbedHits: true);
      await pump(tester, selection, {
        1: 'hi ![:wave:](fake:1) there',
      }, resolver: embeds);

      await tester.tapAt(_pointOn(selection, 1, 3, 9));
      await tester.pumpAndSettle();

      expect(interactions, const [
        ChatEmbedActivated(
          messageId: 1,
          target: 'fake:1',
          alt: ':wave:',
          gesture: ChatInlineGesture.tap,
        ),
      ]);
      expect(idleTaps, isEmpty);
    });

    inlineTest('a tap is an ordinary message tap when the host does not', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {
        1: 'hi ![:wave:](fake:1) there',
      }, resolver: embeds);

      await tester.tapAt(_pointOn(selection, 1, 3, 9));
      await tester.pumpAndSettle();

      expect(interactions, isEmpty);
      expect(idleTaps, [1]);
    });
  });

  group('mentions and hashtags', () {
    inlineTest('a tap on each reaches the host as its own interaction', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {
        1: 'a [@Ann](mention:42) b [@bob](username:bob) c [#tag](hashtag:tag)',
      });

      // Rendered: "a @Ann b @bob c #tag".
      await tester.tapAt(_pointOn(selection, 1, 2, 6));
      await tester.pumpAndSettle();
      await tester.tapAt(_pointOn(selection, 1, 9, 13));
      await tester.pumpAndSettle();
      await tester.tapAt(_pointOn(selection, 1, 16, 20));
      await tester.pumpAndSettle();

      expect(interactions, const [
        ChatResolvedMentionActivated(
          messageId: 1,
          id: '42',
          name: '@Ann',
          gesture: ChatInlineGesture.tap,
        ),
        ChatUsernameMentionActivated(
          messageId: 1,
          name: 'bob',
          gesture: ChatInlineGesture.tap,
        ),
        ChatHashtagActivated(
          messageId: 1,
          tag: 'tag',
          gesture: ChatInlineGesture.tap,
        ),
      ]);
      expect(interactions.whereType<ChatLinkActivated>(), isEmpty);
    });
  });

  group('spoilers', () {
    inlineTest('a tap on a hidden spoiler reveals that message only', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y', 2: 'x ||other|| y'});

      await tester.tapAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isTrue);
      expect(selection.spoilers.isRevealed(2), isFalse);
    });

    inlineTest('a tap on a hidden spoiler is the reveal and no message tap', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y'});

      await tester.tapAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isTrue);
      expect(idleTaps, isEmpty);
      expect(interactions, isEmpty);
      expect(selection.isSelectionMode, isFalse);
    });

    inlineTest('the next tap on the revealed text is a message tap', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y'});
      await tester.tapAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();

      await tester.tapAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();

      expect(idleTaps, [1]);
    });

    inlineTest(
      'a tap beside the spoiler in the same message is a message tap',
      (tester) async {
        final selection = newSelection();
        await pump(tester, selection, {1: 'x ||secret|| y'});

        await tester.tapAt(_pointOn(selection, 1, 0, 1));
        await tester.pumpAndSettle();

        expect(selection.spoilers.isRevealed(1), isFalse);
        expect(idleTaps, [1]);
      },
    );

    inlineTest('revealing one message leaves another hidden spoiler tappable', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y', 2: 'x ||other|| y'});
      await tester.tapAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();

      await tester.tapAt(_pointOn(selection, 2, 2, 7));
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(2), isTrue);
      expect(idleTaps, isEmpty);
    });

    inlineTest('a long press on a hidden spoiler selects the message', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y'});

      await tester.longPressAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();

      expect(selection.isSelected(1), isTrue);
      expect(idleTaps, isEmpty);
      expect(selection.spoilers.isRevealed(1), isFalse);
    });

    inlineTest('a drag starting on a hidden spoiler neither reveals nor taps', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y'});

      await tester.dragFrom(_pointOn(selection, 1, 2, 8), const Offset(0, 80));
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isFalse);
      expect(idleTaps, isEmpty);
      expect(selection.isSelectionMode, isFalse);
    });

    inlineTest('a tap on a hidden spoiler in message selection toggles', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y', 2: 'plain'});
      final spoiler = _pointOn(selection, 1, 2, 8);
      selection.startSelection(2);
      await tester.pumpAndSettle();

      await tester.tapAt(spoiler);
      await tester.pumpAndSettle();

      expect(selection.isSelected(1), isTrue);
      expect(idleTaps, isEmpty);
    });

    inlineTest('revealed state survives the row leaving and coming back', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y'});
      await tester.tapAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();
      expect(selection.spoilers.isRevealed(1), isTrue);

      await tester.pumpWidget(const SizedBox());
      await pump(tester, selection, {1: 'x ||secret|| y'});

      expect(selection.spoilers.isRevealed(1), isTrue);
      expect(find.byType(MarkdownWidget), findsOneWidget);
      expect(
        selection.spoilers.wantsTicks.value,
        isFalse,
        reason: 'a revealed body has no dust to move',
      );
    });

    inlineTest('a tap on a link in a hidden spoiler reveals, no hit', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||[site](https://a.b)|| y'});

      await tester.tapAt(_pointOn(selection, 1, 2, 6));
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isTrue);
      expect(interactions, isEmpty);

      await tester.tapAt(_pointOn(selection, 1, 2, 6));
      await tester.pumpAndSettle();

      expect(interactions.single, isA<ChatLinkActivated>());
    });

    inlineTest('a tap on a mention in a hidden spoiler reveals, no hit', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||[@Ann](mention:42)|| y'});

      await tester.tapAt(_pointOn(selection, 1, 2, 6));
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isTrue);
      expect(interactions, isEmpty);
    });

    inlineTest('a tap on an embed in a hidden spoiler reveals, no hit', (
      tester,
    ) async {
      final selection = newSelection(handlesEmbedHits: true);
      await pump(tester, selection, {
        1: 'x ||![:wave:](fake:1)|| y',
      }, resolver: embeds);

      await tester.tapAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isTrue);
      expect(interactions, isEmpty);
    });

    inlineTest('a body whose surface is not mounted still hides its spoilers', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y', 2: 'plain'});
      expect(selection.spoilers.wantsTicks.value, isTrue);

      // Message selection on 2 unmounts 1's selection surface.
      selection.startSelection(2);
      await tester.pumpAndSettle();

      expect(selection.surfaceFor(1), isNull);
      expect(selection.spoilers.isRevealed(1), isFalse);
      expect(
        selection.spoilers.wantsTicks.value,
        isTrue,
        reason: 'the hidden spoiler is still on screen and still moves',
      );
    });
  });

  group('spoilers under the desktop policy', () {
    Future<void> click(
      WidgetTester tester,
      Offset at, {
      int buttons = kPrimaryMouseButton,
    }) async {
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: buttons,
      );
      await mouse.down(at);
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
    }

    ChatSelectionController desktop() =>
        newSelection(policy: const ChatSelectionPolicy.desktop());

    inlineTest(
      'a click on a hidden spoiler is the reveal only',
      (tester) async {
        final selection = desktop();
        await pump(tester, selection, {1: 'x ||secret|| y'});

        await click(tester, _pointOn(selection, 1, 2, 8));

        expect(selection.spoilers.isRevealed(1), isTrue);
        expect(interactions, isEmpty);
        expect(selection.isSelectionMode, isFalse);
        // The click arms the body as any click on text does; it selects nothing.
        expect(
          selection.markdownSelection.selection?.isCollapsed ?? true,
          isTrue,
        );
      },
      platform: TargetPlatform.macOS,
    );

    inlineTest(
      'a secondary click on a hidden spoiler opens the menu only',
      (tester) async {
        final selection = desktop();
        await pump(tester, selection, {
          1: 'x ||secret|| y',
        }, secondaryMenu: true);

        await click(
          tester,
          _pointOn(selection, 1, 2, 8),
          buttons: kSecondaryMouseButton,
        );

        expect(secondaryTaps, [1]);
        expect(selection.spoilers.isRevealed(1), isFalse);
      },
      platform: TargetPlatform.macOS,
    );

    inlineTest(
      'a drag from a hidden spoiler selects text and reveals',
      (tester) async {
        final selection = desktop();
        await pump(tester, selection, {1: 'x ||secret|| y'});
        final start = _pointOn(selection, 1, 2, 3);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.down(start);
        await mouse.moveBy(const Offset(40, 0));
        await mouse.up();
        await tester.pumpAndSettle();

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.spoilers.isRevealed(1), isTrue);
      },
      platform: TargetPlatform.macOS,
    );
  });

  group('the cursor over a body', () {
    TestGesture? mouse;
    setUp(() => mouse = null);

    Future<MouseCursor> hover(
      WidgetTester tester,
      ChatSelectionController selection,
      int from,
      int to,
    ) async {
      var pointer = mouse;
      if (pointer == null) {
        pointer = mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: const Offset(1, 1));
        addTearDown(pointer.removePointer);
      }
      await pointer.moveTo(_pointOn(selection, 1, from, to));
      await tester.pump();
      // The first mouse a test creates is device 1.
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;
    }

    inlineTest(
      'is a click over a mention, a username and a hashtag',
      (tester) async {
        final selection = newSelection(
          policy: const ChatSelectionPolicy.desktop(),
        );
        await pump(tester, selection, {
          1: 'a [@Ann](mention:42) b [@bob](username:bob) c [#tag](hashtag:tag)',
        });

        expect(await hover(tester, selection, 2, 6), SystemMouseCursors.click);
        expect(await hover(tester, selection, 9, 13), SystemMouseCursors.click);
        expect(
          await hover(tester, selection, 16, 20),
          SystemMouseCursors.click,
        );
        expect(await hover(tester, selection, 0, 1), SystemMouseCursors.text);
      },
      platform: TargetPlatform.macOS,
    );

    inlineTest(
      'is a click over an embed only when the host handles them',
      (tester) async {
        final inert = newSelection(policy: const ChatSelectionPolicy.desktop());
        await pump(tester, inert, {
          1: 'hi ![:wave:](fake:1) there',
        }, resolver: embeds);
        expect(await hover(tester, inert, 3, 9), SystemMouseCursors.text);

        final live = newSelection(
          policy: const ChatSelectionPolicy.desktop(),
          handlesEmbedHits: true,
        );
        await pump(tester, live, {
          1: 'hi ![:wave:](fake:1) there',
        }, resolver: embeds);
        expect(await hover(tester, live, 3, 9), SystemMouseCursors.click);
      },
      platform: TargetPlatform.macOS,
    );

    inlineTest('is a click over a hidden spoiler', (tester) async {
      final selection = newSelection(
        policy: const ChatSelectionPolicy.desktop(),
      );
      await pump(tester, selection, {1: 'x ||secret|| y'});

      expect(await hover(tester, selection, 2, 8), SystemMouseCursors.click);
    }, platform: TargetPlatform.macOS);
  });

  group('copy', () {
    inlineTest('the plain text is the revealed text with the embed\'s alt', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {
        1: 'hi [@Ann](mention:42) ![:wave:](fake:1) ||secret|| **end**',
      }, resolver: embeds);
      selection.startSelection(1);
      await tester.pumpAndSettle();

      expect(selection.enterTextSelection(1), isTrue);
      await tester.pumpAndSettle();

      expect(selection.textSelectionPlainText(), 'hi @Ann :wave: secret end');
      expect(selection.spoilers.isRevealed(1), isTrue);
    });

    inlineTest('hands a host writer the structure, spoiler and embed spans', (
      tester,
    ) async {
      ChatTextCopy? copied;
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
        copyWriter: (copy) async => copied = copy,
      );
      addTearDown(selection.dispose);
      await pump(tester, selection, {
        1: '[@Ann](mention:42) ![:wave:](fake:1) ||secret||',
      }, resolver: embeds);
      selection
        ..startSelection(1)
        ..enterTextSelection(1);
      await tester.pumpAndSettle();

      await selection.copyTextSelection();

      expect(copied!.plainText, '@Ann :wave: secret');
      final spans = [
        for (final block in copied!.content!.documents.single.blocks)
          if (block.block case MD$Paragraph(:final spans)) ...spans,
      ];
      expect(
        [for (final span in spans) span.style.styles],
        containsAll(<Set<String>>[
          {'mention'},
          {'image'},
          {'spoiler'},
        ]),
      );
    });
  });

  group('the dust clock', () {
    late ManualPlaybackTickSource ticks;
    late PlaybackClock clock;

    setUp(() {
      ticks = ManualPlaybackTickSource();
      clock = PlaybackClock(ticks: ticks);
    });
    tearDown(() => clock.dispose());

    inlineTest('runs while a hidden spoiler is on screen and feeds it', (
      tester,
    ) async {
      final selection = newSelection(spoilerClock: clock);
      await pump(tester, selection, {1: 'x ||secret|| y'});

      expect(ticks.isRunning, isTrue);
      ticks.tick(const Duration(seconds: 1));
      expect(selection.spoilers.fillFrame, 30);
      ticks.tick(const Duration(seconds: 2));
      expect(selection.spoilers.fillFrame, 60);
    });

    inlineTest('sleeps once nothing hidden is on screen', (tester) async {
      final selection = newSelection(spoilerClock: clock);
      await pump(tester, selection, {1: 'x ||secret|| y'});
      expect(ticks.isRunning, isTrue);

      await tester.tapAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();

      expect(ticks.isRunning, isFalse);
    });

    inlineTest('is paused by the cache clock\'s pause layers', (tester) async {
      final selection = newSelection(spoilerClock: clock);
      await pump(tester, selection, {1: 'x ||secret|| y'});

      clock.setPaused(PlaybackPauseLayer.fastScroll, paused: true);

      expect(ticks.isRunning, isFalse);
    });

    inlineTest('a controller with no clock leaves the dust still', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, {1: 'x ||secret|| y'});

      expect(selection.spoilers.fillFrame, 0);
      expect(ticks.starts, 0);
    });
  });
}
