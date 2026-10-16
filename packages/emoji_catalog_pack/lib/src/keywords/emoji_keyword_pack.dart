import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The spoken name and search keywords of one emoji sequence in one locale.
@immutable
final class EmojiKeywordRecord {
  /// Creates the record of [key].
  EmojiKeywordRecord({
    required this.key,
    required this.spokenName,
    required List<String> keywords,
  }) : keywords = List.unmodifiable(keywords);

  /// The sequence the record describes, spelled as the structure spells it.
  final ContentKey$Unicode key;

  /// The short name a screen reader speaks (CLDR's `tts`): never empty.
  final String spokenName;

  /// The search keywords in CLDR order. Unmodifiable; empty when the locale
  /// lists none for this sequence.
  final List<String> keywords;
}

/// The names and keywords of every emoji of the catalog in one locale.
///
/// A pack answers by [ContentKey], the same key the structure uses, and is
/// independent of the structure's version: a host may pair it with a pack it
/// fetched itself ([EmojiKeywordRecord] is all a keyword source has to provide).
///
/// ## Asset format
///
/// `keywords/<locale>.tsv` is UTF-8 text, one record per line, fields
/// separated by a tab.
///
/// | Line | Meaning |
/// | --- | --- |
/// | `@emoji-catalog-keywords<TAB>1` | Format marker and version; first line. |
/// | `@locale<TAB>de` | The CLDR locale id of the pack. |
/// | `@cldr<TAB>49` | The CLDR release the keywords come from. |
/// | `1F600<TAB>name<TAB>kw1\|kw2` | A record: key as in the structure, spoken name, then the keywords joined by `\|` (the field is absent when there are none). |
///
/// Names and keywords never contain a tab, a line break or the `|` separator;
/// [encode] refuses text that does, so a pack always reads back as written.
@immutable
final class EmojiKeywordPack {
  /// Creates a pack of [records] for [locale].
  ///
  /// Throws an [ArgumentError] when two records share a key.
  EmojiKeywordPack({
    required this.locale,
    required this.cldrVersion,
    required List<EmojiKeywordRecord> records,
  }) : records = List.unmodifiable(records),
       _byKey = {for (final record in records) record.key: record} {
    if (_byKey.length != records.length) {
      throw ArgumentError.value(records, 'records', 'Repeats a key.');
    }
  }

  /// Reads [source], the text of a `keywords/<locale>.tsv`.
  ///
  /// Throws a [FormatException] on any line it cannot read or a key listed
  /// twice, so a damaged or newer-format asset fails loudly.
  factory EmojiKeywordPack.decode(String source) {
    String? locale;
    String? cldr;
    var sawMarker = false;
    final records = <EmojiKeywordRecord>[];
    final seen = <ContentKey>{};
    for (final line in source.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\t');
      switch (fields.first) {
        case '@$_marker':
          if (fields.length != 2 || fields[1] != '$_formatVersion') {
            throw FormatException('Unsupported keyword pack format.', line);
          }
          sawMarker = true;
        case '@locale':
          locale = _single(fields, line);
        case '@cldr':
          cldr = _single(fields, line);
        default:
          final record = _record(fields, line);
          if (!seen.add(record.key)) {
            throw FormatException('Key listed twice.', line);
          }
          records.add(record);
      }
    }
    if (!sawMarker || locale == null || cldr == null) {
      throw const FormatException('Missing keyword pack header.');
    }
    return EmojiKeywordPack(
      locale: locale,
      cldrVersion: cldr,
      records: records,
    );
  }

  /// The CLDR locale id (`de`).
  final String locale;

  /// The CLDR release the keywords come from.
  final String cldrVersion;

  /// The records in file order. Unmodifiable.
  final List<EmojiKeywordRecord> records;

  final Map<ContentKey, EmojiKeywordRecord> _byKey;

  /// The record of [key], or null when the pack does not list it.
  EmojiKeywordRecord? operator [](ContentKey key) => _byKey[key];

  /// The `keywords/<locale>.tsv` text of this pack; [EmojiKeywordPack.decode]
  /// reads back an equal pack.
  ///
  /// Throws an [ArgumentError] when a name or keyword holds a tab, a line
  /// break or (for a keyword) the `|` separator, or when a name is empty.
  String encode() {
    final out = StringBuffer()
      ..writeln('@$_marker\t$_formatVersion')
      ..writeln('@locale\t$locale')
      ..writeln('@cldr\t$cldrVersion');
    for (final record in records) {
      _check(record.spokenName, 'spokenName', separator: false);
      for (final keyword in record.keywords) {
        _check(keyword, 'keywords', separator: true);
      }
      out.write('${_hex(record.key)}\t${record.spokenName}');
      if (record.keywords.isNotEmpty) {
        out.write('\t${record.keywords.join('|')}');
      }
      out.writeln();
    }
    return out.toString();
  }

  static const String _marker = 'emoji-catalog-keywords';
  static const int _formatVersion = 1;

  static String _hex(ContentKey$Unicode key) => key.encoded.substring(8);

  static void _check(String text, String name, {required bool separator}) {
    final bad =
        text.isEmpty ||
        text.contains(RegExp(r'[\t\r\n]')) ||
        (separator && text.contains('|')) ||
        text != text.trim();
    if (bad) {
      throw ArgumentError.value(text, name, 'Not representable in the pack.');
    }
  }

  static String _single(List<String> fields, String line) {
    if (fields.length != 2 || fields[1].isEmpty) {
      throw FormatException('Expected one value.', line);
    }
    return fields[1];
  }

  static EmojiKeywordRecord _record(List<String> fields, String line) {
    if (fields.length < 2 || fields.length > 3 || fields[1].isEmpty) {
      throw FormatException('Not a keyword record.', line);
    }
    final key = ContentKey.tryParse('unicode:${fields[0]}');
    if (key is! ContentKey$Unicode) {
      throw FormatException('Not a code point sequence.', line);
    }
    return EmojiKeywordRecord(
      key: key,
      spokenName: fields[1],
      keywords: fields.length == 3 ? fields[2].split('|') : const [],
    );
  }
}
