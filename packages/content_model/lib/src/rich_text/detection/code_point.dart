/// Reading a code point out of a UTF-16 `String` by index, which Dart has no
/// call for: the scanners step through text by code unit and need whole code
/// points only where a character class is not ASCII.
abstract final class CodePoint {
  /// The code point starting at [index] in [text]; a lone surrogate is
  /// returned as itself.
  static int at(String text, int index) {
    final unit = text.codeUnitAt(index);
    if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) {
      final next = text.codeUnitAt(index + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        return 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
      }
    }
    return unit;
  }

  /// How many UTF-16 code units [codePoint] takes.
  static int width(int codePoint) => codePoint > 0xFFFF ? 2 : 1;
}
