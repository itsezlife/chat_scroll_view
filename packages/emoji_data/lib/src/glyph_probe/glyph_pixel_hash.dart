import 'dart:typed_data';

/// A 64-bit fingerprint of a block of pixels, as 16 hex digits.
///
/// Two lanes of 32-bit FNV (xor-then-multiply and multiply-then-xor, from
/// different offsets), kept as separate ints and every product kept under 2^53,
/// so the value is the same on the web, where an int is a double. It is a
/// comparison key, not a security hash: it only has to tell "these two cells
/// are the same pixels" from "they are not" among a few thousand cells.
String hashGlyphPixels(Uint8List pixels) {
  var xorFirst = 0x811C9DC5;
  var mulFirst = 0x9747B28C;
  for (final byte in pixels) {
    xorFirst = _mulPrime(xorFirst ^ byte);
    mulFirst = _mulPrime(mulFirst) ^ byte;
  }
  return xorFirst.toRadixString(16).padLeft(8, '0') +
      mulFirst.toRadixString(16).padLeft(8, '0');
}

// 32-bit h * 0x01000193 (the FNV prime) without a 64-bit product: the prime is
// 2^24 + 0x193, and h * 2^24 modulo 2^32 only keeps h's low byte.
int _mulPrime(int h) => (h * 0x193 + ((h & 0xFF) << 24)) & 0xFFFFFFFF;
