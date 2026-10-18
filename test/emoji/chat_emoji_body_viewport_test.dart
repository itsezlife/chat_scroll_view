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

const _thumb = ContentKey.unicode('\u{1F44D}');
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
    );
    addTearDown(selection.dispose);
    return selection;
  }

  InlineEmbed? factory(ContentKey content, AssetPreset preset) =>
      ContentEmbed(scope: scope, content: content, preset: preset);

  // Every attempt the cache started reaches its animated stage.
  void finishAttempts() {
    for (final attempt in producer.attempts) {
      attempt.advance(
        AssetStage.full,
        tier: AssetTier.animated,
        animated: true,
      );
    }
  }

  Future<void> pump(
    WidgetTester tester,
    ChatSelectionController selection,
    EmojiOnly emojiOnly, {
    ContentKey? sticker,
    bool autoplay = true,
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
                      autoplay: autoplay,
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

  final threeCustom = EmojiOnly([
    for (var i = 0; i < 3; i++) EmojiOnlyItem(ContentKey.document('d$i')),
  ]);
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
        ChatEmbedActivated(
          messageId: 1,
          target: 'document:d1',
          alt: '',
          gesture: ChatInlineGesture.tap,
        ),
      ]);
      expect(idleTaps, isEmpty);
    });

    viewportTest('without the opt-in it is an ordinary message tap', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, threeCustom);

      await tester.tapAt(itemCenter(tester, 1));
      await tester.pumpAndSettle();

      expect(interactions, isEmpty);
      expect(idleTaps, [1]);
    });

    viewportTest('a tap on the sticker is a sticker hit, with no opt-in', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);

      await tester.tapAt(tester.getCenter(find.byType(ChatEmojiBody)));
      await tester.pumpAndSettle();

      expect(interactions, const [
        ChatStickerActivated(
          messageId: 1,
          content: _thumb,
          gesture: ChatInlineGesture.tap,
        ),
      ]);
      expect(idleTaps, isEmpty);
    });

    viewportTest('the facade resolves the sticker hit', (tester) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);

      expect(
        selection.resolveInlineHit(
          1,
          tester.getCenter(find.byType(ChatEmojiBody)),
        ),
        const ChatInlineHit.sticker(messageId: 1, content: _thumb),
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

    viewportTest('a long press on the sticker is message selection', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack);

      await tester.longPressAt(tester.getCenter(find.byType(ChatEmojiBody)));
      await tester.pumpAndSettle();

      expect(selection.isSelected(1), isTrue);
      expect(selection.isTextSelectionActive, isFalse);
      expect(interactions.whereType<ChatStickerActivated>(), isEmpty);
    });

    viewportTest('a long press again does not start text selection', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, threeCustom);
      await tester.longPressAt(itemCenter(tester, 0));
      await tester.pumpAndSettle();

      await tester.longPressAt(itemCenter(tester, 2));
      await tester.pumpAndSettle();

      expect(selection.isTextSelectionActive, isFalse);
    });

    viewportTest(
      'on desktop a click selects the message in selection mode',
      (tester) async {
        final selection = newSelection(
          policy: const ChatSelectionPolicy.desktop(),
        );
        await pump(tester, selection, threeCustom);
        selection.toggle(1);
        await tester.pump();

        await tester.tapAt(itemCenter(tester, 1));
        await tester.pumpAndSettle();

        expect(selection.isSelected(1), isFalse);
        expect(selection.isTextSelectionActive, isFalse);
      },
      platform: TargetPlatform.macOS,
    );
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

    viewportTest('autoplay false shows the first frame and does not start', (
      tester,
    ) async {
      final selection = newSelection();

      await pump(tester, selection, oneThumb, sticker: _pack, autoplay: false);

      expect(producer.attempts, hasLength(1));
      expect(ticks.isRunning, isFalse);
    });

    viewportTest('autoplay true starts the sticker', (tester) async {
      final selection = newSelection();

      await pump(tester, selection, oneThumb, sticker: _pack);

      expect(ticks.isRunning, isTrue);
    });

    viewportTest('a tap on a held sticker restarts the animation', (
      tester,
    ) async {
      final selection = newSelection();
      await pump(tester, selection, oneThumb, sticker: _pack, autoplay: false);
      expect(ticks.isRunning, isFalse);

      await tester.tapAt(tester.getCenter(find.byType(ChatEmojiBody)));
      await tester.pumpAndSettle();
      finishAttempts();
      await tester.pump();

      expect(ticks.isRunning, isTrue);
    });

    viewportTest('the sticker is decoded at its drawn extent', (tester) async {
      final selection = newSelection();

      await pump(tester, selection, oneThumb, sticker: _pack);

      // 400 x 800 viewport: 400 x 0.5 x 0.625 = 125 dp at 1x.
      expect(producer.attempts.single.request.spec.pixelWidth, 125);
    });
  });
}
