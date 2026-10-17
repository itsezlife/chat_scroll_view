import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The short text codes people type for emoji (`:grinning:`), by key.
///
/// The codes are the same in every language, so there is one table for the
/// catalog, not one per locale. Like a keyword pack it answers by the
/// structure's [ContentKey] and holds entries and gender variants only: a tone
/// variant has no code of its own, so a host shows its entry's.
///
/// ## Asset format
///
/// `shortcodes.tsv` is UTF-8 text, one record per line, fields separated by a
/// tab.
///
/// | Line | Meaning |
/// | --- | --- |
/// | `@emoji-catalog-shortcodes<TAB>1` | Format marker and version; first line. |
/// | `@source<TAB>emoji-toolkit 11.0.0` | Where the codes come from. |
/// | `1F600<TAB>:grinning:` | A record: key as in the structure, then its code. |
///
/// Codes are never empty and never contain a tab or a line break; [encode]
/// refuses one that does, so a table always reads back as written.
@immutable
final class EmojiShortcodes {
  /// Creates a table of [codes] taken from [source].
  EmojiShortcodes({
    required this.source,
    required Map<ContentKey$Unicode, String> codes,
  }) : codes = Map.unmodifiable(codes);

  /// Reads [text], the text of a `shortcodes.tsv`.
  ///
  /// Throws a [FormatException] on any line it cannot read or a key listed
  /// twice, so a damaged or newer-format asset fails loudly.
  factory EmojiShortcodes.decode(String text) {
    String? source;
    var sawMarker = false;
    final codes = <ContentKey$Unicode, String>{};
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\t');
      switch (fields.first) {
        case '@$_marker':
          if (fields.length != 2 || fields[1] != '$_formatVersion') {
            throw FormatException('Unsupported shortcodes format.', line);
          }
          sawMarker = true;
        case '@source':
          if (fields.length != 2 || fields[1].isEmpty) {
            throw FormatException('Expected one value.', line);
          }
          source = fields[1];
        default:
          if (fields.length != 2 || fields[1].isEmpty) {
            throw FormatException('Not a shortcode record.', line);
          }
          final key = switch (ContentKey.tryParse('unicode:${fields[0]}')) {
            final ContentKey$Unicode unicode => unicode,
            _ => throw FormatException('Not a code point sequence.', line),
          };
          if (codes.containsKey(key)) {
            throw FormatException('Key listed twice.', line);
          }
          codes[key] = fields[1];
      }
    }
    if (!sawMarker || source == null) {
      throw const FormatException('Missing shortcodes header.');
    }
    return EmojiShortcodes(source: source, codes: codes);
  }

  /// Where the codes come from, as a label (`emoji-toolkit 11.0.0`).
  final String source;

  /// The code of each key, in file order. Unmodifiable.
  final Map<ContentKey$Unicode, String> codes;

  /// The code of [key], or null when the table does not list it.
  String? operator [](ContentKey key) => codes[key];

  /// The `shortcodes.tsv` text of this table; [EmojiShortcodes.decode] reads
  /// back an equal one.
  ///
  /// Throws an [ArgumentError] when a code is empty, holds a tab or a line
  /// break, or starts or ends with whitespace.
  String encode() {
    final out = StringBuffer()
      ..writeln('@$_marker\t$_formatVersion')
      ..writeln('@source\t$source');
    for (final MapEntry(:key, value: code) in codes.entries) {
      if (code.isEmpty ||
          code.contains(RegExp(r'[\t\r\n]')) ||
          code != code.trim()) {
        throw ArgumentError.value(code, 'codes', 'Not representable.');
      }
      out.writeln('${key.encoded.substring(8)}\t$code');
    }
    return out.toString();
  }

  static const String _marker = 'emoji-catalog-shortcodes';
  static const int _formatVersion = 1;
}
