import 'package:meta/meta.dart';

/// The one canonical identity of a piece of catalog content.
///
/// A key says _which_ content, never _what kind_: whether an item is a
/// sticker, a custom emoji or a GIF is a [ContentDescriptor] fact, so a key
/// can never disagree with the content it names. The set of variants is
/// closed:
///
/// - [ContentKey.unicode]: the full code point sequence actually shown or
///   sent.
/// - [ContentKey.document]: an opaque id of anything document-backed
///   (stickers, GIFs, custom emoji).
/// - [ContentKey.external]: an opaque id of web or inline-result content that
///   has no document.
///
/// Equality is exact value equality on the payload. Nothing is normalised, so
/// `☂` (U+2602) and `☂️` (U+2602 U+FE0F) are two keys; reconciling the
/// spellings of one emoji is the job of the catalog that owns them, not of the
/// identity.
///
/// Fetch credentials (access hashes, file references) and provenance are not
/// part of a key; the host that fetches the content keeps them, keyed by it.
///
/// ## Storage encoding
///
/// [encoded] is a stable, ASCII-safe string that [parse] and [tryParse] read
/// back to an equal key, so a key can be persisted and compared across runs:
///
/// | Variant | Encoding | Example |
/// | --- | --- | --- |
/// | unicode | `unicode:` and the code points as hex, `-`-separated | `unicode:1F44D-1F3FB` |
/// | document | `document:` and the id, verbatim | `document:5368` |
/// | external | `external:` and the id, verbatim | `external:https://host/a` |
///
/// The encoding is canonical on output (upper-case hex, at least four digits)
/// and generous on input (any hex case, one to six digits per code point).
@immutable
sealed class ContentKey {
  /// A key for the exact unicode [sequence] shown or sent.
  ///
  /// [sequence] must not be empty.
  const factory ContentKey.unicode(String sequence) = ContentKey$Unicode;

  /// A key for the document-backed content with the opaque [id].
  ///
  /// [id] must not be empty.
  const factory ContentKey.document(String id) = ContentKey$Document;

  /// A key for the web or inline-result content with the opaque [id].
  ///
  /// [id] must not be empty.
  const factory ContentKey.external(String id) = ContentKey$External;

  /// The key [encoded] was produced from.
  ///
  /// Throws a [FormatException] carrying [source] when it is not an encoded
  /// key. Use [tryParse] for persisted data that may be damaged or written by
  /// another version.
  factory ContentKey.parse(String source) =>
      tryParse(source) ??
      (throw FormatException('Not an encoded ContentKey.', source));

  const ContentKey._();

  /// The key [source] encodes, or null when it is not an encoded key: no known
  /// variant prefix, an empty payload, or a unicode payload that is not
  /// `-`-separated hex code points within the unicode range.
  static ContentKey? tryParse(String? source) => switch (source) {
    final text? => _parseTagged(text),
    null => null,
  };

  static ContentKey? _parseTagged(String text) {
    final separator = text.indexOf(':');
    if (separator < 0) return null;
    final payload = text.substring(separator + 1);
    if (payload.isEmpty) return null;
    return switch (text.substring(0, separator)) {
      _unicodeTag => _parseSequence(payload),
      _documentTag => ContentKey.document(payload),
      _externalTag => ContentKey.external(payload),
      _ => null,
    };
  }

  /// The stable storage string of this key; see the encoding table of
  /// [ContentKey].
  String get encoded;

  static const String _unicodeTag = 'unicode';
  static const String _documentTag = 'document';
  static const String _externalTag = 'external';

  static final RegExp _hexCodePoint = RegExp(r'^[0-9A-Fa-f]{1,6}$');
  static const int _maxCodePoint = 0x10FFFF;

  // Hex rather than the glyph: a sequence made of ZWJ and variation selectors
  // is invisible or ambiguous in logs and diffs, and hex is what Unicode
  // charts print.
  static String _hexCodePoints(String sequence) => [
    for (final codePoint in sequence.runes)
      codePoint.toRadixString(16).toUpperCase().padLeft(4, '0'),
  ].join('-');

  static ContentKey$Unicode? _parseSequence(String payload) {
    final codePoints = <int>[];
    for (final part in payload.split('-')) {
      if (!_hexCodePoint.hasMatch(part)) return null;
      final codePoint = int.parse(part, radix: 16);
      if (codePoint > _maxCodePoint) return null;
      codePoints.add(codePoint);
    }
    return ContentKey$Unicode(String.fromCharCodes(codePoints));
  }
}

/// A [ContentKey] for a unicode emoji sequence; see [ContentKey.unicode].
final class ContentKey$Unicode extends ContentKey {
  /// Creates the key for [sequence], which must not be empty.
  const ContentKey$Unicode(this.sequence)
    : assert(sequence != '', 'A unicode ContentKey needs a sequence.'),
      super._();

  /// The exact sequence shown or sent: ZWJ, variation selectors (FE0F) and
  /// modifiers are part of it and are never stripped.
  final String sequence;

  @override
  String get encoded => 'unicode:${ContentKey._hexCodePoints(sequence)}';

  @override
  bool operator ==(Object other) =>
      other is ContentKey$Unicode && other.sequence == sequence;

  @override
  int get hashCode => Object.hash(ContentKey$Unicode, sequence);

  @override
  String toString() =>
      'ContentKey.unicode(${ContentKey._hexCodePoints(sequence)})';
}

/// A [ContentKey] for document-backed content; see [ContentKey.document].
final class ContentKey$Document extends ContentKey {
  /// Creates the key for the document [id], which must not be empty.
  const ContentKey$Document(this.id)
    : assert(id != '', 'A document ContentKey needs an id.'),
      super._();

  /// The opaque document id. A string rather than an integer so 64-bit ids
  /// survive targets whose integers are doubles.
  final String id;

  @override
  String get encoded => 'document:$id';

  @override
  bool operator ==(Object other) =>
      other is ContentKey$Document && other.id == id;

  @override
  int get hashCode => Object.hash(ContentKey$Document, id);

  @override
  String toString() => 'ContentKey.document($id)';
}

/// A [ContentKey] for web or inline-result content; see
/// [ContentKey.external].
final class ContentKey$External extends ContentKey {
  /// Creates the key for the external [id], which must not be empty.
  const ContentKey$External(this.id)
    : assert(id != '', 'An external ContentKey needs an id.'),
      super._();

  /// The opaque id of the content, for example the result id of a web search.
  final String id;

  @override
  String get encoded => 'external:$id';

  @override
  bool operator ==(Object other) =>
      other is ContentKey$External && other.id == id;

  @override
  int get hashCode => Object.hash(ContentKey$External, id);

  @override
  String toString() => 'ContentKey.external($id)';
}
