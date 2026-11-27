/// Goldens of the paint step per platform policy: a single box, albums of
/// two and three, a box with a caption below (text corners) and a whole
/// fit over blurred bars; on the desktop policy also albums of four and
/// ten, its own mosaic.
///
/// Pictures come from a producer local to the test that answers at once
/// with a gradient of the item's own size, placed as the attach's fit
/// says, so the scenes show crop against whole fit, the blurred bars and
/// each corner's radius. Regenerate with `scripts/goldens --update`
/// (baselines are the CI runner's).
library;

import 'dart:ui' as ui;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';

const Color _backdrop = Color(0xFF121215);

/// A picture of [size] painted as a diagonal gradient with a frame, placed
/// in its rect as the paint's fit says.
final class _GradientPicture extends AssetPaintable {
  _GradientPicture(this.size, this.colors);

  final Size size;
  final List<Color> colors;

  @override
  Size? get pictureSize => size;

  @override
  bool get isAnimated => false;

  @override
  AtlasSprite? get sprite => null;

  @override
  bool get isHolding => false;

  @override
  bool restart() => false;

  @override
  void dispose() {}

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    final placed = context.fit.place(size, rect).destination;
    canvas
      ..save()
      ..clipRect(rect)
      ..drawRect(
        placed,
        Paint()
          ..shader = ui.Gradient.linear(
            placed.topLeft,
            placed.bottomRight,
            colors,
          ),
      )
      ..drawRect(
        placed.deflate(6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFFFFFFFF),
      )
      ..restore();
  }
}

/// Answers every request at once with the full stage of a
/// [_GradientPicture] of the item's size.
final class _PictureProducer implements AssetProducer {
  _PictureProducer(this.items);

  final List<MediaItem> items;

  static const _palettes = [
    [Color(0xFF2E6FD8), Color(0xFFE0B040)],
    [Color(0xFF3AA376), Color(0xFF8A3FC2)],
    [Color(0xFFD8452E), Color(0xFF2EC4D8)],
  ];

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    final index = items.indexWhere(
      (item) => item.descriptor.key.mediaKey == request.key,
    );
    final ContentSize(:width, :height) = items[index].descriptor.size!;
    progress
      ..advance(
        AssetStage.full,
        _GradientPicture(
          Size(width.toDouble(), height.toDouble()),
          _palettes[index % _palettes.length],
        ),
        bytes: 100,
      )
      ..bestReached();
    return const _Done();
  }

  @override
  void holdPreloads({required bool held}) {}

  @override
  void know(MediaDescriptor descriptor) {}
}

final class _Done implements AssetTask {
  const _Done();

  @override
  void cancel() {}
}

MediaItem _photo(int index, ContentSize size) => MediaItem(
  id: MediaItemId('$index'),
  kind: MediaItemKind.photo,
  descriptor: ContentDescriptor(key: ContentKey.document('$index'), size: size),
);

const _policies = {
  'android': MessageMediaPolicy.android(),
  'ios': MessageMediaPolicy.ios(),
  'desktop': MessageMediaPolicy.desktop(),
};

void main() {
  useGoldenBaselines('test/goldens/message_media_view_golden_test.dart');

  Future<void> expectScene(
    WidgetTester tester,
    String name,
    MessageMediaPolicy policy,
    List<ContentSize> sizes, {
    MediaCaptionPosition caption = MediaCaptionPosition.none,
  }) async {
    final items = [
      for (final (index, size) in sizes.indexed) _photo(index, size),
    ];
    final scope = ContentAssetScope.withMedia(
      producer: _PictureProducer(items),
    );
    addTearDown(scope.dispose);
    final layout = policy.layout(
      MediaLayoutInput(
        items: items,
        availableWidth: 375,
        displaySize: const Size(375, 640),
        captionPosition: caption,
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ContentAssetProvider(
          scope: scope,
          child: ColoredBox(
            color: _backdrop,
            child: Center(
              child: RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: MessageMediaView(
                    layout: layout,
                    items: items,
                    policy: policy,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('view_$name.png'),
    );
  }

  for (final MapEntry(key: platform, value: policy) in _policies.entries) {
    group(platform, () {
      testWidgets('single box', (tester) async {
        await expectScene(tester, '${platform}_single', policy, const [
          ContentSize(1600, 900),
        ]);
      });

      testWidgets('album of two', (tester) async {
        await expectScene(tester, '${platform}_album_2', policy, const [
          ContentSize(1, 1),
          ContentSize(1, 1),
        ]);
      });

      testWidgets('album of three', (tester) async {
        await expectScene(tester, '${platform}_album_3', policy, const [
          ContentSize(3, 2),
          ContentSize(1, 1),
          ContentSize(1, 1),
        ]);
      });

      testWidgets('captioned box', (tester) async {
        await expectScene(tester, '${platform}_captioned', policy, const [
          ContentSize(1200, 900),
        ], caption: MediaCaptionPosition.below);
      });

      testWidgets('blurFit bars', (tester) async {
        // Every platform drawn with a whole fit: a panorama in a box the
        // minimum height makes taller than the picture.
        final base = policy.layoutStep as MediaLayoutPolicy;
        await expectScene(
          tester,
          '${platform}_blur_fit',
          policy.copyWith(
            layoutStep: base.copyWith(
              fit: base.fit.copyWith(photo: const MediaFit.blurFit()),
            ),
          ),
          const [ContentSize(1600, 200)],
        );
      });
    });
  }

  group('desktop mosaic', () {
    const desktop = MessageMediaPolicy.desktop();

    testWidgets('album of four', (tester) async {
      await expectScene(tester, 'desktop_album_4', desktop, const [
        ContentSize(1600, 900),
        ContentSize(1000, 1000),
        ContentSize(600, 1000),
        ContentSize(1600, 900),
      ]);
    });

    testWidgets('album of ten', (tester) async {
      await expectScene(tester, 'desktop_album_10', desktop, const [
        ContentSize(1600, 900),
        ContentSize(600, 1000),
        ContentSize(1000, 1000),
        ContentSize(1600, 900),
        ContentSize(900, 1600),
        ContentSize(1000, 1000),
        ContentSize(1600, 900),
        ContentSize(600, 1000),
        ContentSize(1200, 900),
        ContentSize(900, 1200),
      ]);
    });
  });
}
