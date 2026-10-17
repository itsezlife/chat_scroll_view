import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _metrics = InlineEmbedMetrics(
  fontSize: 10,
  ascent: 8,
  descent: 2,
  devicePixelRatio: 2,
);

void main() {
  late FakeAssetProducer producer;
  late AssetCacheScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
    addTearDown(scope.dispose);
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
        const InlineEmbedTarget(
          scheme: 'unicode',
          id: '1F44D',
          alt: '\u{1F44D}',
        ),
        _metrics,
      )!;
      addTearDown(embed.dispose);

      final preset = AssetPresets.inlineMessage(
        ascent: 8,
        descent: 2,
        devicePixelRatio: 2,
      );
      expect(
        producer.last.request,
        AssetRequest(const ContentKey.unicode('\u{1F44D}'), preset.spec),
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

    test('sizes the embed with the preset the host chose', () {
      final embed =
          ContentEmbedResolver(
            scope: scope,
            presetFor: (metrics) => AssetPresets.keyboardCell(
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
