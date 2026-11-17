/// What a message body needs from the chat screen beyond the message: the
/// host's embed seams over the asset cache, the sticker lookup, and the
/// memory of which stickers this screen already played.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_kind.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/reference_media_sizes.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_play_memory.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_atlas/testing.dart';
import 'package:listen/listen.dart' as listen;
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

final class _Counting implements Canvas {
  int rrects = 0;
  int circles = 0;
  int rects = 0;

  @override
  void drawRect(Rect rect, Paint paint) => rects++;

  @override
  void drawRRect(RRect rrect, Paint paint) => rrects++;

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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
    late ContentAssetScope scope;
    late FakeAssetProducer producer;
    late ValueNotifier<LargeEmojiPolicy> policy;
    late ChatBodyHost host;

    setUp(() {
      producer = FakeAssetProducer();
      scope = ContentAssetScope.withMedia(producer: producer);
      policy = ValueNotifier(const LargeEmojiPolicy(enabled: true));
      host = ChatBodyHost(assets: scope, policy: policy);
    });
    tearDown(() {
      policy.dispose();
      scope.dispose();
    });

    test('every embed attaches with the chat\'s download context', () {
      final channel = ChatBodyHost(
        assets: scope,
        policy: policy,
        downloadContext: ChatKind.channel.downloadContext,
      );
      final item = channel.embedFactory(
        const ContentKey.document('1'),
        ContentAssetPresets.emojiOnly(step: 40, devicePixelRatio: 2),
      )!;
      addTearDown(item.dispose);
      expect(
        producer.last.demand.downloadContexts,
        contains(AutoDownloadContext.channels),
      );

      final inline = channel.embedResolver.resolve(
        const InlineEmbedTarget(scheme: 'document', id: '2', alt: 'x'),
        const InlineEmbedMetrics(
          fontSize: 15,
          ascent: 14,
          descent: 4,
          devicePixelRatio: 2,
        ),
      )!;
      addTearDown(inline.dispose);
      expect(
        producer.last.demand.downloadContexts,
        contains(AutoDownloadContext.channels),
      );
    });

    test('every embed draws an outline in the screen\'s stage style', () {
      const fill = Color(0x33123456);
      final styled = ChatBodyHost(
        assets: scope,
        policy: policy,
        stages: MediaStageStyle.$Android.copyWith(outlineFill: fill),
      );
      for (final make in <InlineEmbed? Function()>[
        () => styled.embedFactory(
          const ContentKey.document('1'),
          ContentAssetPresets.emojiOnly(step: 40, devicePixelRatio: 2),
        ),
        () => styled.embedResolver.resolve(
          const InlineEmbedTarget(scheme: 'document', id: '2', alt: 'x'),
          const InlineEmbedMetrics(
            fontSize: 15,
            ascent: 14,
            descent: 4,
            devicePixelRatio: 2,
          ),
        ),
      ]) {
        final embed = make()!;
        addTearDown(embed.dispose);
        final attempt = producer.last
          ..describe(
            MediaDescriptor(
              key: producer.last.request.key,
              preview: const MediaPreview.outline(
                'M0 0h1v1z',
                MediaDimensions(1, 1),
              ),
            ),
          );
        final preview = attempt.advance(AssetStage.preview);

        embed.paint(
          _Counting(),
          const Rect.fromLTWH(0, 0, 10, 10),
          const InlineEmbedPaintContext(),
        );

        expect(
          preview.paints.single.context.outline,
          const OutlineLook(fill: fill),
        );
      }
    });

    testWidgets('a lone GIF gets the status control and the badge over its '
        'embed; a sticker gets none', (tester) async {
      final embed = host.embedFactory(
        const ContentKey.document('1'),
        ContentAssetPresets.emojiOnly(step: 40, devicePixelRatio: 2),
      )!;
      addTearDown(embed.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      );

      final gif = host.mediaOverlay(
        context,
        const ChatMediaItem(kind: ChatMediaKind.gif),
        embed,
      );
      final sticker = host.mediaOverlay(
        context,
        const ChatMediaItem(kind: ChatMediaKind.sticker),
        embed,
      );

      expect(
        gif,
        isA<ContentEmbedOverlay>()
            .having((o) => o.embed, 'embed', same(embed))
            .having((o) => o.status, 'status', const MediaStatusMode.control())
            .having((o) => o.badge, 'badge', isTrue),
      );
      expect(sticker, isNull);
    });

    test('makes an embed over the cache for a content and a preset', () {
      final embed = host.embedFactory(
        const ContentKey.document('5368'),
        ContentAssetPresets.emojiOnly(step: 40, devicePixelRatio: 2),
      );
      addTearDown(embed!.dispose);

      expect(
        producer.attempts.single.request.key,
        const ContentKey.document('5368').mediaKey,
      );
      expect(
        embed.sizeHint,
        ContentAssetPresets.emojiOnly(step: 40, devicePixelRatio: 2).size,
      );
    });

