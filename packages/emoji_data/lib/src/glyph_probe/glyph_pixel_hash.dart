import 'dart:typed_data';

/// The comparison key of a glyph cell's pixels.
abstract final class GlyphPixelHash {
  /// A 64-bit fingerprint of a block of pixels, as 16 hex digits.
  ///
  /// Two lanes of 32-bit FNV (xor-then-multiply and multiply-then-xor, from
  /// different offsets), kept as separate ints and every product kept under
  /// 2^53, so the value is the same on the web, where an int is a double. It is
  /// a comparison key, not a security hash: it only has to tell "these two
  /// cells are the same pixels" from "they are not" among a few thousand cells.
  ///
  /// It reads a 32-bit word per step, not a byte: the probe hashes every baked
  /// cell on the thread that draws frames, and a cell is some 23 KB, so the
  /// loop is the probe's whole cost there. The words are the machine's own byte
  /// order, so a hash compares cells of one device, which is all the probe asks
  /// of it (and all the persisted verdicts are used for). A view that does not
  /// start on a word boundary is copied first, and hashes like its aligned
  /// twin.
  static String of(Uint8List pixels) {
    final aligned = pixels.offsetInBytes % 4 == 0
        ? pixels
        : Uint8List.fromList(pixels);
    final words = Uint32List.view(
      aligned.buffer,
      aligned.offsetInBytes,
      aligned.lengthInBytes ~/ 4,
    );
    var xorFirst = 0x811C9DC5;
    var mulFirst = 0x9747B28C;
    for (final word in words) {
      xorFirst = _mix(_mulPrime(xorFirst ^ word), 15);
      mulFirst = _mix(_mulPrime(mulFirst), 13) ^ word;
    }
    for (var i = words.length * 4; i < aligned.lengthInBytes; i++) {
      final byte = aligned[i];
      xorFirst = _mulPrime(xorFirst ^ byte);
      mulFirst = _mulPrime(mulFirst) ^ byte;
    }
    xorFirst = _mulPrime(xorFirst ^ (aligned.lengthInBytes & 0xFFFFFFFF));
    return xorFirst.toRadixString(16).padLeft(8, '0') +
        mulFirst.toRadixString(16).padLeft(8, '0');
  }
}

// Folds the high bits of the state down. The multiply only carries upward, so
// without this a difference in the high bits stays there, which makes cells
// that differ only in them collide far more often than 64 bits should.
int _mix(int h, int shift) => h ^ (h >> shift);

// 32-bit h * 0x01000193 (the FNV prime) without a 64-bit product: the prime is
// 2^24 + 0x193, and h * 2^24 modulo 2^32 only keeps h's low byte.
int _mulPrime(int h) => (h * 0x193 + ((h & 0xFF) << 24)) & 0xFFFFFFFF;
