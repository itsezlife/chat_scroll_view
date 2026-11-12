import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_decoder/src/image_paintable.dart';

final class _Recording implements ui.Canvas {
  final List<({ui.Rect src, ui.Rect dst})> draws = [];

  @override
  void drawImageRect(
    ui.Image image,
    ui.Rect src,
    ui.Rect dst,
    ui.Paint paint,
  ) => draws.add((src: src, dst: dst));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ui.Image _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint(),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

void main() {
  const cell = ui.Rect.fromLTWH(0, 0, 100, 100);

  test('a still is contained by default, with bars', () {
    final paintable = StillImagePaintable(_image(200, 100), template: false);
    addTearDown(paintable.dispose);
    final canvas = _Recording();

    paintable.paint(canvas, cell, const AssetPaintContext());

    expect(canvas.draws.single.src, const ui.Rect.fromLTWH(0, 0, 200, 100));
    expect(canvas.draws.single.dst, const ui.Rect.fromLTWH(0, 25, 100, 50));
  });

  test('a still covers the cell when the surface asks, cropping the sides', () {
    final paintable = StillImagePaintable(_image(200, 100), template: false);
    addTearDown(paintable.dispose);
    final canvas = _Recording();

    paintable.paint(canvas, cell, const AssetPaintContext(fit: AssetFit.cover));

    expect(canvas.draws.single.src, const ui.Rect.fromLTWH(50, 0, 100, 100));
    expect(canvas.draws.single.dst, cell);
  });
}