    group('what a sticker shows while it loads', () {
      final preset = ContentAssetPresets.emojiOnly(
        step: 40,
        devicePixelRatio: 2,
      );
      const rect = Rect.fromLTWH(0, 0, 40, 40);

      // Counts what an embed asks of a canvas before its content exists.
      ({int rrects, int circles}) drawnBefore(InlineEmbed embed) {
        final canvas = _Counting();
        embed.paint(canvas, rect, const InlineEmbedPaintContext());
        return (rrects: canvas.rrects, circles: canvas.circles);
      }

      test('a GIF is clear: no box until its preview or thumbnail', () {
        const gif = ContentKey.document('giphy:abc');
        final own = ChatBodyHost(
          assets: scope,
          policy: policy,
          describe: (key) => key == gif
              ? const ContentDescriptor(
                  key: gif,
                  semanticKind: SemanticKind.gif,
                  mediaForm: MediaForm.video,
                  animated: true,
                )
              : null,
        );
        final embed = own.embedFactory(gif, preset)!;
        addTearDown(embed.dispose);
        final canvas = _Counting();

        embed.paint(canvas, rect, const InlineEmbedPaintContext());

        expect((canvas.rects, canvas.rrects, canvas.circles), (0, 0, 0));
      });

      test('a document is a quiet rounded square, not the circle', () {
        final embed = host.embedFactory(
          const ContentKey.document('5368'),
          preset,
        )!;
        addTearDown(embed.dispose);

        expect(drawnBefore(embed), (rrects: 1, circles: 0));
      });

      test('a unicode emoji not baked yet keeps the circle', () {
        final atlas = FakeGlyphSpriteSource(const ['\u{1F600}']);
        addTearDown(atlas.dispose);
        scope.glyphSource = atlas;
        final embed = host.embedFactory(
          const ContentKey.unicode('\u{1F600}'),
          preset,
        )!;
        addTearDown(embed.dispose);

        expect(drawnBefore(embed), (rrects: 0, circles: 1));
      });
    });

    test('every embed the bodies make holds while the chat is held', () {
      final held = listen.ValueNotifier<bool>(false);
      addTearDown(held.dispose);
      final ticking = ContentAssetScope.withMedia(
        producer: producer,
        clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
      );
      addTearDown(ticking.dispose);
      final holding = ChatBodyHost(assets: ticking, policy: policy, held: held);
      final item = holding.embedFactory(
        const ContentKey.document('1'),
        ContentAssetPresets.emojiOnly(step: 40, devicePixelRatio: 2),
      )!;
      addTearDown(item.dispose);
      final itemPaintable = producer.last.advance(
        AssetStage.full,
        animated: true,
      );
      final inline = holding.embedResolver.resolve(
        const InlineEmbedTarget(scheme: 'document', id: '2', alt: 'x'),
        const InlineEmbedMetrics(
          fontSize: 15,
          ascent: 14,
          descent: 4,
          devicePixelRatio: 2,
        ),
      )!;
      addTearDown(inline.dispose);
      final inlinePaintable = producer.last.advance(
        AssetStage.full,
        animated: true,
      );

      held.value = true;

      expect(itemPaintable.keepsFrame, isTrue);
      expect(inlinePaintable.keepsFrame, isTrue);

      held.value = false;

      expect(itemPaintable.keepsFrame, isFalse);
      expect(inlinePaintable.keepsFrame, isFalse);
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

    group('media', () {
      const sticker = ContentKey.document('sticker');
      const gif = ContentKey.document('giphy:abc');
      const custom = ContentKey.document('5368');
      ContentDescriptor? describe(ContentKey key) => switch (key) {
        sticker => const ContentDescriptor(
          key: sticker,
          semanticKind: SemanticKind.sticker,
          size: ContentSize(512, 512),
        ),
        gif => const ContentDescriptor(
          key: gif,
          semanticKind: SemanticKind.gif,
          size: ContentSize(480, 270),
        ),
        custom => const ContentDescriptor(
          key: custom,
          semanticKind: SemanticKind.customEmoji,
        ),
        _ => null,
      };

      test('a lone sticker or GIF is media of its kind and source size', () {
        final own = ChatBodyHost(
          assets: scope,
          policy: policy,
          describe: describe,
        );

        expect(
          own.mediaOf(_only([sticker])),
          const ChatMediaItem(
            kind: ChatMediaKind.sticker,
            source: ContentSize(512, 512),
          ),
        );
        expect(
          own.mediaOf(_only([gif])),
          const ChatMediaItem(
            kind: ChatMediaKind.gif,
            source: ContentSize(480, 270),
          ),
        );
      });

      test('a lone emoji, two items or an unknown document is no media', () {
        final own = ChatBodyHost(
          assets: scope,
          policy: policy,
          describe: describe,
        );

        expect(own.mediaOf(_only([custom])), isNull);
        expect(
          own.mediaOf(_only([const ContentKey.unicode('\u{1F44D}')])),
          isNull,
        );
        expect(own.mediaOf(_only([sticker, sticker])), isNull);
        expect(own.mediaOf(_only([const ContentKey.document('nope')])), isNull);
        expect(host.mediaOf(_only([sticker])), isNull, reason: 'no describe');
      });

      test('sizes media by the running platform\'s sizes, or the '
          'host\'s', () {
        expect(
          ChatBodyHost(assets: scope, policy: policy).mediaSizes,
          ReferenceMediaSizes.forPlatform(),
        );
        expect(
          ChatBodyHost(
            assets: scope,
            policy: policy,
            mediaSizes: const ReferenceMediaSizes.desktop(),
          ).mediaSizes,
          const ReferenceMediaSizes.desktop(),
        );
      });
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
