import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
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
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    final ids = messages.map((m) => m.id).toList()..sort();
    seedBoundaries(oldestKnownId: ids.first, newestKnownId: ids.last, reachedOldest: true, reachedNewest: true);
  }

  @override
  Future<List<IChatMessage>> fetchRange({required int fromId, required int toId}) async => const <IChatMessage>[];
}

const _thumb = ContentKey.unicode('\u{1F44D}');

/// A ledger the test can read.
final class _Ledger implements ChatStickerPlayLedger {
  final played = <int>{};

  @override
  bool hasPlayed(int messageId) => played.contains(messageId);

  @override
  void markPlayed(int messageId) => played.add(messageId);
}

const _pack = ContentKey.document('thumb-sticker');

/// The emoji-only body through the real host path: [ChatEmojiBody] in a
/// [ChatScrollView], gestures arbitrated by the viewport's selection pointer,
/// playback by a real asset cache on a manual clock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatScrollController controller;
  late FakeAssetProducer producer;
  late ManualPlaybackTickSource ticks;
  late AssetCacheScope scope;
  final interactions = <ChatSelectionInteraction>[];
  final idleTaps = <int>[];
  // The facade's monotonic clock.
  var now = const Duration(seconds: 5);

  void viewportTest(
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
    producer = FakeAssetProducer();
    ticks = ManualPlaybackTickSource();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ticks),
    );
    interactions.clear();
    idleTaps.clear();
    now = const Duration(seconds: 5);
  });
  tearDown(() {
    controller.dispose();
    scope.dispose();
  });

  ChatSelectionController newSelection({
    bool handlesEmbedHits = false,
    ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
  }) {
    final selection = ChatSelectionController(
      policy: policy,
      onInteraction: interactions.add,
      handlesEmbedHits: handlesEmbedHits,
      monotonicClock: () => now,
    );
    addTearDown(selection.dispose);
    return selection;
  }

  InlineEmbed? factory(ContentKey content, AssetPreset preset) =>
      ContentEmbed(scope: scope, content: content, preset: preset);

  // A pass of 180 ms: the frames the animated stage plays.
  const frames = [Duration(milliseconds: 40), Duration(milliseconds: 60), Duration(milliseconds: 80)];

  // Every attempt the cache started reaches its animated stage.
  void finishAttempts() {
    for (final attempt in producer.attempts) {
      attempt.advance(AssetStage.full, tier: AssetTier.animated, frames: frames);
    }
  }

  // The engine's frame at [ms]: the clock ticks and the surface repaints.
  Future<void> frame(WidgetTester tester, int ms) async {
    ticks.tick(Duration(milliseconds: ms));
    await tester.pump();
  }

  // Plays the sticker's pass to its end, the end heard on the tick after. The
  // pass began at the first paint, with the clock still at zero.
  Future<void> playPass(WidgetTester tester, {int from = 0}) async {
    await frame(tester, from);
    await frame(tester, from + 40);
    await frame(tester, from + 100);
    await frame(tester, from + 180);
    await frame(tester, from + 220);
  }

  FakeAssetPaintable stickerPaintable() => producer.attempts.last.paintables.last;

  Future<void> pump(
    WidgetTester tester,
    ChatSelectionController selection,
    EmojiOnly emojiOnly, {
    ContentKey? sticker,
    ChatStickerPlayLedger? ledger,
    ChatStickerPlayback? playback,
    ChatStickerTapPolicy? tapPolicy,
    bool isActive = true,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dataSource = _LoadedSource([_msg(1)]);
    addTearDown(dataSource.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: debugDefaultTargetPlatformOverride),
        home: Scaffold(
          body: ChatScrollView(
            dataSource: dataSource,
            controller: controller,
            selectionController: selection,
            onIdleMessageTap: (request) => idleTaps.add(request.messageId),
            messageBuilder: (context, id, message, status, runLayout) => id != 1
                ? const SizedBox(height: 10)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: ChatEmojiBody(
                      key: ValueKey('emoji-$id'),
                      controller: selection,
                      messageId: id,
                      emojiOnly: emojiOnly,
                      sticker: sticker,
                      playLedger: ledger,
                      playback: playback,
                      tapPolicy: tapPolicy,
                      isActive: isActive,
                      // A sticker takes the policy with an inset around the
                      // art, so a tap beside it is still inside the cell.
                      policy: sticker == null ? const ChatEmojiPolicy.android() : const ChatEmojiPolicy.ios(),
                      embedFactory: factory,
                    ),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    finishAttempts();
    await tester.pump();
  }

  // The sticker is 112 pt square, 10 pt inside the body's box (iOS).
  Rect drawn(WidgetTester tester) =>
      (tester.getTopLeft(find.byType(ChatEmojiBody)) + const Offset(10, 10)) & const Size.square(112);

  final threeCustom = EmojiOnly([for (var i = 0; i < 3; i++) EmojiOnlyItem(ContentKey.document('d$i'))]);
  final oneThumb = EmojiOnly(const [EmojiOnlyItem(_thumb)]);

  Offset itemCenter(WidgetTester tester, int index, {double box = 59.2}) {
    final rect = tester.getRect(find.byType(ChatEmojiBody));
    return Offset(rect.left + box * (index + 0.5), rect.center.dy);
  }

  group('taps', () {
    viewportTest('a tap on a custom emoji is an embed hit when the host '
        'handles them', (tester) async {
      final selection = newSelection(handlesEmbedHits: true);
      await pump(tester, selection, threeCustom);

      await tester.tapAt(itemCenter(tester, 1));
      await tester.pumpAndSettle();

      expect(interactions, const [
        ChatEmbedActivated(messageId: 1, target: 'document:d1', alt: '', gesture: ChatInlineGesture.tap),
      ]);
      expect(idleTaps, isEmpty);
    });

    viewportTest('without the opt-in it is an ordinary message tap', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, threeCustom);

      await tester.tapAt(itemCenter(tester, 1));
      await tester.pumpAndSettle();

      expect(interactions, isEmpty);
      expect(idleTaps, [1]);
    });

    viewportTest('a tap on the sticker is a sticker hit, with no opt-in', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);

      await tester.tapAt(drawn(tester).center);
      await tester.pumpAndSettle();

      expect(interactions, [
        ChatStickerActivated(
          messageId: 1,
          content: _thumb,
          gesture: ChatInlineGesture.tap,
          stickerRect: drawn(tester),
          tapTime: now,
        ),
      ]);
      expect(idleTaps, isEmpty);
    });

    viewportTest('the facade resolves the sticker hit', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);

      expect(
        selection.resolveInlineHit(1, drawn(tester).center),
        ChatInlineHit.sticker(messageId: 1, content: _thumb, stickerRect: drawn(tester)),
      );
    });
  });

  group('selection', () {
    viewportTest('a long press enters message selection, never text '
        'selection', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, threeCustom);

      await tester.longPressAt(itemCenter(tester, 0));
      await tester.pumpAndSettle();

      expect(selection.isSelected(1), isTrue);
      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelection, isNull);
      expect(await selection.copyTextSelection(), isFalse);
    });

    viewportTest('a long press on the sticker is message selection', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);

      await tester.longPressAt(drawn(tester).center);
      await tester.pumpAndSettle();

      expect(selection.isSelected(1), isTrue);
      expect(selection.isTextSelectionActive, isFalse);
    });

    viewportTest('a long press again enters text selection (message, then '
        'text), on one emoji', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, threeCustom);
      await tester.longPressAt(itemCenter(tester, 0));
      await tester.pumpAndSettle();

      await tester.longPressAt(itemCenter(tester, 2));
      await tester.pumpAndSettle();

      expect(selection.isTextSelectionActive, isTrue);
      expect(selection.textSelectionSubject, 1);
      // The third emoji: one atomic item (a custom emoji with no text copies
      // as the object replacement character).
      expect(selection.markdownSelection.getText(), '\u{FFFC}');
    });

    viewportTest('on desktop a click selects the message in selection mode', (tester) async {
      final selection = newSelection(policy: const ChatSelectionPolicy.desktop());
      await pump(tester, selection, threeCustom);
      selection.toggle(1);
      await tester.pump();

      await tester.tapAt(itemCenter(tester, 1));
      await tester.pumpAndSettle();

      expect(selection.isSelected(1), isFalse);
      expect(selection.isTextSelectionActive, isFalse);
    }, platform: TargetPlatform.macOS);
  });

  group('playback', () {
    viewportTest('custom emoji animate and loop', (tester) async {
      final selection = newSelection();

      await pump(tester, selection, threeCustom);

      expect(ticks.isRunning, isTrue);
      for (final attempt in producer.attempts) {
        expect(attempt.request.spec.pixelWidth, 60);
      }
    });

    viewportTest('a sticker the ledger says played shows the first frame and '
        'does not start', (tester) async {
      final selection = newSelection();

      await pump(tester, selection, oneThumb, sticker: _pack, ledger: _Ledger()..played.add(1));

      expect(producer.attempts, hasLength(1));
      expect(ticks.isRunning, isFalse);
    });

    viewportTest('a first show starts the sticker and records it', (tester) async {
      final selection = newSelection();
      final ledger = _Ledger();

      await pump(tester, selection, oneThumb, sticker: _pack, ledger: ledger);

      expect(ticks.isRunning, isTrue);
      expect(ledger.played, {1});
    });

    viewportTest('the pass ends, the sticker rests and stops costing ticks', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);

      await playPass(tester);

      expect(ticks.isRunning, isFalse);
      expect(stickerPaintable().isHolding, isTrue);
    });

    viewportTest('a tap on the resting sticker plays another pass', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);
      await playPass(tester);

      await tester.tapAt(drawn(tester).center);
      await tester.pump();

      expect(stickerPaintable().restarts, 1);
      expect(ticks.isRunning, isTrue);
      expect(idleTaps, isEmpty);
    });

    viewportTest('a tap on a sticker that is still playing does not restart '
        'it, and is still the host\'s interaction', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);
      await frame(tester, 0);
      await frame(tester, 40);

      await tester.tapAt(drawn(tester).center);
      await tester.pump();

      expect(stickerPaintable().restarts, 0);
      expect(stickerPaintable().frameShown, 1, reason: 'not rewound');
      expect(interactions.whereType<ChatStickerActivated>(), hasLength(1));
    });

    viewportTest('a tap on a held sticker plays it', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack, ledger: _Ledger()..played.add(1));
      expect(ticks.isRunning, isFalse);

      await tester.tapAt(drawn(tester).center);
      await tester.pumpAndSettle();

      expect(ticks.isRunning, isTrue);
    });

    viewportTest('a sticker that loops is never replayed: it never ends', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack, playback: ChatStickerPlayback.loop);
      await playPass(tester);

      await tester.tapAt(drawn(tester).center);
      await tester.pump();

      expect(ticks.isRunning, isTrue);
      expect(stickerPaintable().restarts, 0);
    });

    viewportTest('rest on the last frame when the host asks', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack, playback: ChatStickerPlayback.onceThenLastFrame);

      await playPass(tester);

      expect(stickerPaintable().isHolding, isTrue);
      expect(stickerPaintable().frameShown, 2);
    });

    viewportTest('an inactive row does not play, and plays when it is '
        'active', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack, isActive: false);
      expect(ticks.isRunning, isFalse);

      await pump(tester, selection, oneThumb, sticker: _pack);

      expect(ticks.isRunning, isTrue);
    });

    viewportTest('a paused clock holds the pass until the host resumes it', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);
      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: true);

      expect(ticks.isRunning, isFalse);
      scope.clock.setPaused(PlaybackPauseLayer.lowPower, paused: false);
      expect(ticks.isRunning, isTrue);
    });

    viewportTest('the sticker is decoded at its drawn extent', (tester) async {
      final selection = newSelection();

      await pump(tester, selection, oneThumb, sticker: _pack);

      // iOS: a fixed 112 pt, at 1x.
      expect(producer.attempts.single.request.spec.pixelWidth, 112);
    });
  });

  group('tap policy', () {
    // A tap 5 dp beside the sticker: in the body's inset, inside the cell.
    Offset beside(WidgetTester tester) => drawn(tester).topLeft - const Offset(5, 5);

    for (final (name, policy, platform) in [
      ('mobile', const ChatSelectionPolicy.mobile(), TargetPlatform.iOS),
      ('desktop', const ChatSelectionPolicy.desktop(), TargetPlatform.macOS),
    ]) {
      viewportTest('$name: a tap beside the sticker is an ordinary message tap', (tester) async {
        final selection = newSelection(policy: policy);
        await pump(tester, selection, oneThumb, sticker: _pack);
        await playPass(tester);

        await tester.tapAt(beside(tester));
        await tester.pumpAndSettle();

        expect(interactions.whereType<ChatStickerActivated>(), isEmpty);
        expect(stickerPaintable().restarts, 0);
        expect(
          idleTaps,
          policy is ChatSelectionPolicy$Mobile ? [1] : isEmpty,
          reason: 'desktop has no idle message tap, mobile opens the menu',
        );
      }, platform: platform);

      viewportTest('$name: with a replay tap slop that tap is the sticker\'s', (tester) async {
        final selection = newSelection(policy: policy);
        await pump(
          tester,
          selection,
          oneThumb,
          sticker: _pack,
          tapPolicy: ChatStickerTapPolicy.of(policy, replayTapSlop: 8),
        );
        await playPass(tester);

        await tester.tapAt(beside(tester));
        await tester.pumpAndSettle();

        expect(interactions.whereType<ChatStickerActivated>(), hasLength(1));
        expect(stickerPaintable().restarts, 1);
        expect(idleTaps, isEmpty);
      }, platform: platform);

      viewportTest('$name: a tap on the row outside the body is not the sticker\'s', (tester) async {
        final selection = newSelection(policy: policy);
        await pump(tester, selection, oneThumb, sticker: _pack);

        await tester.tapAt(const Offset(390, 400));
        await tester.pumpAndSettle();

        expect(interactions, isEmpty);
      }, platform: platform);
    }

    viewportTest('mobile: a long press selects the message, tells the host and '
        'restarts the sticker', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);
      await playPass(tester);

      await tester.longPressAt(drawn(tester).center);
      await tester.pumpAndSettle();

      expect(selection.isSelected(1), isTrue);
      expect(interactions.single, isA<ChatStickerActivated>());
      expect((interactions.single as ChatStickerActivated).gesture, ChatInlineGesture.longPress);
      expect(stickerPaintable().restarts, 1);
    });

    viewportTest('the tap time follows the facade\'s clock', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);

      await tester.tapAt(drawn(tester).center);
      await tester.pump(const Duration(milliseconds: 400));
      now += const Duration(milliseconds: 400);
      await tester.tapAt(drawn(tester).center);
      await tester.pumpAndSettle();

      final times = interactions.whereType<ChatStickerActivated>().map((a) => a.tapTime).toList();
      expect(times, [const Duration(seconds: 5), const Duration(seconds: 5, milliseconds: 400)]);
    });
  });
}
