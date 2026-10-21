/// The comparison key of a cell's pixels.
///
/// **Seam:** `GlyphPixelHash.of`, bytes in, 16 hex digits out.
library;

import 'dart:typed_data';

import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

Uint8List _pixels(int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (i * 37 + 11) & 0xFF]);

void main() {
  test('is 16 hex digits and the same for the same pixels', () {
    final hash = GlyphPixelHash.of(_pixels(64));

    expect(hash, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(GlyphPixelHash.of(_pixels(64)), hash);
  });

  for (final length in [1, 3, 4, 7, 64, 77]) {
    test('tells a change of any single byte of $length bytes', () {
      final base = _pixels(length);
      final seen = {GlyphPixelHash.of(base)};

      for (var i = 0; i < length; i++) {
        final changed = Uint8List.fromList(base)..[i] ^= 0x40;
        seen.add(GlyphPixelHash.of(changed));
      }

      expect(seen, hasLength(length + 1));
    });
  }

  test('is the same for a view that does not start on a word boundary', () {
    final cell = _pixels(64);
    final shifted = Uint8List(65)..setRange(1, 65, cell);

    expect(
      GlyphPixelHash.of(Uint8List.sublistView(shifted, 1)),
      GlyphPixelHash.of(cell),
    );
  });

  test('tells pixels of different length apart', () {
    expect(
      GlyphPixelHash.of(Uint8List(8)),
      isNot(GlyphPixelHash.of(Uint8List(12))),
    );
  });
}
