import 'dart:ui';

import 'package:content_assets/content_assets.dart';
import 'package:content_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

const _metrics = InlineEmbedMetrics(
  fontSize: 10,
  ascent: 8,
  descent: 2,
  devicePixelRatio: 2,
);

void main() {
  late FakeAssetProducer producer;
  late AssetCacheScope media;
  late ContentAssetScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    media = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
    scope = ContentAssetScope(media: media);
    addTearDown(() {
      scope.dispose();
      media.dispose();
    });
  });

  InlineEmbedResolverContract.run(
    () => InlineEmbedResolverHarness(
      resolver: ContentEmbedResolver(scope: scope),
      known: const InlineEmbedTarget(scheme: 'document', id: '5', alt: 'x'),
      unknown: const InlineEmbedTarget(scheme: 'https', id: '//a', alt: 'x'),
    ),
  );

  group('ContentEmbedResolver', () {
    test('reads the scheme and id as the encoding of a content key', () {
      final embed = ContentEmbedResolver(scope: scope).resolve(
        const InlineEmbedTarget(scheme: 'document', id: '5368', alt: 'x'),
        _metrics,
      )!;
      addTearDown(embed.dispose);

      final preset = ContentAssetPresets.inlineMessage(
        ascent: 8,
        descent: 2,
        devicePixelRatio: 2,
      );
      expect(
        producer.last.request,
        AssetRequest(const MediaKey.remote('5368'), preset.spec),
      );
      expect(embed.sizeHint, preset.size);
    });

    test('sizes the embed to the inline square of the metrics', () {
      const metrics = InlineEmbedMetrics(
        fontSize: 16,
        ascent: 15,
        descent: 4,
        devicePixelRatio: 3,
      );
      final embed = ContentEmbedResolver(scope: scope).resolve(
        const InlineEmbedTarget(scheme: 'document', id: '5', alt: 'x'),
        metrics,
      )!;
      addTearDown(embed.dispose);

      // 1.2 * (15 + 4) = 22.8 logical px = 68.4 device px, 68 rounded.
      expect(embed.sizeHint, const Size.square(68 / 3));
      expect(producer.last.request.spec.pixelWidth, 68);
    });

    test('has no embed for a scheme that is not a content key', () {
      final embed = ContentEmbedResolver(scope: scope).resolve(
        const InlineEmbedTarget(scheme: 'mention', id: 'alice', alt: '@alice'),
        _metrics,
      );

      expect(embed, isNull);
      expect(producer.attempts, isEmpty);
    });

    test('has no embed for an unreadable id', () {
      final embed = ContentEmbedResolver(scope: scope).resolve(
        const InlineEmbedTarget(scheme: 'unicode', id: 'zz', alt: '?'),
        _metrics,
      );

      expect(embed, isNull);
    });

    test('every embed it makes follows the host\'s hold', () {
      final hold = listen.ValueNotifier<bool>(true);
      addTearDown(hold.dispose);
      final embed = ContentEmbedResolver(scope: scope, held: hold).resolve(
        const InlineEmbedTarget(scheme: 'document', id: '9', alt: 's'),
        _metrics,
      )!;
      addTearDown(embed.dispose);
      final paintable = producer.last.advance(AssetStage.full, animated: true);

      expect(paintable.keepsFrame, isTrue);
      hold.value = false;
      expect(paintable.keepsFrame, isFalse);
    });

    test('every embed it makes attaches with the surface\'s download '
        'context', () {
      const context = AutoDownloadContext('channels');
      final embed = ContentEmbedResolver(scope: scope, downloadContext: context)
          .resolve(
            const InlineEmbedTarget(scheme: 'document', id: '9', alt: 's'),
            _metrics,
          )!;
      addTearDown(embed.dispose);

      expect(producer.last.demand.downloadContexts, contains(context));
    });

    test('every embed it makes draws an outline in the host\'s stages', () {
      const fill = Color(0x33123456);
      final embed =
          ContentEmbedResolver(
                scope: scope,
                stages: listen.ValueNotifier(
                  MediaStageStyle.$Android.copyWith(outlineFill: fill),
                ),
              ).resolve(
                const InlineEmbedTarget(scheme: 'document', id: '9', alt: 's'),
                _metrics,
              )!
              as ContentEmbed;
      addTearDown(embed.dispose);
      producer.last.describe(
        MediaDescriptor(
          key: producer.last.request.key,
          preview: const MediaPreview.outline(
            'M0 0h1v1z',
            MediaDimensions(1, 1),
          ),
        ),
      );
      final preview = producer.last.advance(AssetStage.preview);

      embed.paint(
        Canvas(PictureRecorder()),
        const Rect.fromLTWH(0, 0, 10, 10),
        const InlineEmbedPaintContext(),
      );

      expect(
        preview.paints.single.context.outline,
        const OutlineLook(fill: fill),
      );
    });

    test('sizes the embed with the preset the host chose', () {
      final embed =
          ContentEmbedResolver(
            scope: scope,
            presetFor: (metrics) => ContentAssetPresets.keyboardCell(
              extent: metrics.fontSize * 3,
              devicePixelRatio: metrics.devicePixelRatio,
            ),
          ).resolve(
            const InlineEmbedTarget(scheme: 'document', id: '9', alt: 's'),
            _metrics,
          )!;
      addTearDown(embed.dispose);

      expect(embed.sizeHint.width, 30);
    });
  });
}
