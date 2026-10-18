/// What a message body needs from the chat screen beyond the message: the
/// host's embed seams over the asset cache, the sticker lookup, and the
/// memory of which stickers this screen already played.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_play_memory.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

EmojiOnly _only(List<ContentKey> keys) =>
    EmojiOnly([for (final key in keys) EmojiOnlyItem(key)]);

void main() {
  group('StickerPlayMemory', () {
    test('is the ledger of the viewport\'s sticker body', () {
      expect(StickerPlayMemory(), isA<ChatStickerPlayLedger>());
    });

    test('has played nothing until a play is recorded', () {
      final memory = StickerPlayMemory();

      expect(memory.hasPlayed(7), isFalse);
      memory.markPlayed(7);
      expect(memory.hasPlayed(7), isTrue);
      expect(memory.hasPlayed(8), isFalse);
    });

    test('recording twice is the same as once', () {
      final memory = StickerPlayMemory()
        ..markPlayed(7)
        ..markPlayed(7);

      expect(memory.hasPlayed(7), isTrue);
    });

    test('a new screen has a new memory: its stickers play again', () {
      StickerPlayMemory().markPlayed(1);

      expect(StickerPlayMemory().hasPlayed(1), isFalse);
    });
  });

  group('ChatBodyHost', () {
    late AssetCacheScope scope;
    late FakeAssetProducer producer;
    late ValueNotifier<LargeEmojiPolicy> policy;
    late ChatBodyHost host;

    setUp(() {
      producer = FakeAssetProducer();
      scope = AssetCacheScope(producer: producer);
      policy = ValueNotifier(const LargeEmojiPolicy(enabled: true));
      host = ChatBodyHost(assets: scope, policy: policy);
    });
    tearDown(() {
      policy.dispose();
      scope.dispose();
    });

    test('makes an embed over the cache for a content and a preset', () {
      final embed = host.embedFactory(
        const ContentKey.document('5368'),
        AssetPresets.emojiOnly(step: 40, devicePixelRatio: 2),
      );
      addTearDown(embed!.dispose);

      expect(
        producer.attempts.single.request.key,
        const ContentKey.document('5368'),
      );
      expect(
        embed.sizeHint,
        AssetPresets.emojiOnly(step: 40, devicePixelRatio: 2).size,
      );
    });

    test('resolves a document target of an image span to an embed', () {
      final embed = host.embedResolver.resolve(
        const InlineEmbedTarget(scheme: 'document', id: '5368', alt: 'x'),
        const InlineEmbedMetrics(
          fontSize: 15,
          ascent: 14,
          descent: 4,
          devicePixelRatio: 2,
        ),
      );
      addTearDown(() => embed?.dispose());

      expect(embed, isNotNull);
      expect(
        host.embedResolver.resolve(
          const InlineEmbedTarget(scheme: 'mention', id: '7', alt: '@a'),
          const InlineEmbedMetrics(
            fontSize: 15,
            ascent: 14,
            descent: 4,
            devicePixelRatio: 2,
          ),
        ),
        isNull,
      );
    });

    test(
      'a lone unicode emoji is the sticker of the pack, when it has one',
      () {
        final thumbsUp = AnimatedEmojiPack.stickerFor(
          const ContentKey.unicode('\u{1F44D}'),
        );

        expect(
          host.stickerOf(_only([const ContentKey.unicode('\u{1F44D}')])),
          thumbsUp,
        );
        expect(thumbsUp, isNotNull);
        expect(
          host.stickerOf(_only([const ContentKey.unicode('\u{1F9A5}')])),
          isNull,
        );
      },
    );

    test('a lone custom emoji is its own sticker', () {
      expect(
        host.stickerOf(_only([const ContentKey.document('5368')])),
        const ContentKey.document('5368'),
      );
    });

    test('plays a lone unicode emoji once and a custom emoji in a loop, by '
        'default', () {
      expect(
        host.playbackFor(const ContentKey.unicode('\u{1F44D}')),
        ChatStickerPlayback.onceThenFirstFrame,
      );
      expect(
        host.playbackFor(const ContentKey.document('5368')),
        ChatStickerPlayback.loop,
      );
    });

    test('lets the host choose the playback: the rest frame, or still', () {
      final own = ChatBodyHost(
        assets: scope,
        policy: policy,
        playbackFor: (emoji) => emoji is ContentKey$Unicode
            ? ChatStickerPlayback.onceThenLastFrame
            : ChatStickerPlayback.still,
      );

      expect(
        own.playbackFor(const ContentKey.unicode('\u{1F44D}')),
        ChatStickerPlayback.onceThenLastFrame,
      );
      expect(
        own.playbackFor(const ContentKey.document('5368')),
        ChatStickerPlayback.still,
      );
    });

    test('more than one emoji is text, whatever each would be alone', () {
      expect(
        host.stickerOf(
          _only([
            const ContentKey.unicode('\u{1F44D}'),
            const ContentKey.unicode('\u{1F44D}'),
          ]),
        ),
        isNull,
      );
    });
  });
}
