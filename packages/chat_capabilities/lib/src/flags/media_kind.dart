/// A kind of media the user may send, one bit of a [MediaKindSet].
///
/// An enum rather than a flag constant of [MediaKindSet]: a kind is one
/// label of a closed set, so a consumer switches over it exhaustively and a
/// `denials` key can never be a set of several kinds.
///
/// Each kind's bit is fixed by its declaration ([MediaKindSet.bits] is the
/// serialised form). A new kind takes the next free bit and is declared
/// last; a removed kind leaves its bit unused for good, so a stored set
/// never reads as another kind.
///
/// | Bit | Kind         |
/// |-----|--------------|
/// |  0  | `photo`      |
/// |  1  | `video`      |
/// |  2  | `animation`  |
/// |  3  | `file`       |
/// |  4  | `audio`      |
/// |  5  | `voice`      |
/// |  6  | `roundVideo` |
///
/// At most 31 kinds (bits 0 to 30), so every set is a JavaScript small
/// integer on the web.
enum MediaKind {
  /// Still pictures.
  photo(0),

  /// Videos.
  video(1),

  /// GIFs and other silent looping clips; never tied to stickers here.
  animation(2),

  /// Files sent as documents.
  file(3),

  /// Music and other audio files.
  audio(4),

  /// Voice messages.
  voice(5),

  /// Round video messages.
  roundVideo(6);

  const MediaKind(this._bit);

  final int _bit;

  int get _mask => 1 << _bit;
}

/// A set of [MediaKind]s: which kinds the user may send.
///
/// A bit flag set with no payload, in the engine's message status idiom:
/// the representation is private, and only the named constants, [of],
/// [fromBits] and the set operations are public. Equal sets are equal
/// integers, so `==` and `hashCode` are the int's.
extension type const MediaKindSet._(int _bits) {
  /// The set of [kinds].
  MediaKindSet.of(Iterable<MediaKind> kinds)
    : _bits = kinds.fold(0, (bits, kind) => bits | kind._mask);

  /// The set a stored [bits] holds; bits of no known kind are dropped, so a
  /// value written by a newer build still decodes.
  MediaKindSet.fromBits(int bits) : _bits = bits & _known;

  /// No kind.
  static const none = MediaKindSet._(0);

  /// Every kind; the default of the sending group.
  static const all = MediaKindSet._(_known);

  // Bits 0 to 6, one per declared kind; a test pins it to MediaKind.values.
  static const _known = (1 << 7) - 1;

  /// The serialised form: kind `k` is bit `k`'s position in the table on
  /// [MediaKind].
  int get bits => _bits;

  /// Whether [kind] is in the set.
  bool contains(MediaKind kind) => _bits & kind._mask != 0;

  /// Whether the set holds no kind.
  bool get isEmpty => _bits == 0;

  /// The kinds in either set.
  MediaKindSet operator |(MediaKindSet other) =>
      MediaKindSet._(_bits | other._bits);

  /// The kinds in both sets.
  MediaKindSet operator &(MediaKindSet other) =>
      MediaKindSet._(_bits & other._bits);

  /// This set without the kinds of [other].
  MediaKindSet without(MediaKindSet other) =>
      MediaKindSet._(_bits & ~other._bits);

  /// The kinds in the set, in bit order.
  Iterable<MediaKind> get kinds => MediaKind.values.where(contains);
}
