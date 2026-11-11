import 'dart:typed_data';

/// Blurs [rgba] (rows of `width` RGBA pixels, premultiplied, `height` rows)
/// in place by a stack blur of [radius], after laying it over the opaque
/// [background] (`0xRRGGBB`), then applies [tone] (a 4 x 5 colour matrix
/// whose fifth column is in 0..255), and leaves every pixel opaque.
///
/// A stack blur weighs the pixels at 0, 1, … [radius] away by [radius] + 1,
/// [radius], … 1 (a tent, close to a Gaussian of sigma
/// `sqrt(radius * (radius + 2) / 6)`), across each row and then down each
/// column, each pass truncated to whole levels. Past the edges it repeats the
/// edge pixel, so the edges keep their colour. It reads every pixel a
/// constant number of times whatever [radius] is.
void stackBlurRgba(
  Uint8List rgba,
  int width,
  int height, {
  required int radius,
  int background = 0x000000,
  List<double>? tone,
}) {
  assert(rgba.length == width * height * 4, 'rgba is width x height pixels');
  assert(radius >= 0, 'A radius is never negative.');
  _flatten(rgba, background);
  if (radius > 0 && width > 0 && height > 0) {
    final across = Uint8List(rgba.length);
    for (var y = 0; y < height; y++) {
      _blurLine(rgba, across, y * width * 4, 4, width, radius);
    }
    for (var x = 0; x < width; x++) {
      _blurLine(across, rgba, x * 4, width * 4, height, radius);
    }
  }
  if (tone != null) _tone(rgba, tone);
}

// Lays the premultiplied pixels over an opaque background.
void _flatten(Uint8List rgba, int background) {
  final r = background >> 16 & 0xFF;
  final g = background >> 8 & 0xFF;
  final b = background & 0xFF;
  for (var at = 0; at < rgba.length; at += 4) {
    final clear = 255 - rgba[at + 3];
    if (clear != 0) {
      rgba[at] += (r * clear + 127) ~/ 255;
      rgba[at + 1] += (g * clear + 127) ~/ 255;
      rgba[at + 2] += (b * clear + 127) ~/ 255;
      rgba[at + 3] = 255;
    }
  }
}

// One line of [length] pixels from [source] into [target], starting at
// [start] and [stride] bytes apart, its colour channels blurred.
void _blurLine(
  Uint8List source,
  Uint8List target,
  int start,
  int stride,
  int length,
  int radius,
) {
  final last = length - 1;
  final divisor = (radius + 1) * (radius + 1);
  int at(int i) => start + (i < 0 ? 0 : (i > last ? last : i)) * stride;
  for (var channel = 0; channel < 3; channel++) {
    // The tent's sum at the pixel, and the sums of its rising half (the
    // pixel and those before it) and falling half (those after).
    var sum = 0;
    var rising = 0;
    var falling = 0;
    for (var k = -radius; k <= radius; k++) {
      final value = source[at(k) + channel];
      sum += value * (radius + 1 - k.abs());
      if (k <= 0) {
        rising += value;
      } else {
        falling += value;
      }
    }
    for (var i = 0; i < length; i++) {
      target[at(i) + channel] = sum ~/ divisor;
      final incoming = source[at(i + radius + 1) + channel];
      final next = source[at(i + 1) + channel];
      sum += falling + incoming - rising;
      rising += next - source[at(i - radius) + channel];
      falling += incoming - next;
    }
  }
  for (var i = 0; i < length; i++) {
    target[at(i) + 3] = 255;
  }
}

void _tone(Uint8List rgba, List<double> m) {
  for (var at = 0; at < rgba.length; at += 4) {
    final r = rgba[at];
    final g = rgba[at + 1];
    final b = rgba[at + 2];
    rgba[at] = _level(m[0] * r + m[1] * g + m[2] * b + m[3] * 255 + m[4]);
    rgba[at + 1] = _level(m[5] * r + m[6] * g + m[7] * b + m[8] * 255 + m[9]);
    rgba[at + 2] = _level(
      m[10] * r + m[11] * g + m[12] * b + m[13] * 255 + m[14],
    );
  }
}

int _level(double value) => value <= 0
    ? 0
    : value >= 255
    ? 255
    : value.round();
