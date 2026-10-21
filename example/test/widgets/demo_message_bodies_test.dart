/// The example's message widget through the real host path: a
/// [DemoMessageBubble] in a [ChatScrollView], over a real asset cache with a
/// fake producer, taps arbitrated by the viewport's selection pointer.
///
/// The engine's own behaviour (hit kinds, spoiler reveal, the layouts) is
/// tested where it lives; these tests pin that the host wired it: the embed
/// resolver is the cache's, the interactions reach the host's handler, and the
/// right body is chosen for each message.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

UserChatMessage _message(
  int id,
  String content, {
  String sender = 'alice',
  bool hasMedia = false,
}) => UserChatMessage(
  id: id,
  sender: sender,
  createdAt: DateTime(2026, 1, 1, 12, 30),
  updatedAt: DateTime(2026, 1, 1, 12, 30),
  content: content,
  hasMedia: hasMedia,
);

/// Global point over rendered-text `[from, to)` of block 0 of [messageId].
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatScrollController controller;
  late FakeAssetProducer producer;
  late AssetCacheScope scope;
  late ValueNotifier<LargeEmojiPolicy> policy;
  late ChatBodyHost host;
  final interactions = <ChatSelectionInteraction>[];

  setUp(() {
    controller = ChatScrollController();
    producer = FakeAssetProducer();
    scope = AssetCacheScope(producer: producer);
    policy = ValueNotifier(const LargeEmojiPolicy(enabled: true));
    host = ChatBodyHost(assets: scope, policy: policy);
    interactions.clear();
  });
  tearDown(() {
    controller.dispose();
    policy.dispose();
    scope.dispose();
  });

  // The platform override is a foundation debug variable: it has to be unset
  // before the test body ends, so it cannot live in a tearDown.
  void bodyTest(
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

  ChatSelectionController newSelection() {
    final selection = ChatSelectionController(
      onInteraction: interactions.add,
      handlesEmbedHits: true,
    );
    addTearDown(selection.dispose);
    return selection;
  }

  Future<void> pump(
    WidgetTester tester,
    ChatSelectionController selection,
    List<UserChatMessage> messages, {
    ChatBodyHost? bodies,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dataSource = _LoadedSource(messages);
    addTearDown(dataSource.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        builder: (context, child) => ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: child!,
        ),
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: ChatScrollView(
              dataSource: dataSource,
              controller: controller,
              selectionController: selection,
              messageBuilder: (context, id, message, status, runLayout) =>
                  buildDemoMessage(
                    context,
                    id,
                    message,
                    status,
                    runLayout,
                    selection: selection,
                    host: bodies ?? host,
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a markdown body', () {
    bodyTest('paints a document embed through the cache, and a tap on it '
        'reaches the host', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, [
        _message(1, 'hi ![wave](document:5368) there'),
      ]);

      final attempt = producer.attempts.single;
      expect(attempt.request.key, const ContentKey.document('5368'));
      final paintable = attempt.advance(AssetStage.full);
      await tester.pump();
      expect(paintable.paints, isNotEmpty);

      await tester.tapAt(_pointOn(selection, 1, 3, 7));
      await tester.pumpAndSettle();

      expect(interactions, const [
        ChatEmbedActivated(
          messageId: 1,
          target: 'document:5368',
          alt: 'wave',
          gesture: ChatInlineGesture.tap,
        ),
      ]);
    });

    bodyTest('shows the alt text of a target the cache does not know', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, [_message(1, 'hi ![wave](other:1) there')]);

      expect(producer.attempts, isEmpty);
      final boxes = selection.surfaceFor(1)!.localBoxesForRange(0, 3, 7);
      expect(boxes, isNotEmpty);
      expect(boxes.first.width, greaterThan(0));
    });

    bodyTest('reveals a hidden spoiler on a tap, and the tap is no hit', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, [_message(1, 'a ||secret|| b')]);
      expect(selection.spoilers.isRevealed(1), isFalse);

      await tester.tapAt(_pointOn(selection, 1, 2, 8));
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isTrue);
      expect(interactions, isEmpty);
    });

    bodyTest('reports a mention and a hashtag with their own fields', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, [
        _message(1, 'a [@Ann](mention:42) b [#tag](hashtag:tag)'),
      ]);

      // Rendered: "a @Ann b #tag".
      await tester.tapAt(_pointOn(selection, 1, 2, 6));
      await tester.pumpAndSettle();
      await tester.tapAt(_pointOn(selection, 1, 9, 13));
      await tester.pumpAndSettle();

      expect(interactions, const [
        ChatResolvedMentionActivated(
          messageId: 1,
          id: '42',
          name: '@Ann',
          gesture: ChatInlineGesture.tap,
        ),
        ChatHashtagActivated(
          messageId: 1,
          tag: 'tag',
          gesture: ChatInlineGesture.tap,
        ),
      ]);
    });
  });

  group('an emoji-only message', () {
    const three = '\u{1F44D}\u{1F680}\u{1F525}';

    bodyTest('three emoji are the emoji body in its text layout', (
      tester,
    ) async {
      await pump(tester, newSelection(), [_message(1, three)]);

      final body = tester.widget<ChatEmojiBody>(find.byType(ChatEmojiBody));
      expect(body.emojiOnly.items, hasLength(3));
      expect(
        ChatEmojiBody.layoutKindFor(body.emojiOnly, sticker: body.sticker),
        ChatEmojiLayoutKind.text,
      );
      expect(find.byType(ChatMarkdownBody), findsNothing);
    });

    bodyTest('the setting turns it off and on while the chat is open', (
      tester,
    ) async {
      await pump(tester, newSelection(), [_message(1, three)]);

      policy.value = const LargeEmojiPolicy(enabled: false);
      await tester.pumpAndSettle();
      expect(find.byType(ChatEmojiBody), findsNothing);
      expect(find.byType(ChatMarkdownBody), findsOneWidget);

      policy.value = const LargeEmojiPolicy(enabled: true);
      await tester.pumpAndSettle();
      expect(find.byType(ChatEmojiBody), findsOneWidget);
      expect(find.byType(ChatMarkdownBody), findsNothing);
    });

    // Android is the platform family that gates on the sticker permission;
    // iOS and desktop do not (04 section 4, row 1).
    bodyTest(
      'a chat that does not allow stickers keeps the markdown body '
      'for a member, not for an admin',
      platform: TargetPlatform.android,
      (tester) async {
        policy.value = const LargeEmojiPolicy(
          enabled: true,
          stickersAllowed: false,
        );
        await pump(tester, newSelection(), [_message(1, three)]);
        expect(find.byType(ChatEmojiBody), findsNothing);

        policy.value = const LargeEmojiPolicy(
          enabled: true,
          stickersAllowed: false,
          isAdmin: true,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ChatEmojiBody), findsOneWidget);
      },
    );

    bodyTest('a message with a link preview stays markdown', (tester) async {
      await pump(tester, newSelection(), [_message(1, three, hasMedia: true)]);

      expect(find.byType(ChatEmojiBody), findsNothing);
      expect(find.byType(ChatMarkdownBody), findsOneWidget);
    });

    bodyTest('text with an emoji is markdown', (tester) async {
      await pump(tester, newSelection(), [_message(1, 'ok $three')]);
      expect(find.byType(ChatEmojiBody), findsNothing);
    });

    bodyTest('a custom emoji is painted through the cache at its own size', (
      tester,
    ) async {
      await pump(tester, newSelection(), [
        _message(1, '![\u{1F680}](document:5368)![\u{1F680}](document:5369)'),
      ]);

      expect(
        {for (final attempt in producer.attempts) attempt.request.key},
        {const ContentKey.document('5368'), const ContentKey.document('5369')},
      );
    });

    bodyTest('a lone unicode emoji with a pack document is a sticker that '
        'plays once per screen', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, [_message(1, '\u{1F44D}')]);

      var body = tester.widget<ChatEmojiBody>(find.byType(ChatEmojiBody));
      expect(
        body.sticker,
        AnimatedEmojiPack.stickerFor(const ContentKey.unicode('\u{1F44D}')),
      );
      expect(
        ChatEmojiBody.layoutKindFor(body.emojiOnly, sticker: body.sticker),
        ChatEmojiLayoutKind.sticker,
      );
      // The host's policy and the screen's memory are the body's.
      expect(body.playback, ChatStickerPlayback.onceThenFirstFrame);
      expect(identical(body.playLedger, host.plays), isTrue);
      expect(host.plays.hasPlayed(1), isFalse, reason: 'not playing yet');

      // The animation arrives and plays: the screen remembers.
      final attempt = producer.attempts.single
        ..advance(
          AssetStage.full,
          tier: AssetTier.animated,
          frames: [const Duration(milliseconds: 40)],
        );
      final paintable = attempt.paintables.single;
      await tester.pump();
      expect(host.plays.hasPlayed(1), isTrue);
      // iOS: a fixed 112 pt sticker.
      expect(attempt.request.spec.pixelWidth, 112);
      expect(paintable.paints.last.context.animate, isTrue);

      // Leaving the screen's view of the row and coming back: the cache keeps
      // the animation, the screen remembers it played, so it rests; a tap
      // plays it.
      await tester.pumpWidget(const SizedBox());
      await pump(tester, selection, [_message(1, '\u{1F44D}')]);
      await tester.pump();
      expect(paintable.paints.last.context.animate, isFalse);

      await tester.tapAt(tester.getCenter(find.byType(ChatEmojiBody)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(paintable.paints.last.context.animate, isTrue);
    });

    bodyTest('a lone unicode emoji the pack lacks is text, not a sticker', (
      tester,
    ) async {
      await pump(tester, newSelection(), [_message(1, '\u{1F9A5}')]);

      final body = tester.widget<ChatEmojiBody>(find.byType(ChatEmojiBody));
      expect(body.sticker, isNull);
    });

    bodyTest('a lone custom emoji is its own sticker and loops', (
      tester,
    ) async {
      await pump(tester, newSelection(), [
        _message(1, '![\u{1F680}](document:5368)'),
      ]);

      final body = tester.widget<ChatEmojiBody>(find.byType(ChatEmojiBody));
      expect(body.sticker, const ContentKey.document('5368'));
    });

    bodyTest('is bubble-less and its text layout registers as selectable '
        'text', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, [_message(1, three)]);

      expect(selection.bodyOf(1), isNotNull);
      expect(selection.surfaceFor(1), isNotNull);
      expect(find.byType(ChatMessageChangeTransition), findsNothing);
    });
  });
}
