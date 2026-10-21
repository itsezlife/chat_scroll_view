import 'package:meta/meta.dart';

/// Who holds the bottom slot of the window: the soft keyboard alone, or the
/// panel, and in which phase.
///
/// The sealed **hand-off** states of the keyboard-replacement presentation.
/// Each is a fact about the slot, not a flag; an impossible combination, such
/// as a cold open that is also handing off, cannot be built.
@immutable
sealed class KeyboardSlotState {
  const KeyboardSlotState();

  /// Nothing but the soft keyboard (or nothing at all) holds the slot.
  static const KeyboardSlotState idle = KeyboardSlotState$Idle();

  /// The panel grows into a free slot: a cold open.
  static const KeyboardSlotState opening = KeyboardSlotState$Opening();

  /// The panel took the slot while the soft keyboard was still up beneath it.
  static const KeyboardSlotState replacing = KeyboardSlotState$Replacing();

  /// The panel holds the slot at rest.
  static const KeyboardSlotState open = KeyboardSlotState$Open();

  /// The panel shrinks out of the slot: a cold close.
  static const KeyboardSlotState closing = KeyboardSlotState$Closing();

  /// The panel keeps the slot, emptied, until the soft keyboard has risen to
  /// take it over, so the composer does not drop and rise again.
  static const KeyboardSlotState handOffToIme =
      KeyboardSlotState$HandOffToIme();

  /// Whether the panel holds the slot in any phase.
  bool get holdsSlot => switch (this) {
    KeyboardSlotState$Idle() => false,
    KeyboardSlotState$Opening() ||
    KeyboardSlotState$Replacing() ||
    KeyboardSlotState$Open() ||
    KeyboardSlotState$Closing() ||
    KeyboardSlotState$HandOffToIme() => true,
  };

  /// Whether the panel is on screen at rest, over a keyboard or not.
  bool get isAtRest => switch (this) {
    KeyboardSlotState$Open() || KeyboardSlotState$Replacing() => true,
    KeyboardSlotState$Idle() ||
    KeyboardSlotState$Opening() ||
    KeyboardSlotState$Closing() ||
    KeyboardSlotState$HandOffToIme() => false,
  };
}

/// See [KeyboardSlotState.idle].
final class KeyboardSlotState$Idle extends KeyboardSlotState {
  /// Idle.
  const KeyboardSlotState$Idle();

  @override
  String toString() => 'KeyboardSlotState.idle';
}

/// See [KeyboardSlotState.opening].
final class KeyboardSlotState$Opening extends KeyboardSlotState {
  /// Opening.
  const KeyboardSlotState$Opening();

  @override
  String toString() => 'KeyboardSlotState.opening';
}

/// See [KeyboardSlotState.replacing].
final class KeyboardSlotState$Replacing extends KeyboardSlotState {
  /// Replacing.
  const KeyboardSlotState$Replacing();

  @override
  String toString() => 'KeyboardSlotState.replacing';
}

/// See [KeyboardSlotState.open].
final class KeyboardSlotState$Open extends KeyboardSlotState {
  /// Open.
  const KeyboardSlotState$Open();

  @override
  String toString() => 'KeyboardSlotState.open';
}

/// See [KeyboardSlotState.closing].
final class KeyboardSlotState$Closing extends KeyboardSlotState {
  /// Closing.
  const KeyboardSlotState$Closing();

  @override
  String toString() => 'KeyboardSlotState.closing';
}

/// See [KeyboardSlotState.handOffToIme].
final class KeyboardSlotState$HandOffToIme extends KeyboardSlotState {
  /// Handing the slot to the soft keyboard.
  const KeyboardSlotState$HandOffToIme();

  @override
  String toString() => 'KeyboardSlotState.handOffToIme';
}
