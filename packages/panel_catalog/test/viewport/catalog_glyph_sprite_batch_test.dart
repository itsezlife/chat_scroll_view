/// The sprite batch of one paint pass: sprites are grouped by the page image
/// they are cut from, whatever number the page has.
///
/// **Seam:** [CatalogGlyphSpriteBatch.add] and `flush` against a recording
/// canvas; what is observed is the atlas draws the canvas received.
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart' show AtlasSprite;
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

  void add(AtlasSprite sprite, {double opacity = 1}) =>
      batch.add(sprite, left: 0, top: 0, scale: 1, opacity: opacity);

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
}
