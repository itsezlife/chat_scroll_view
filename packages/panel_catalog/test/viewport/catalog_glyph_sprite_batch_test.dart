/// The sprite batch of one paint pass: sprites are grouped by the page image
/// they are cut from, whatever number the page has.
///
/// **Seam:** [CatalogGlyphSpriteBatch.add] and `flush` against a recording
/// canvas; what is observed is the atlas draws the canvas received.
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart' show AssetFit, AtlasSprite;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/src/viewport/catalog_glyph_sprite_batch.dart';

import '../support/recording_canvas.dart';

ui.Image _page() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(8, 8);
  picture.dispose();
  return image;
}

AtlasSprite _sprite(ui.Image page, {int pageIndex = 0, double x = 0}) =>
    AtlasSprite(
      pageIndex: pageIndex,
      page: page,
      source: Rect.fromLTWH(x, 0, 4, 4),
    );

void main() {
  late CatalogGlyphSpriteBatch batch;
  late RecordingCanvas canvas;
  late ui.Image glyphPage;
  late ui.Image framePage;

  setUp(() {
    batch = CatalogGlyphSpriteBatch();
    canvas = RecordingCanvas();
    glyphPage = _page();
    framePage = _page();
  });
  tearDown(() {
    batch.dispose();
    glyphPage.dispose();
    framePage.dispose();
  });

  // A 4 x 4 box at the origin: a 4 x 4 sprite lands there unscaled.
  void add(
    AtlasSprite sprite, {
    double opacity = 1,
    Rect box = const Rect.fromLTWH(0, 0, 4, 4),
    AssetFit fit = AssetFit.contain,
    double pressScale = 1,
  }) => batch.add(
    sprite,
    box: box,
    fit: fit,
    anchor: box.center,
    pressScale: pressScale,
    opacity: opacity,
  );

  test('pages with the same index but different images are drawn apart', () {
    // A glyph atlas page 0 and a frame pool page 0 are different pictures.
    add(_sprite(glyphPage));
    add(_sprite(framePage, x: 4));
    add(_sprite(glyphPage, x: 2));

    batch.flush(canvas);

    expect(canvas.atlasDraws, hasLength(2));
    final byImage = {for (final d in canvas.atlasDraws) d.image: d};
    expect(byImage[glyphPage]!.sprites, 2);
    expect(byImage[framePage]!.sprites, 1);
    expect(byImage[framePage]!.sources.single, const Rect.fromLTWH(4, 0, 4, 4));
  });

  test('sprites of one image are one draw, flush after flush', () {
    for (var pass = 0; pass < 2; pass++) {
      canvas = RecordingCanvas();
      add(_sprite(glyphPage));
      add(_sprite(glyphPage, x: 4));

      batch.flush(canvas);

      expect(canvas.atlasDraws, hasLength(1));
      expect(canvas.atlasDraws.single.sprites, 2);
    }
  });

  test('a page image replaced between passes does not linger', () {
    add(_sprite(glyphPage));
    batch.flush(canvas);
    canvas = RecordingCanvas();

    add(_sprite(framePage));
    batch.flush(canvas);

    expect(canvas.atlasDraws, hasLength(1));
    expect(canvas.atlasDraws.single.image, same(framePage));
  });

  test('opaque sprites draw without colours', () {
    add(_sprite(glyphPage));

    batch.flush(canvas);

    expect(canvas.atlasDraws.single.colors, isNull);
  });

  test('a faded sprite is modulated by its opacity, an opaque one is not', () {
    add(_sprite(glyphPage));
    add(_sprite(glyphPage, x: 4), opacity: 0.5);

    batch.flush(canvas);

    final draw = canvas.atlasDraws.single;
    expect(draw.blendMode, BlendMode.modulate);
    final colors = draw.colors!.map(Color.new).toList();
    expect(colors[0].a, closeTo(1, 0.01));
    expect(colors[1].a, closeTo(0.5, 0.01));
  });

  group('fit', () {
    // A 40 x 20 sprite at (4, 2) on its page, drawn into a 20 x 20 box at (10, 30).
    const wide = Rect.fromLTWH(4, 2, 40, 20);
    const box = Rect.fromLTWH(10, 30, 20, 20);

    AtlasSprite wideSprite() =>
        AtlasSprite(pageIndex: 0, page: glyphPage, source: wide);

    test('contain draws the whole sprite, scaled to the box and centred', () {
      add(wideSprite(), box: box);

      batch.flush(canvas);

      final draw = canvas.atlasDraws.single;
      expect(draw.sources.single, wide);
      expect(draw.scales.single, closeTo(0.5, 1e-6));
      expect(draw.offsets.single.dx, closeTo(10, 1e-4));
      expect(draw.offsets.single.dy, closeTo(35, 1e-4));
    });

    test('cover draws the middle of the sprite over the whole box', () {
      add(wideSprite(), box: box, fit: AssetFit.cover);

      batch.flush(canvas);

      final draw = canvas.atlasDraws.single;
      // The box is square: the sprite's height, the middle 20 of its 40 width.
      expect(draw.sources.single, const Rect.fromLTWH(14, 2, 20, 20));
      expect(draw.scales.single, closeTo(1, 1e-6));
      expect(draw.offsets.single.dx, closeTo(10, 1e-4));
      expect(draw.offsets.single.dy, closeTo(30, 1e-4));
    });

    test('cover keeps one atlas draw however many sprites are cropped', () {
      for (var i = 0; i < 5; i++) {
        add(
          wideSprite(),
          box: box.shift(Offset(30.0 * i, 0)),
          fit: AssetFit.cover,
        );
      }
      add(_sprite(glyphPage, x: 4), box: const Rect.fromLTWH(0, 0, 8, 8));

      batch.flush(canvas);

      expect(canvas.atlasDraws, hasLength(1));
      expect(canvas.atlasDraws.single.sprites, 6);
    });

    test('a press scales the placed sprite about the anchor, crop kept', () {
      batch.add(
        wideSprite(),
        box: box,
        fit: AssetFit.cover,
        anchor: box.center,
        pressScale: 0.8,
      );

      batch.flush(canvas);

      final draw = canvas.atlasDraws.single;
      expect(draw.sources.single, const Rect.fromLTWH(14, 2, 20, 20));
      expect(draw.scales.single, closeTo(0.8, 1e-6));
      // Top-left pulled 20% toward the centre (20, 40): (10, 30) -> (12, 32).
      expect(draw.offsets.single.dx, closeTo(12, 1e-4));
      expect(draw.offsets.single.dy, closeTo(32, 1e-4));
    });
  });
}
