import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [width] x [height] PNG, black on the left half and white on the right.
Future<Uint8List> _halves(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF000000),
    )
    ..drawRect(
      ui.Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<List<int>> _redOfRow(ui.Image image, int y) async {
  final data = (await image.toByteData())!;
  return [
    for (var x = 0; x < image.width; x++)
      data.getUint8((y * image.width + x) * 4),
  ];
}

void main() {
  testWidgets('a large still is decoded small, its aspect kept', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await MiniThumbnail.decode(await _halves(200, 100));

      expect(image.width, MiniThumbnail.maxEdge);
      expect(image.height, MiniThumbnail.maxEdge ~/ 2);
      image.dispose();
    });
  });

  testWidgets('a still that is small already is not scaled up', (tester) async {
    await tester.runAsync(() async {
      final image = await MiniThumbnail.decode(await _halves(20, 10));

      expect(image.width, 20);
      expect(image.height, 10);
      image.dispose();
    });
  });

  testWidgets('it is blurred once, at decode: an edge becomes a ramp', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await MiniThumbnail.decode(await _halves(40, 40));
      final row = await _redOfRow(image, 20);

      expect(row.first, lessThan(8));
      expect(row.last, greaterThan(247));
      // Right at the edge the two sides mix; a sharp edge would be 0 or 255.
      expect(row[19], inExclusiveRange(40, 215));
      expect(row[20], inExclusiveRange(40, 215));
      // The ramp rises left to right.
      for (var x = 1; x < row.length; x++) {
        expect(row[x], greaterThanOrEqualTo(row[x - 1]));
      }
      image.dispose();
    });
  });

  testWidgets('bytes that are not an image fail the decode', (tester) async {
    await tester.runAsync(() async {
      await expectLater(
        MiniThumbnail.decode(Uint8List.fromList([1, 2, 3])),
        throwsA(anything),
      );
    });
  });
}
