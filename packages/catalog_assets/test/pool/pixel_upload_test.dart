import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter_test/flutter_test.dart';

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(2, 2);
  picture.dispose();
  return image;
}

void main() {
  final pixels = Uint8List(2 * 2 * 4);

  test('an engine with the synchronous form gives its image', () async {
    final made = _image();
    var asyncCalls = 0;
    final upload = PixelUpload(
      sync: (_, _, _, _) => made,
      async: (_, _, _, _, _) => asyncCalls++,
    );
    expect(await upload(pixels, 2, 2, ui.PixelFormat.rgba8888), same(made));
    expect(asyncCalls, 0);
    made.dispose();
  });

  test('a throw switches to the asynchronous form for good', () async {
    var syncCalls = 0;
    final made = <ui.Image>[];
    final upload = PixelUpload(
      sync: (_, _, _, _) {
        syncCalls++;
        throw UnimplementedError();
      },
      async: (_, width, height, format, done) {
        expect((width, height, format), (2, 2, ui.PixelFormat.bgra8888));
        final image = _image();
        made.add(image);
        done(image);
      },
    );
    for (var i = 0; i < 3; i++) {
      await upload(pixels, 2, 2, ui.PixelFormat.bgra8888);
    }
    expect(syncCalls, 1);
    for (final image in made) {
      image.dispose();
    }
  });

  test('the engine upload makes an image wherever the test runs', () async {
    final image = await uploadFramePage(pixels, 2);
    expect((image.width, image.height), (2, 2));
    image.dispose();
  });
}
