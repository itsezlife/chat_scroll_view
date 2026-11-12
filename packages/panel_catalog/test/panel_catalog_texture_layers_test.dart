/// Playing leaves with a platform texture: the Panel Catalog Viewport adds a
/// texture layer for each, inside its clip and over what the cell painted
/// under it, instead of drawing a sprite or calling `paint` (ADR 043).
///
/// **Seam:** [PanelCatalogViewport] driven with [FakeCatalogSnapshotSource]
/// and a real [AssetCacheScope] over a [FakeAssetProducer], whose paintables
/// expose a texture (and a sprite) once they are advanced. What is observed is
/// the layer tree the viewport's own layer holds after a frame, and what a
/// recording canvas is asked to draw.
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

import 'support/recording_canvas.dart';

// 4 columns of 80 x 40 cells under a 24 px header in a 320 px wide viewport. A
// sticker is shown whole in a 40 px box centred in its cell.
const _span = 4;
const _theme = PanelCatalogThemeData.light;
const _viewport = Size(320, 400);

/// The box of leaf [i] of the first section, in the viewport's coordinates.
Rect _box(int i) {
  final column = i % _span;
  final row = i ~/ _span;
  return Rect.fromLTWH(column * 80.0 + 20, 24.0 + row * 40, 40, 40);
}

ui.Image _page() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(8, 8);
  picture.dispose();
  return image;
}

CatalogLeaf _leaf(int i, {SemanticKind kind = SemanticKind.sticker}) =>
    CatalogLeaf.document(
      'leaf-$i',
      semanticKind: kind,
      mediaForm: MediaForm.still,
      animated: true,
    );

List<Layer> _children(ContainerLayer layer) {
  final out = <Layer>[];
  for (var child = layer.firstChild; child != null; child = child.nextSibling) {
    out.add(child);
  }
  return out;
}

/// Every texture layer under [layer], depth first, in paint order.
List<TextureLayer> _textures(Layer layer) => [
  if (layer is TextureLayer) layer,
  if (layer is ContainerLayer)
    for (final child in _children(layer)) ..._textures(child),
];

