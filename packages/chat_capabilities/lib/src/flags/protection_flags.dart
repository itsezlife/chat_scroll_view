/// What protection denies for a chat or one message: each set flag is a
/// restriction.
///
/// A bit flag set with no payload, in the engine's message status idiom:
/// the representation is private, and only the named constants,
/// [fromBits] and the set operations are public. Equal sets are equal
/// integers.
///
/// | Bit | Flag             | Set means                          |
/// |-----|------------------|------------------------------------|
/// |  0  | `copy`           | messages may not be copied         |
/// |  1  | `forward`        | messages may not be forwarded      |
/// |  2  | `save`           | media may not be saved             |
/// |  3  | `captureBlocked` | screen capture is blocked          |
///
/// The bit order is the serialised form. A new flag takes the next free bit;
/// a removed flag's bit is never reused. At most 31 flags (bits 0 to 30), so
/// every value is a JavaScript small integer on the web.
///
/// Read from `ChatProtection.forMessage`, which adds a message's own flag to
/// the chat's.
extension type const ProtectionFlags._(int _bits) {
  /// The set a stored [bits] holds; bits of no known flag are dropped, so a
  /// value written by a newer build still decodes.
  ProtectionFlags.fromBits(int bits) : _bits = bits & _known;

  /// Nothing is protected.
  static const none = ProtectionFlags._(0);

  /// Messages may not be copied (menus and text selection).
  static const copy = ProtectionFlags._(1 << 0);

  /// Messages may not be forwarded.
  static const forward = ProtectionFlags._(1 << 1);

  /// Media may not be saved to the device.
  static const save = ProtectionFlags._(1 << 2);

  /// Screen capture is blocked while the chat shows.
  static const captureBlocked = ProtectionFlags._(1 << 3);

  /// Every flag, in bit order.
  static const values = [copy, forward, save, captureBlocked];

  static const _names = ['copy', 'forward', 'save', 'captureBlocked'];

  static const _known = (1 << 4) - 1;

  /// The serialised form.
  int get bits => _bits;

  /// Whether every flag of [flag] is set.
  bool contains(ProtectionFlags flag) => _bits & flag._bits == flag._bits;

  /// Whether no flag is set.
  bool get isEmpty => _bits == 0;

  /// The flags set in either.
  ProtectionFlags operator |(ProtectionFlags other) =>
      ProtectionFlags._(_bits | other._bits);

  /// The flags set in both.
  ProtectionFlags operator &(ProtectionFlags other) =>
      ProtectionFlags._(_bits & other._bits);

  /// These flags without those of [other].
  ProtectionFlags without(ProtectionFlags other) =>
      ProtectionFlags._(_bits & ~other._bits);

  /// The single flags set, in bit order.
  Iterable<ProtectionFlags> get flags => values.where(contains);

  /// The names of the flags set, in bit order, for logs and debug screens
  /// (an extension type prints as its integer).
  Iterable<String> get names => [
    for (final (index, flag) in values.indexed)
      if (contains(flag)) _names[index],
  ];
}
