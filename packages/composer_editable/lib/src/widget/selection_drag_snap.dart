/// Telegram `TextSelectionHelper.isInterruptedCharacter` — letter, digit, or `_`.
bool isInterruptedCharacter(String text, int index) {
  if (index < 0 || index >= text.length) {
    return false;
  }
  final int cu = text.codeUnitAt(index);
  if (cu == 0x5F) {
    return true; // '_'
  }
  // ASCII fast path
  if ((cu >= 0x30 && cu <= 0x39) ||
      (cu >= 0x41 && cu <= 0x5A) ||
      (cu >= 0x61 && cu <= 0x7A)) {
    return true;
  }
  // BMP letter/digit via Unicode categories (no surrogate pairing for snap).
  if (cu >= 0x80 && cu <= 0xFFFF) {
    final String ch = String.fromCharCode(cu);
    return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);
  }
  return false;
}

/// Start index of the interrupted-character run containing [index], or [index]
/// if that character is not interrupted.
int interruptedRunStart(String text, int index) {
  if (!isInterruptedCharacter(text, index)) {
    return index;
  }
  int i = index;
  while (i > 0 && isInterruptedCharacter(text, i - 1)) {
    i--;
  }
  return i;
}

/// End index (exclusive) of the interrupted-character run containing [index],
/// or `index + 1` / [index] when not interrupted.
int interruptedRunEnd(String text, int index) {
  if (index < 0) {
    return 0;
  }
  if (index >= text.length) {
    return text.length;
  }
  if (!isInterruptedCharacter(text, index)) {
    return index;
  }
  int i = index + 1;
  while (i < text.length && isInterruptedCharacter(text, i)) {
    i++;
  }
  return i;
}

/// Whether [extent] is moving away from [fixedBase] relative to [previousExtent]
/// (selection growing), not shrinking toward the fixed end.
bool isExpandingHandleDrag({
  required int fixedBase,
  required int extent,
  required int previousExtent,
}) {
  if (extent == fixedBase) {
    return false;
  }
  if (extent > fixedBase) {
    // Fixed on the left — expanding means extent moved further right (or stayed).
    return extent >= previousExtent;
  }
  // Fixed on the right — expanding means extent moved further left (or stayed).
  return extent <= previousExtent;
}

/// Snap handle [rawExtent] to interrupted-character run edges while **expanding**.
///
/// Shrinking toward [fixedBase] is never snapped — otherwise sticky run edges
/// fight character-by-character resize and oscillate with `_avoidCollapseExtent`
/// (extent jumps to runStart → nudge → next frame looks like expand → runEnd).
int snapExtentForHandleDrag({
  required String text,
  required int fixedBase,
  required int rawExtent,
  required int previousExtent,
}) {
  if (text.isEmpty) {
    return 0;
  }
  final int extent = rawExtent.clamp(0, text.length);
  if (extent == fixedBase) {
    return extent;
  }

  if (!isExpandingHandleDrag(
    fixedBase: fixedBase,
    extent: extent,
    previousExtent: previousExtent,
  )) {
    return extent;
  }

  final int probe = extent < text.length
      ? extent
      : (extent > 0 ? extent - 1 : 0);

  if (!isInterruptedCharacter(text, probe) &&
      !(extent > 0 && isInterruptedCharacter(text, extent - 1))) {
    return extent;
  }

  final int runStart = isInterruptedCharacter(text, probe)
      ? interruptedRunStart(text, probe)
      : interruptedRunStart(text, extent - 1);
  final int runEnd = isInterruptedCharacter(text, probe)
      ? interruptedRunEnd(text, probe)
      : interruptedRunEnd(text, extent - 1);

  if (extent <= runStart || extent >= runEnd) {
    return extent;
  }

  // Expanding through a run: stick to the far edge away from the fixed base.
  if (extent > fixedBase) {
    return runEnd;
  }
  return runStart;
}
