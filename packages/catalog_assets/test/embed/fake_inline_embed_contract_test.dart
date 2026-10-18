import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  InlineEmbedContract.run(FakeInlineEmbed.new);

  InlineEmbedContract.run(FakePlayableEmbed.new);

  PlayableEmbedContract.run(() {
    final embed = FakePlayableEmbed();
    return PlayableEmbedHarness(
      embed: embed,
      endPass: () => embed.playback = AssetPlayback.ended,
    );
  });

  InlineEmbedResolverContract.run(
    () => InlineEmbedResolverHarness(
      resolver: FakeInlineEmbedResolver(),
      known: const InlineEmbedTarget(scheme: 'fake', id: '1', alt: 'x'),
      unknown: const InlineEmbedTarget(scheme: 'other', id: '1', alt: 'x'),
    ),
  );

  group('FakeInlineEmbed', () {
    test('signals its listeners when a test invalidates it', () {
      final embed = FakeInlineEmbed();
      var heard = 0;
      embed
        ..addListener(() => heard++)
        ..invalidate();

      expect(heard, 1);
    });

    test('records what it was painted with', () {
      final embed = FakeInlineEmbed();
      const context = InlineEmbedPaintContext(opacity: 0.5);

      embed.paint(
        Canvas(PictureRecorder()),
        const Rect.fromLTWH(1, 2, 3, 4),
        context,
      );

      expect(embed.paints.single.context, context);
    });
  });
}
