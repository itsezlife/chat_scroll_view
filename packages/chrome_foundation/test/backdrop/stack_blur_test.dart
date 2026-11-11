/// The stack blur a backdrop still is made with, on the CPU.
///
/// **Seam:** `stackBlurRgba` over small RGBA buffers, against a direct
/// evaluation of the same tent: each pixel the weighted sum of the pixels
/// up to the radius away along the line, the edge pixel repeated past the
/// edges, divided by (radius + 1)², truncated, across the rows and then down
/// the columns.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/src/backdrop/stack_blur.dart';
import 'package:flutter_test/flutter_test.dart';

// The tent evaluated directly, one channel of an opaque image.
List<int> _direct(List<int> pixels, int width, int height, int radius) {
  final divisor = (radius + 1) * (radius + 1);
  int clamp(int i, int n) => math.min(math.max(i, 0), n - 1);
  final across = List<int>.filled(pixels.length, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var k = -radius; k <= radius; k++) {
        sum += pixels[y * width + clamp(x + k, width)] * (radius + 1 - k.abs());
      }
      across[y * width + x] = sum ~/ divisor;
    }
  }
  final down = List<int>.filled(pixels.length, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var k = -radius; k <= radius; k++) {
        sum +=
            across[clamp(y + k, height) * width + x] * (radius + 1 - k.abs());
      }
      down[y * width + x] = sum ~/ divisor;
    }
  }
  return down;
}

Uint8List _opaque(List<int> red, List<int> green, List<int> blue) {
  final rgba = Uint8List(red.length * 4);
  for (var i = 0; i < red.length; i++) {
    rgba
      ..[i * 4] = red[i]
      ..[i * 4 + 1] = green[i]
      ..[i * 4 + 2] = blue[i]
      ..[i * 4 + 3] = 255;
  }
  return rgba;
}

List<int> _channel(Uint8List rgba, int channel) => [
  for (var at = channel; at < rgba.length; at += 4) rgba[at],
];

void main() {
  test('equals the tent evaluated directly, edges repeated', () {
    const width = 13;
    const height = 9;
    final random = math.Random(7);
    // A checkerboard of single pixels, a sharp bar at the left edge and
    // noise: every kind of detail, up against the edges.
    final red = [
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++) (x + y).isEven ? 255 : 0,
    ];
    final green = [
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++) x < 2 ? 255 : 16,
    ];
    final blue = [for (var i = 0; i < width * height; i++) random.nextInt(256)];
    for (final radius in [0, 1, 2, 5, 15]) {
      final rgba = _opaque(red, green, blue);
      stackBlurRgba(rgba, width, height, radius: radius);
      expect(_channel(rgba, 0), _direct(red, width, height, radius));
      expect(_channel(rgba, 1), _direct(green, width, height, radius));
      expect(_channel(rgba, 2), _direct(blue, width, height, radius));
      expect(_channel(rgba, 3), everyElement(255));
    }
  });

  test('a single row or column is blurred along its length alone', () {
    final row = _opaque([0, 0, 255, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0]);
    stackBlurRgba(row, 5, 1, radius: 1);
    expect(_channel(row, 0), _direct([0, 0, 255, 0, 0], 5, 1, 1));
    final column = _opaque([0, 0, 255, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0]);
    stackBlurRgba(column, 1, 5, radius: 1);
    expect(_channel(column, 0), _direct([0, 0, 255, 0, 0], 1, 5, 1));
  });

  test('clear pixels are laid over the background first, and come out '
      'opaque', () {
    // Premultiplied: a red at half alpha, and nothing.
    final rgba = Uint8List.fromList([128, 0, 0, 128, 0, 0, 0, 0]);
    stackBlurRgba(rgba, 2, 1, radius: 0, background: 0x0000FF);
    expect(rgba, [128, 0, 127, 255, 0, 0, 255, 255]);
  });

  test('the tone is applied after the blur, in levels of 255', () {
    final rgba = _opaque([128], [128], [128]);
    stackBlurRgba(
      rgba,
      1,
      1,
      radius: 4,
      tone: BackdropSnapshot.toneMatrix(brightness: -0.25),
    );
    expect(rgba, [64, 64, 64, 255]);
  });

  test('its cost for a phone window at 1/15, measured', () {
    // 1440 x 3120 device pixels at 1/15, the reference's radius.
    const width = 96;
    const height = 208;
    final random = math.Random(1);
    final source = Uint8List.fromList([
      for (var i = 0; i < width * height * 4; i++) random.nextInt(256),
    ]);
    final tone = BackdropSnapshot.toneMatrix(saturation: .04, brightness: -.04);
    final rgba = Uint8List(source.length);
    // Warmed up, then the best of a few runs: the unoptimised first calls
    // are not what a long-running app pays.
    var best = Duration.zero;
    for (var run = 0; run < 30; run++) {
      rgba.setAll(0, source);
      final watch = Stopwatch()..start();
      stackBlurRgba(rgba, width, height, radius: 15, tone: tone);
      watch.stop();
      if (run == 10 || (run > 10 && watch.elapsed < best)) best = watch.elapsed;
    }
    // ignore: avoid_print, the cost is reported with the suite.
    print('stack blur, $width x $height, radius 15, toned: $best');
    expect(best, lessThan(const Duration(milliseconds: 5)));
  });
}
