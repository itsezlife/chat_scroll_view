import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart' show MarkdownWidget;
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

  // The platform override is a foundation debug variable: it has to be unset
  // before the test body ends, so it cannot live in a tearDown.
  void inlineTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
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
  });
  tearDown(() => controller.dispose());

  ChatSelectionController newSelection({
    bool handlesEmbedHits = false,
    PlaybackClock? spoilerClock,
  }) {
    final selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.mobile(),
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
        ChatMentionActivated(
          messageId: 1,
          kind: ChatMentionKind.resolved,
          id: '42',
          name: '@Ann',
          gesture: ChatInlineGesture.tap,
        ),
        ChatMentionActivated(
          messageId: 1,
          kind: ChatMentionKind.username,
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