void main() {
  late FakeCatalogSnapshotSource snapshots;
  late PanelCatalogController controller;
  late FakeAssetProducer producer;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late AssetCacheScope scope;
  late ui.Image page;

  setUp(() {
    snapshots = FakeCatalogSnapshotSource();
    controller = PanelCatalogController();
    producer = FakeAssetProducer();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    scope = AssetCacheScope(producer: producer, clock: clock);
    page = _page();
  });
  tearDown(() {
    snapshots.dispose();
    controller.dispose();
    scope.dispose();
    clock.dispose();
    page.dispose();
  });

  Future<void> pumpViewport(
    WidgetTester tester,
    List<CatalogLeaf> leaves,
  ) async {
    snapshots.replaceSections([
      CatalogSection(id: 'a', title: 'A', leaves: leaves),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PanelCatalogTheme(
          data: _theme,
          child: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: _viewport,
                child: PanelCatalogViewport(
                  snapshots: snapshots,
                  assets: scope,
                  controller: controller,
                  spanCount: _span,
                  cellExtent: 40,
                  headerExtent: 24,
                  onLeafTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  RenderPanelCatalog render(WidgetTester tester) =>
      tester.renderObject(find.byType(PanelCatalogViewport));

  /// The viewport's own layer: it is a repaint boundary.
  OffsetLayer layer(WidgetTester tester) =>
      render(tester).debugLayer! as OffsetLayer;

  RecordingCanvas paintOnce(WidgetTester tester) {
    final canvas = RecordingCanvas();
    render(tester).paint(TestRecordingPaintingContext(canvas), Offset.zero);
    return canvas;
  }

  AtlasSprite sprite() => AtlasSprite(
    pageIndex: 0,
    page: page,
    source: const Rect.fromLTWH(0, 0, 48, 48),
  );

  /// Every attach answered at once with an animated paintable whose sprite
  /// lands on its first advance, and whose texture does too unless its index
  /// is in [noTexture]. Texture ids are `100 + index`.
  List<FakeAssetPaintable> answerAll({
    Set<int> noTexture = const {},
    int textureSide = 128,
  }) {
    final made = <FakeAssetPaintable>[];
    producer.onProduce = (attempt) {
      final paintable = attempt.advance(AssetStage.full, animated: true)
        ..spriteOnAdvance = sprite();
      if (!noTexture.contains(made.length)) {
        paintable.textureOnAdvance = AssetTexture(
          id: 100 + made.length,
          width: textureSide,
          height: textureSide,
        );
      }
      made.add(paintable);
    };
    return made;
  }

  group('layer tree', () {
    testWidgets('a playing leaf with a texture is a texture layer at its box, '
        'inside the viewport clip, after the picture', (tester) async {
      answerAll();
      await pumpViewport(tester, [_leaf(0), _leaf(1)]);

      final children = _children(layer(tester));

      expect(children.first, isA<PictureLayer>());
      final clip = children.whereType<ClipRectLayer>().single;
      expect(clip.clipRect, Offset.zero & render(tester).size);
      expect(children.indexOf(clip), greaterThan(0));
      final textures = _textures(clip);
      expect(textures.map((t) => t.textureId), [100, 101]);
      expect(textures.map((t) => t.rect), [_box(0), _box(1)]);
    });

    testWidgets('a texture of another proportion is fitted whole, centred', (
      tester,
    ) async {
      final made = <FakeAssetPaintable>[];
      producer.onProduce = (attempt) => made.add(
        attempt.advance(
          AssetStage.full,
          animated: true,
        )..textureOnAdvance = const AssetTexture(id: 7, width: 128, height: 64),
      );
      await pumpViewport(tester, [_leaf(0)]);

      final texture = _textures(layer(tester)).single;

      expect(
        texture.rect,
        Rect.fromCenter(center: _box(0).center, width: 40, height: 20),
      );
    });

    testWidgets('a cover leaf fills its box and is clipped to it', (
      tester,
    ) async {
      producer.onProduce = (attempt) =>
          attempt.advance(AssetStage.full, animated: true).textureOnAdvance =
              const AssetTexture(id: 7, width: 128, height: 64);
      await pumpViewport(tester, [_leaf(0, kind: SemanticKind.gif)]);

      final texture = _textures(layer(tester)).single;
      final clips = [
        for (final clip in _children(layer(tester)).whereType<ClipRectLayer>())
          ..._children(clip).whereType<ClipRectLayer>(),
      ];

      expect(texture.rect.height, _box(0).height);
      expect(texture.rect.width, _box(0).height * 2);
      expect(texture.rect.center, _box(0).center);
      expect(clips.single.clipRect, _box(0));
    });

    testWidgets('a cover leaf fills its box with the frame, not with the '
        'square texture around it', (tester) async {
      // A portrait frame, half as wide as tall, centred in a square texture.
      producer.onProduce = (attempt) =>
          attempt
              .advance(AssetStage.full, animated: true)
              .textureOnAdvance = const AssetTexture(
            id: 7,
            width: 128,
            height: 128,
            frameWidth: 64,
            frameHeight: 128,
          );
      await pumpViewport(tester, [_leaf(0, kind: SemanticKind.gif)]);

      final texture = _textures(layer(tester)).single;

      // The frame's width is the box's: the square is twice that.
      expect(texture.rect.width, _box(0).width * 2);
      expect(texture.rect.height, _box(0).width * 2);
      expect(texture.rect.center, _box(0).center);
    });

    testWidgets('no texture, no layer: the viewport stays one picture', (
      tester,
    ) async {
      answerAll(noTexture: {0, 1});
      await pumpViewport(tester, [_leaf(0), _leaf(1)]);

      final children = _children(layer(tester));

      expect(children, hasLength(1));
      expect(children.single, isA<PictureLayer>());
    });
  });

  group('drawing', () {
    testWidgets('a textured leaf is advanced each pass, never painted and '
        'never batched', (tester) async {
      final made = answerAll();
      await pumpViewport(tester, [_leaf(0), _leaf(1)]);
      final advanced = made.first.advances.length;

      final canvas = paintOnce(tester);

      expect(canvas.atlasDraws, isEmpty, reason: 'the texture wins');
      expect(canvas.imageDraws, 0);
      for (final paintable in made) {
        expect(paintable.paints, isEmpty);
      }
      expect(made.first.advances, hasLength(advanced + 1));
    });

    testWidgets('leaves without a texture keep the batched sprite draw', (
      tester,
    ) async {
      answerAll(noTexture: {1, 2});
      await pumpViewport(tester, [for (var i = 0; i < 4; i++) _leaf(i)]);

      final canvas = paintOnce(tester);

      expect(canvas.atlasDraws.single.sprites, 2);
      expect(_textures(layer(tester)).map((t) => t.textureId), [100, 103]);
    });

    testWidgets('a leaf whose texture is gone falls back to its sprite', (
      tester,
    ) async {
      final made = answerAll();
      await pumpViewport(tester, [_leaf(0)]);
      made.single
        ..textureOnAdvance = null
        ..texture = null;

      render(tester).markNeedsPaint();
      await tester.pump();

      expect(_textures(layer(tester)), isEmpty);
      expect(paintOnce(tester).atlasDraws.single.sprites, 1);
    });
  });

  group('opacity', () {
    testWidgets('content there at attach is a bare texture layer', (
      tester,
    ) async {
      answerAll();
      await pumpViewport(tester, [_leaf(0)]);

      final clip = _children(layer(tester)).whereType<ClipRectLayer>().single;

      expect(_children(clip).single, isA<TextureLayer>());
    });

    testWidgets('content that arrives later fades in through an opacity layer '
        'over its placeholder', (tester) async {
      await pumpViewport(tester, [_leaf(0)]);
      producer.last.advance(AssetStage.full, animated: true).textureOnAdvance =
          const AssetTexture(id: 9, width: 128, height: 128);
      await tester.pump();

      final clip = _children(layer(tester)).whereType<ClipRectLayer>().single;
      final opacity = _children(clip).single;

      expect(opacity, isA<OpacityLayer>());
      expect((opacity as OpacityLayer).alpha, lessThan(255));
      expect(_children(opacity).single, isA<TextureLayer>());
      expect(
        paintOnce(tester).rrects,
        isNotEmpty,
        reason: 'the placeholder stays under it mid-fade',
      );
    });
  });

  group('press', () {
    testWidgets('the press wash is painted under the texture, and the texture '
        'shrinks about the cell centre', (tester) async {
      answerAll();
      await pumpViewport(tester, [_leaf(0)]);
      final origin = tester.getTopLeft(find.byType(PanelCatalogViewport));

      final gesture = await tester.startGesture(origin + _box(0).center);
      await tester.pump(const Duration(milliseconds: 100));

      expect(render(tester).pressedSlotKey, isNotNull);
      final texture = _textures(layer(tester)).single;
      expect(texture.rect.width, lessThan(_box(0).width));
      expect(texture.rect.center, _box(0).center);
      final washes = paintOnce(
        tester,
      ).rrects.where((r) => r.color.a > 0 && r.color.a < 0.1);
      expect(washes, isNotEmpty, reason: 'drawn in the picture, under it');

      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
